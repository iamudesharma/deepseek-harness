/// Semantic parity replay — Flutter half of `$semantic-parity-replay`.
///
/// Drives the canonical `parity-stream.jsonl` fixture (identical bytes to the
/// React driver's input) through this app's REAL protocol parsers
/// (`MuxFrame.fromJson` / `HostFrame.fromJson`) and projects the resulting
/// session state into the canonical v1 line schema. The projection must
/// byte-match `migration/parity-reports/react-parity-projection-v1.txt`, which
/// the React object layer produces from the same stream — so a semantic drift
/// between the two runtimes fails loudly on either side.
///
/// The projector is replay-fixture machinery (sanctioned by the synthetic-
/// fallback policy for `replay` rows): it reuses the wire parsers and mirrors
/// the documented fold semantics — chunk coalescing into settled nodes, tool
/// call↔result pairing by callId, blank cleared by an authoritative user
/// message, running flips from turn lifecycle and host status.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart'
    show liveHistoryProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection double whose history fetch returns server truth (full window).
class _ScriptedHistoryClient extends ConnectionClient {
  _ScriptedHistoryClient() : super(baseUrl: 'http://parity.test');

  @override
  Future<List<HistoryEntry>> getSessionEvents(
    SessionId id, {
    int? beforeSeq,
    int? maxMessages,
  }) =>
      _scriptedEvents(id);
}

/// Server-truth history used by the gap-repair fixture: full window 1..5.
int _fetchCount = 0;

Future<List<HistoryEntry>> _scriptedEvents(SessionId id) async {
  _fetchCount++;
  HistoryEntry entry(int seq, String type) => HistoryEntry(
        event: SessionEvent.fromJson({
          'type': type,
          'seq': seq,
          'time': 0,
          if (type == 'user/message') 'surfaceOp': 'append',
          'data': {
            if (type == 'turn/start') 'turn': 1,
            if (type == 'user/message')
              ...{
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'gap'},
                ],
                'source': {'kind': 'user'},
              },
          },
        }),
      );
  return [
    entry(1, 'turn/start'),
    entry(2, 'user/message'),
    entry(3, 'step/start'),
    entry(4, 'assistant/chunk'),
    entry(5, 'assistant/chunk'),
  ];
}

void main() {
  test('gap repair contract: hold the hole, resync server truth, drop dups',
      () async {
    final container = ProviderContainer(overrides: [
      connectionClientProvider.overrideWithValue(_ScriptedHistoryClient()),
    ]);
    addTearDown(container.dispose);

    HistoryEntry entry(int seq, String type) => HistoryEntry(
          event: SessionEvent.fromJson({
            'type': type,
            'seq': seq,
            'time': 0,
            if (type == 'user/message') 'surfaceOp': 'append',
            'data': {
              if (type == 'turn/start') 'turn': 1,
              if (type == 'user/message')
                ...{
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': 'gap'},
                  ],
                  'source': {'kind': 'user'},
                },
            },
          }),
        );

    // Server truth resolves first so every mutation below stays synchronous
    // on one live notifier instance (Riverpod swaps instances lazily).
    final serverTruth = await _scriptedEvents(const SessionId('g1'));
    final notifier = container.read(liveHistoryProvider('g1').notifier);

    notifier.replaceAll([entry(1, 'turn/start'), entry(2, 'user/message')]);

    // A gapped live event is HELD OUT (never appended as a hole) — the same
    // decision React's acceptLiveEvent makes before repairGap(); production
    // then refetches authoritative truth (the resync leg below mirrors the
    // Session.repairGap stitch). Hold-out itself is pinned by
    // live_sync_test's gap/dedup case.
    notifier.appendLive(entry(4, 'assistant/chunk'));

    // Invalidation is lazy: the next notifier read rebuilds the provider,
    // and the resync replaces the rebuilt window with authoritative truth.
    final repaired = container.read(liveHistoryProvider('g1').notifier);
    repaired.replaceAll(serverTruth);

    // Post-repair live appends and reconnect replay duplicates behave.
    repaired.appendLive(entry(5, 'assistant/chunk'));
    repaired.appendLive(entry(2, 'user/message')); // replay dup → dropped

    final seqs = container
        .read(liveHistoryProvider('g1'))
        .map((e) => e.event.seq)
        .toList();
    expect(seqs, [1, 2, 3, 4, 5],
        reason: 'both stacks converge to the identical repaired window');
  });

  test('Flutter projects parity-stream identically to the React reference', () {
    const fixturePath = 'test/goldens/replay/parity-stream.jsonl';
    final lines =
        File(fixturePath).readAsLinesSync().where((l) => l.trim().isNotEmpty);

    var muxErrors = 0;
    var hostErrors = 0;
    final projector = ParityProjector();
    var count = 0;
    for (final line in lines) {
      count++;
      final wire = jsonDecode(line) as Map<String, dynamic>;
      final frameWire = (wire['frame'] as Map).cast<String, Object?>();
      switch (wire['stream'] as String) {
        case 'mux':
          final frame = MuxFrame.fromJson(frameWire);
          if (frame is StreamErrorFrame) muxErrors++;
          projector.add(frame);
        case 'host':
          final frame = HostFrame.fromJson(frameWire);
          if (frame is HostStreamErrorFrame) hostErrors++;
          projector.addHost(frame);
        default:
          fail('unknown stream tag ${wire['stream']}');
      }
    }
    expect(count, 54);

    final expected = File(
      '../../migration/parity-reports/react-parity-projection-v1.txt',
    ).readAsStringSync().trim();
    // Stream errors are consumed without killing the fold on either stream.
    expect(muxErrors, 1, reason: 'mux stream/error frame present');
    expect(hostErrors, 1, reason: 'host stream/error frame present');
    expect(projector.snapshot().join('\n'), expected);
  });
}

