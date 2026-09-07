/// Deterministic session-stream folding for the headless replay harness
/// (P0 exit criteria, migration/plan.md): recorded mux/host frames decode
/// through the extracted protocol parsers, fold in stream order, and render
/// through the slot system as a stable transcript snapshot.
///
/// The fold is intentionally minimal — one stable line per frame from raw
/// contract fields. Typed ConversationNode assembly is a separate P0 row;
/// this layer only proves decode → host → slots → render end-to-end and
/// byte-stable across runs.
library;

import 'package:flutter/material.dart';

import '../api/frames.dart';
import '../plugin/plugin_contract.dart';
import '../plugin/plugin_host.dart';
import '../renderer/slot_outlet.dart';
import '../slots/slot_registry.dart';
import 'session_event_map.dart';

/// Folds decoded frames into ordered transcript lines.
///
/// Session events route through [SessionEventEnvelope] — required-unknown
/// types refuse reconstruction, ignorable unknowns record a skip line, and
/// `assistant/chunk`s coalesce into their step's in-flight buffer until the
/// settled `assistant/message` lands. A chunk arriving after its step's
/// message throws: settled nodes are never mutated by in-flight state.
class TranscriptFolder {
  final List<String> _lines = [];

  /// (turn, step) → coalesced chunk count awaiting its assembled message.
  final Map<(int, int), int> _pendingChunks = {};

  /// Settled (turn, step) pairs; further chunks for these are violations.
  final Set<(int, int)> _settled = {};

  /// Folds one already-decoded mux or host frame.
  void add(Object frame) {
    switch (frame) {
      case SessionSubscribedFrame(sessionId: final sid, lastSeq: final seq):
        _lines.add('subscribe $sid lastSeq=$seq');
      case SessionEventFrame(sessionId: final sid, event: final raw):
        _foldEvent(sid.value, SessionEventEnvelope.fromJson(raw));
      case SessionQueueFrame(sessionId: final sid, items: final items):
        _lines.add('queue $sid items=${items.length}');
      case SessionJobsFrame(sessionId: final sid, jobs: final jobs):
        _lines.add('jobs $sid count=${jobs.length}');
      case SessionProjectionFrame(
        sessionId: final sid,
        key: final key,
        seq: final seq,
      ):
        _lines.add('projection $sid $key@$seq');
      case ApprovalRequestedFrame(sessionId: final sid, toolName: final tool):
        _lines.add('approval-requested $sid $tool');
      case ApprovalResolvedFrame(sessionId: final sid, outcome: final outcome):
        _lines.add('approval-resolved $sid $outcome');
      case QuestionRequestedFrame(sessionId: final sid):
        _lines.add('question-requested $sid');
      case StreamErrorFrame(error: final error):
        _lines.add('stream-error ${error.code.wire}');
      case SessionAddedFrame(sessionId: final sid, blank: final blank):
        _lines.add('host session-added $sid blank=$blank');
      case SessionRemovedFrame(sessionId: final sid):
        _lines.add('host session-removed $sid');
      case SessionStatusFrame(sessionId: final sid, running: final running):
        _lines.add('host session-status $sid running=$running');
      case AgentErrorFrame(sessionId: final sid):
        _lines.add('host agent-error $sid');
      case WorkspaceChangedFrame(workspace: final workspace):
        _lines.add('host workspace-changed ${workspace['workspaceId'] ?? '?'}');
      case WorkspaceOrderChangedFrame(workspaceIds: final ids):
        _lines.add('host workspace-order-changed count=${ids.length}');
      case ArchivedSessionsChangedFrame(archivedSessionIds: final ids):
        _lines.add('host archived-sessions-changed count=${ids.length}');
      case RemoteEventFrame(event: final event):
        _lines.add('host remote-event $event');
      case HostStreamErrorFrame(error: final error):
        _lines.add('stream-error ${error.code.wire}');
    }
  }

