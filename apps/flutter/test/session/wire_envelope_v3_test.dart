import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

extension on ConversationNodeFolder {
  void forEach(Iterable<SessionEventEnvelope> events) {
    for (final e in events) {
      add(e);
    }
  }

  List<String> toLines() => snapshot().toTranscriptLines();
}

/// Session-log-v3 wire envelope parity vectors (Host `surface.ts`,
/// `session-wire-event.ts`, `transport.ts` at upstream 5dda764).
Map<String, Object?> _wire(
  String type,
  int seq,
  Map<String, Object?> data, {
  Object? surfaceOp,
  Object? sourceEventSeqs,
  bool ignorable = false,
  bool omitData = false,
  Map<String, Object?> extra = const {},
}) => {
  'type': type,
  'seq': seq,
  'time': seq * 1000,
  if (!omitData) 'data': data,
  if (surfaceOp != null) 'surfaceOp': surfaceOp,
  if (sourceEventSeqs != null) 'sourceEventSeqs': sourceEventSeqs,
  if (ignorable) 'ignorable': true,
  ...extra,
};

Object _replace(int startSeq, int endSeq) =>
    {'op': 'replace', 'startSeq': startSeq, 'endSeq': endSeq};

Map<String, Object?> _messageData(String text) => {
  'message': {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

Map<String, Object?> _systemData(String text) => {
  'turn': 0,
  'step': 0,
  'message': {
    'role': 'system',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

void main() {
  group('v3 wire envelope decode', () {
    test('valid v3 replace envelope decodes startSeq/endSeq', () {
      final envelope = SessionEventEnvelope.fromJson(
        _wire(
          'user/message',
          5,
          {'content': 'condensed'},
          surfaceOp: _replace(3, 3),
          sourceEventSeqs: [3],
        ),
      );
      expect(envelope.surfaceOp?.isReplace, isTrue);
      expect(envelope.surfaceOp?.startSeq, 3);
      expect(envelope.surfaceOp?.endSeq, 3);
      expect(envelope.sourceEventSeqs, [3]);
    });

    test('valid system/message envelope is surface-eligible', () {
      final envelope = SessionEventEnvelope.fromJson(
        _wire(
          'system/message',
          0,
          _systemData('Be brief.'),
          surfaceOp: 'append',
        ),
      );
      expect(envelope.isKnown, isTrue);
      expect(envelope.isSurfaceEligible, isTrue);
    });

    test('invalid sequence rejected (negative, fractional)', () {
      expect(
        () => SessionEventEnvelope.fromJson(
          _wire('turn/start', -1, {'turn': 1}),
        ),
        throwsArgumentError,
      );
      expect(
        () => SessionEventEnvelope.fromJson({
          'type': 'turn/start',
          'seq': 1.5,
          'time': 0,
          'data': {'turn': 1},
        }),
        throwsArgumentError,
      );
    });

    test('malformed surface ops rejected; legacy start/end bridged', () {
      // Wrong shapes throw.
      for (final bad in [
        {'op': 'replace', 'startSeq': 1},
        {'op': 'replace', 'startSeq': 1, 'endSeq': 2, 'extra': true},
        {'op': 'replace', 'startSeq': -1, 'endSeq': 2},
        {'op': 'replace', 'startSeq': '1', 'endSeq': 2},
        'replace',
      ]) {
        expect(
          () => SessionEventEnvelope.fromJson(
            _wire('user/message', 5, {}, surfaceOp: bad),
          ),
          throwsArgumentError,
          reason: 'op $bad must throw',
        );
      }
      // TODO(K5): legacy bridge — fork Host still emits start/end.
      final legacy = SessionEventEnvelope.fromJson(
        _wire('user/message', 5, {}, surfaceOp: {
          'op': 'replace',
          'start': 3,
          'end': 3,
        }),
      );
      expect(legacy.surfaceOp?.startSeq, 3);
      expect(legacy.surfaceOp?.endSeq, 3);
    });

    test('unknown ignorable events retain opaque metadata', () {
      final envelope = SessionEventEnvelope.fromJson(
        _wire(
          'future/extension',
          9,
          {},
          surfaceOp: {'opaque': [1, 2]},
          sourceEventSeqs: 'not-a-list',
          ignorable: true,
        ),
      );
      expect(envelope.isKnown, isFalse);
      expect(envelope.requireKnown(), same(envelope));
      expect(envelope.surfaceOpJson, {'opaque': [1, 2]});
      expect(envelope.sourceEventSeqs, 'not-a-list');
    });

    test('replay gate: strict envelope (unexpected key, missing data)', () {
      expect(
        () => assertSessionWireEvent(
          _wire('turn/start', 1, {'turn': 1}, extra: {'future': 1}),
        ),
        throwsArgumentError,
      );
      expect(
        () => assertSessionWireEvent(
          _wire('turn/start', 1, {'turn': 1}, omitData: true),
        ),
        throwsArgumentError,
      );
      expect(
        () => assertSessionWireEvent(
          _wire('turn/start', 1, {'turn': 1}, extra: {'ignorable': 'yes'}),
        ),
        throwsArgumentError,
      );
      // Valid record passes with metadata validated.
      final ok = assertSessionWireEvent(
        _wire(
          'user/message',
          5,
          {'content': 'hi'},
          surfaceOp: 'append',
        ),
      );
      expect(ok.seq, 5);
    });
  });

  group('surface metadata validation', () {
    test('stale endpoints rejected (startSeq/endSeq must precede seq)', () {
      final envelope = SessionEventEnvelope.fromJson(
        _wire('user/message', 3, {}, surfaceOp: _replace(3, 4)),
      );
      expect(() => validateSurfaceMetadata(envelope), throwsArgumentError);
    });

    test('source seq rules (empty, dupes, future, non-array)', () {
      for (final bad in [<int>[], [2, 2], [9], 'x']) {
        final envelope = SessionEventEnvelope.fromJson(
          _wire('user/message', 5, {}, surfaceOp: _replace(1, 2),
              sourceEventSeqs: bad),
        );
        expect(
          () => validateSurfaceMetadata(envelope),
          throwsArgumentError,
          reason: 'seqs $bad must throw',
        );
      }
    });

    test('assistant/message cannot cite sources', () {
      final envelope = SessionEventEnvelope.fromJson(
        _wire('assistant/message', 5, {'turn': 1, 'step': 1},
            sourceEventSeqs: [3]),
      );
      expect(() => validateSurfaceMetadata(envelope), throwsArgumentError);
    });

    test('tool/result error requires content[0].isError', () {
      final bad = SessionEventEnvelope.fromJson(
        _wire('tool/result', 7, {
          'message': {
            'callId': 'c1',
            'content': [
              {'type': 'text', 'text': 'boom'},
            ],
          },
          'error': {'name': 'ToolError'},
        }),
      );
      expect(() => validateSessionEventData(bad), throwsArgumentError);
      final ok = SessionEventEnvelope.fromJson(
        _wire('tool/result', 7, {
          'message': {
            'callId': 'c1',
            'content': [
              {'type': 'text', 'text': 'boom', 'isError': true},
            ],
          },
          'error': {'name': 'ToolError'},
        }),
      );
      expect(() => validateSessionEventData(ok), returnsNormally);
    });

    test('request/header must omit system and empty collections', () {
      final withSystem = SessionEventEnvelope.fromJson(
        _wire('request/header', 1, {
          'header': {'system': 'x'},
        }),
      );
      expect(
        () => validateSessionEventData(withSystem),
        throwsArgumentError,
      );
      final emptyTools = SessionEventEnvelope.fromJson(
        _wire('request/header', 1, {
          'header': {'tools': []},
        }),
      );
      expect(
        () => validateSessionEventData(emptyTools),
        throwsArgumentError,
      );
    });
  });

  group('empty-content projection', () {
    test('empty system/assistant project to null; user projects verbatim', () {
      final emptyAssistant = SessionEventEnvelope.fromJson(
        _wire('assistant/message', 5, {
          'turn': 1,
          'step': 1,
          'message': {'role': 'assistant', 'content': []},
        }),
      );
      expect(deriveEventMessageText(emptyAssistant), isNull);
      final emptySystem = SessionEventEnvelope.fromJson(
        _wire('system/message', 0, {
          'message': {'role': 'system', 'content': []},
        }),
      );
      expect(deriveEventMessageText(emptySystem), isNull);
      final user = SessionEventEnvelope.fromJson(
        _wire('user/message', 2, {'content': 'go'}),
      );
      expect(deriveEventMessageText(user), isNotNull);
      final system = SessionEventEnvelope.fromJson(
        _wire('system/message', 0, _systemData('Be brief.')),
      );
      expect(deriveEventMessageText(system), 'Be brief.');
    });
  });

  group('SessionEvent threading (history-hole fix)', () {
    test('surface metadata survives decode and round-trip', () {
      final event = SessionEvent.fromJson(
        _wire(
          'user/message',
          5,
          {'content': 'condensed'},
          surfaceOp: _replace(3, 3),
          sourceEventSeqs: [3],
        ).cast<String, dynamic>(),
      );
      expect(event.surfaceOp?.startSeq, 3);
      expect(event.surfaceOp?.endSeq, 3);
      final envelope = SessionEventEnvelope.fromJson(
        event.toJson().cast<String, Object?>(),
      );
      expect(envelope.surfaceOp?.isReplace, isTrue);
      expect(envelope.surfaceOp?.startSeq, 3);
      expect(envelope.sourceEventSeqs, [3]);
    });

    test('malformed surfaceOp throws at decode instead of dropping', () {
      expect(
        () => SessionEvent.fromJson(
          _wire('user/message', 5, {}, surfaceOp: {'op': 'replace'})
              .cast<String, dynamic>(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('compaction and head rewrite (new wire keys)', () {
    test('packet pair with startSeq/endSeq folds to a CompactionNode', () {
      final folder = ConversationNodeFolder()
        ..add(
          SessionEventEnvelope.fromJson(
            _wire('user/message', 1, {
              'content': [
                {'type': 'text', 'text': 'keep'},
              ],
            }, surfaceOp: 'append'),
          ),
        )
        ..add(
          SessionEventEnvelope.fromJson(
            _wire('user/message', 2, {
              'content': [
                {'type': 'text', 'text': 'shadow-me'},
              ],
            }, surfaceOp: 'append'),
          ),
        )
        ..add(
          SessionEventEnvelope.fromJson(
            _wire('compaction/summary', 3, {
              'summary': [
                {'type': 'text', 'text': 'condensed history'},
              ],
              'shadowedSeqs': [2],
              'shadowedTokenCount': 512,
            }),
          ),
        )
        ..add(
          SessionEventEnvelope.fromJson(
            _wire('user/message', 4, {
              'content': [
                {'type': 'text', 'text': 'condensed history'},
              ],
            }, surfaceOp: _replace(1, 1)),
          ),
        )
        ..add(
          SessionEventEnvelope.fromJson(
            _wire('compaction/end', 5, {}),
          ),
        );
      final nodes = folder.snapshot().nodes;
      final compactions = nodes.whereType<CompactionNode>().toList();
      expect(compactions, hasLength(1));
      expect(compactions.single.text, 'condensed history');
      final users = nodes.whereType<UserMessageNode>().map((n) => n.text);
      expect(users, ['keep']);
    });

    test('system/message appends a system row; replace rewrites the head', () {
      final folder = ConversationNodeFolder()
        ..add(
          SessionEventEnvelope.fromJson(
            _wire('system/message', 0, _systemData('Be brief.'),
                surfaceOp: 'append'),
          ),
        );
      var systems = folder.snapshot().nodes.whereType<SystemPromptNode>();
      expect(systems, hasLength(1));
      expect(systems.single.text, 'Be brief.');
      // Head rewrite over node 0 updates in place (no second row).
      folder.add(
        SessionEventEnvelope.fromJson(
          _wire('system/message', 6, _systemData('Be very brief.'),
              surfaceOp: _replace(0, 0), sourceEventSeqs: [0]),
        ),
      );
      systems = folder.snapshot().nodes.whereType<SystemPromptNode>();
      expect(systems, hasLength(1));
      expect(systems.single.text, 'Be very brief.');
      // Empty content records "no system prompt": the row goes away.
      folder.add(
        SessionEventEnvelope.fromJson(
          _wire('system/message', 7, {
            'message': {'role': 'system', 'content': []},
          }, surfaceOp: _replace(0, 0), sourceEventSeqs: [6]),
        ),
      );
      expect(
        folder.snapshot().nodes.whereType<SystemPromptNode>(),
        isEmpty,
      );
    });

    test('new-key history folds deterministically across runs', () {
      List<SessionEventEnvelope> script() => [
        SessionEventEnvelope.fromJson(
          _wire('turn/start', 1, {'turn': 1}),
        ),
        SessionEventEnvelope.fromJson(
          _wire('user/message', 2, {'content': 'go'}, surfaceOp: 'append',
              sourceEventSeqs: []),
        ),
        SessionEventEnvelope.fromJson(
          _wire('assistant/message', 3, {
            'turn': 1,
            'step': 1,
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'hi'},
              ],
            },
          }, surfaceOp: 'append'),
        ),
      ];
      final a = ConversationNodeFolder()..forEach(script());
      final b = ConversationNodeFolder()..forEach(script());
      expect(a.toLines(), b.toLines());
    });
  });
}