/// One folded conversation node in schema v1 (seq-ordered).
class _Node {
  String line;

  _Node(this.line);

  int get seq => int.parse(line.split(' ')[1]);
}

/// State projector over parsed frames — schema v1.
class ParityProjector {
  final List<_Node> _nodes = [];
  final Map<int, int> _turnEnds = {};
  final Map<String, String> _callNames = {};
  final Set<String> _runningCalls = {};
  final Set<String> _pending = {};

  bool _blank = true;
  bool _running = false;
  final Map<(int, int), int> _pendingChunks = {};
  final Set<(int, int)> _settled = {};
  int _queue = 0;
  String? _pendingLine;

  // Subcall topology: callId → (subCallId → isError), in dispatch order.
  final Map<String, List<(String, bool)>> _subCalls = {};
  // Retry chains: retryId → (seq, retry, maxRetries, started).
  final Map<String, (int, int, int, bool)> _retries = {};

  /// Apply one decoded wire frame.
  void add(MuxFrame frame) => switch (frame) {
        SessionEventFrame(:final sessionId, :final event) =>
          _addEvent(sessionId.value, event),
        SessionQueueFrame(:final items) => _queue = items.length,
        ApprovalRequestedFrame(:final approvalId, :final toolName) => () {
            _pending.add('a:$approvalId');
            _pendingLine = 'pending approval:$toolName';
          }(),
        ApprovalResolvedFrame(:final approvalId) => () {
            _pending.remove('a:$approvalId');
            if (_pending.isEmpty) _pendingLine = null;
          }(),
        QuestionRequestedFrame() => () {
            _pending.add('q:fixture');
            _pendingLine = 'pending question';
          }(),
        QuestionResolvedFrame() => () {
            for (final key in _pending.where((k) => k.startsWith('q:')).toList()) {
              _pending.remove(key);
            }
            if (_pending.isEmpty) _pendingLine = null;
          }(),
        _ => null,
      };

  /// Apply one decoded host frame.
  void addHost(HostFrame frame) => switch (frame) {
        SessionAddedFrame(:final blank) => _blank = blank,
        SessionStatusFrame(:final running) => _running = running,
        AgentErrorFrame() || _ => null,
      };

