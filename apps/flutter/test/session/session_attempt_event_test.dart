import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/transcript_fold.dart';
import 'package:dsh_flutter/src/plugins/conversation/nodes/conversation_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the failed-attempt vocabulary (`assistant/attempt`
/// + `feedback/message-*`): a provider error settles an attempt with no
/// surface message, and the Host logs it as a required event. An older
/// Flutter build refused the whole reconstruction (`refusing
/// reconstruction: unrecognized required event "assistant/attempt"`), which
/// surfaced as the full-screen red error. These events are log-only —
/// React's deriveMessages skips them too — so the fix is vocabulary, not a
/// new row.
void main() {
  Map<String, Object?> attemptJson({int seq = 14}) {
    return {
      'type': 'assistant/attempt',
      'seq': seq,
      'time': 1700000000000,
      'data': {
        'turn': 2,
        'step': 1,
        'stream': [],
      },
    };
  }

  group('assistant/attempt vocabulary', () {
    test('decodes known, passes the gate, carries no surface metadata', () {
      final envelope = SessionEventEnvelope.fromJson(attemptJson());
      expect(envelope.isKnown, isTrue);
      expect(envelope.isCore, isTrue);
      expect(envelope.isSurfaceEligible, isFalse);
      expect(envelope.requireKnown(), same(envelope));
    });

    test('folder accepts the attempt with no surface node', () {
      final folder = ConversationNodeFolder()
        ..add(SessionEventEnvelope.fromJson(attemptJson()));
      // Log-only: the attempt records no chat row (React deriveMessages
      // parity) but must not refuse reconstruction.
      expect(folder.snapshot().nodes, isEmpty);
    });

    test('diagnostic fold renders one line, never a message row', () {
      final folder = TranscriptFolder()
        ..add(
          SessionEventFrame(
            sessionId: SessionId('s1'),
            event: attemptJson(),
          ),
        );
      final snapshot = folder.snapshot();
      expect(snapshot, contains('assistant/attempt'));
      expect(snapshot, contains('t=2 s=1'));
    });
  });

  group('feedback message vocabulary', () {
    test('put and delete decode known and pass the gate', () {
      for (final entry in [
        {
          'type': 'feedback/message-put',
          'data': {
            'sessionId': 's1',
            'item': {'messageId': 'm1'},
          },
        },
        {
          'type': 'feedback/message-delete',
          'data': {'sessionId': 's1', 'messageId': 'm1'},
        },
      ]) {
        final envelope = SessionEventEnvelope.fromJson({
          ...entry,
          'seq': 20,
          'time': 1700000000000,
        });
        expect(envelope.isKnown, isTrue);
        expect(envelope.requireKnown(), same(envelope));
      }
    });

    test('folder accepts feedback mutations with no surface node', () {
      final folder = ConversationNodeFolder()
        ..add(
          SessionEventEnvelope.fromJson({
            'type': 'feedback/message-put',
            'seq': 20,
            'time': 1700000000000,
            'data': {
              'sessionId': 's1',
              'item': {'messageId': 'm1'},
            },
          }),
        );
      expect(folder.snapshot().nodes, isEmpty);
    });
  });
}