  void _foldEvent(String sid, SessionEventEnvelope envelope) {
    // Required-on-read gate: unrecognized required types refuse reconstruction.
    envelope.requireKnown();

    if (!envelope.isKnown) {
      // Plugin extension marked safe to skip.
      _lines.add('${_prefix(sid, envelope)} ignorable-skip');
      return;
    }

    switch (envelope.type) {
      case 'user/message':
        final placement = switch (envelope.surfaceOp) {
          null => '-',
          SurfaceOp(:final isReplace) when !isReplace => 'append',
          _ => 'replace',
        };
        _lines.add('${_prefix(sid, envelope)} $placement');
      case 'assistant/chunk':
        final key = (
          envelope.data['turn'] as int,
          envelope.data['step'] as int,
        );
        if (_settled.contains(key)) {
          throw StateError(
            'assistant/chunk for settled turn=${key.$1} step=${key.$2} at seq ${envelope.seq} '
            '— settled nodes are never mutated by in-flight streaming state',
          );
        }
        _pendingChunks[key] = (_pendingChunks[key] ?? 0) + 1;
      case 'assistant/message':
        final key = (
          envelope.data['turn'] as int,
          envelope.data['step'] as int,
        );
        final chunks =
            envelope.sourceEventSeqs?.length ?? _pendingChunks.remove(key) ?? 0;
        _settled.add(key);
        final interrupted = envelope.data['interrupted'] == true
            ? ' interrupted'
            : '';
        _lines.add('${_prefix(sid, envelope)} chunks=$chunks$interrupted');
      case 'tool/call':
        _lines.add(
          '${_prefix(sid, envelope)} call=${envelope.data['callId']} name=${envelope.data['name']}',
        );
      case 'tool/result':
        final error = envelope.data['error'];
        final suffix = error == null ? '' : ' error=${(error as Map)['name']}';
        _lines.add(
          '${_prefix(sid, envelope)} result=${(envelope.data['message'] as Map)['callId'] ?? '-'}$suffix',
        );
      case 'turn/start':
        _lines.add('${_prefix(sid, envelope)} turn=${envelope.data['turn']}');
      case 'turn/end':
        _lines.add(
          '${_prefix(sid, envelope)} turn=${envelope.data['turn']} reason=${envelope.data['reason']}',
        );
      case 'step/start':
        _lines.add(
          '${_prefix(sid, envelope)} t=${envelope.data['turn']} s=${envelope.data['step']}',
        );
      case 'step/end':
        _lines.add(
          '${_prefix(sid, envelope)} t=${envelope.data['turn']} s=${envelope.data['step']}',
        );
      case 'todo/write':
        _lines.add(
          '${_prefix(sid, envelope)} todos=${(envelope.data['todos'] as List).length}',
        );
      case 'request/header':
        _lines.add(
          '${_prefix(sid, envelope)} header=${envelope.data['reason']}',
        );
      case 'request/context':
        _lines.add(
          '${_prefix(sid, envelope)} ctx=${envelope.data['provider']}/${envelope.data['model']}',
        );
      case 'session/end-seed':
        _lines.add('${_prefix(sid, envelope)} end-seed');
      default:
        // Merged plugin extensions render one generic line; their payload
        // typing belongs to each owning workstream.
        if (kPluginSessionEventTypes.contains(envelope.type)) {
          _lines.add('${_prefix(sid, envelope)} extension');
          return;
        }
        throw StateError('unhandled known session event "${envelope.type}"');
    }
  }

  String _prefix(String sid, SessionEventEnvelope envelope) =>
      'event $sid seq=${envelope.seq} ${envelope.type}';

  /// Number of folded frames.
  int get length => _lines.length;

  /// The stable snapshot: every folded line in stream order, newline-joined.
  String snapshot() => _lines.join('\n');
}

/// Declares `'root'` with the `'replay.transcript'` hole and renders that
/// hole through [SlotOutlet] — the fixture-scale mirror of the app shell's
/// shape in [package:dsh_flutter/src/core/bootstrap/app_plugins.dart].
class ReplayShellPlugin extends DshPlugin {
  /// Creates the shell around one ledger.
  ReplayShellPlugin(this.registry);

  /// The host's composition ledger.
  final SlotRegistry registry;

  @override
  String get id => '@replay/shell';

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.onDispose(
      ctx.slots.register(
        const RegistrationOptions(
          name: 'root',
          children: {
            'replay.transcript': SlotSpec(
              kind: SlotKind.list,
              scope: SlotScope.root,
            ),
          },
        ),
        (BuildContext context, SlotComponentProps props) =>
            SlotOutlet(registry: registry, slotKey: 'replay.transcript'),
      ),
    );
  }
}

/// Registers the fold renderer so a widget tree displays the snapshot the way
/// production features render their contributions: through slots, not imports.
class ReplayTranscriptPlugin extends DshPlugin {
  /// Creates the plugin around one folder instance.
  ReplayTranscriptPlugin(this.folder);

  /// The shared folder this plugin renders.
  final TranscriptFolder folder;

  @override
  String get id => '@replay/transcript';

  @override
  Future<void> apply(DshContext ctx) async {
    ctx.onDispose(
      ctx.slots.register(
        const RegistrationOptions(name: 'replay.transcript', id: 'fold'),
        (BuildContext context, SlotComponentProps props) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in folder.snapshot().split('\n'))
              Text(line, key: ValueKey(line), textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
  }
}

/// Assembles a host whose root declares `'replay.transcript'` and whose fold
/// renderer displays [folder]. Activation is left to the caller.
PluginHost buildReplayHost(TranscriptFolder folder) {
  final host = PluginHost();
  host.provide('slots', host.slots);
  host.register(ReplayShellPlugin(host.slots));
  host.register(ReplayTranscriptPlugin(folder));
  return host;
}