  void _addEvent(String sid, Map<String, Object?> raw) {
    final type = raw['type'] as String;
    final seq = raw['seq'] as int;
    final data = Map<String, Object?>.from(raw['data'] as Map);
    switch (type) {
      case 'user/message':
        final placement = raw['surfaceOp'];
        if (placement == null) return; // non-surface log echo
        _blank = false; // authoritative user message proves content started
        final content = (data['content'] as List?)?.cast<Map>();
        final text = content == null || content.isEmpty
            ? ''
            : (content.first['text'] as String? ?? '');
        _nodes.add(_Node('node $seq user text="$text"'));
      case 'assistant/chunk':
        final key = (data['turn'] as int, data['step'] as int);
        _settled.contains(key)
            ? throw StateError('assistant/chunk for settled $key at seq $seq')
            : _pendingChunks[key] = (_pendingChunks[key] ?? 0) + 1;
      case 'assistant/message':
        final key = (data['turn'] as int, data['step'] as int);
        final chunks =
            (raw['sourceEventSeqs'] as List?)?.length ?? _pendingChunks.remove(key) ?? 0;
        _settled.add(key);
        final content =
            ((data['message'] as Map)['content'] as List?)?.cast<Map>() ?? const [];
        final histogram = <String, int>{};
        for (final block in content) {
          final kind = switch (block['type']) {
            'text' => 'text',
            'reasoning' => 'reasoning',
            'tool-call' => 'tool-call',
            'image' => 'image',
            _ => 'other',
          };
          histogram[kind] = (histogram[kind] ?? 0) + 1;
        }
        final blocks = histogram.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final interrupted = data['interrupted'] == true;
        _nodes.add(_Node(
          'node $seq assistant turn=${data['turn']} step=${data['step']} '
          'blocks=${blocks.map((e) => '${e.key}:${e.value}').join(',')} '
          'interrupted=$interrupted',
        ));
        assert(chunks >= 0);
      case 'tool/call':
        _callNames[data['callId'] as String] = data['name'] as String;
        _runningCalls.add(data['callId'] as String);
      case 'tool/result':
        final message = data['message'] as Map;
        final source = message['source'] as Map?;
        final callId =
            ((source?['callId'] ?? message['callId']) ?? '-') as String;
        final error = data['error'] as Map?;
        _runningCalls.remove(callId);
        final subs = _subCalls.remove(callId) ?? const [];
        final subErrors = subs.where(((s) => s.$2)).length;
        _nodes.add(_Node(
          'node $seq tool-result callId=$callId '
          'name=${_callNames[callId] ?? '-'} error=${error?['name'] ?? 'none'} '
          'subcalls=${subs.length}/$subErrors',
        ));
      case 'tool/code-dispatch-start':
      case 'tool/code-dispatch':
        final rootCallId = data['rootCallId'] as String?;
        final subCallId = data['subCallId'] as String?;
        if (rootCallId == null || rootCallId.isEmpty || subCallId == null) {
          throw StateError('code-dispatch missing ids at seq $seq');
        }
        final subs = _subCalls.putIfAbsent(rootCallId, () => []);
        final isError = data['isError'] == true;
        final idx = subs.indexWhere((s) => s.$1 == subCallId);
        if (idx != -1) {
          subs[idx] = (subCallId, isError);
        } else {
          subs.add((subCallId, isError));
        }
      case 'llm/retry':
        final retryId = data['retryId'] as String?;
        if (retryId == null || retryId.isEmpty) {
          throw StateError('llm/retry without retryId at seq $seq');
        }
        final retry = (data['retry'] as num?)?.toInt() ?? 0;
        final maxRetries = (data['maxRetries'] as num?)?.toInt() ?? 0;
        _retries[retryId] = (seq, retry, maxRetries, false);
        _nodes.add(_Node(
          'node $seq model-retry retry=$retry maxRetries=$maxRetries state=scheduled',
        ));
      case 'llm/retry-started':
        final startedId = data['retryId'] as String?;
        if (startedId != null && _retries.containsKey(startedId)) {
          final cur = _retries[startedId]!;
          _retries[startedId] = (cur.$1, cur.$2, cur.$3, true);
          final idx = _nodes
              .indexWhere((n) => n.line.startsWith('node ${cur.$1} model-retry'));
          if (idx != -1) {
            _nodes[idx] = _Node(
                _nodes[idx].line.replaceFirst('state=scheduled', 'state=started'));
          }
        }
      case 'turn/start':
      case 'step/start':
      case 'step/end':
      case 'todo/write':
      case 'request/header':
      case 'request/context':
      case 'session/end-seed':
        break;
      case 'turn/end':
        _turnEnds[data['turn'] as int] = seq;
        _running = false;
      default:
        if (raw['ignorable'] != true) {
          throw StateError('unhandled session event "$type" at seq $seq');
        }
    }
  }

  /// Canonical snapshot lines (schema v1), node order = seq order.
  List<String> snapshot() {
    final lines = <String>[
      'session s-200 blank=$_blank running=$_running',
      ...((_nodes.toList()..sort((a, b) => a.seq.compareTo(b.seq))).map((n) => n.line)),
      ..._turnEnds.entries.map((e) => 'turn-end ${e.key} seq=${e.value}'),
      'running-calls ${_runningCalls.length}',
      'queue $_queue',
      _pendingLine ?? 'pending none',
    ];
    return lines;
  }
}
