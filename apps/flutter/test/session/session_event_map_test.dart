import 'package:dsh_flutter/src/core/session/session_event_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionEventEnvelope.fromJson', () {
    test('decodes a core event with defaults (ignorable false, no surface metadata)', () {
      final envelope = SessionEventEnvelope.fromJson({
        'type': 'turn/start',
        'seq': 1,
        'time': 100,
        'data': {'turn': 1},
      });
      expect(envelope.isKnown, isTrue);
      expect(envelope.ignorable, isFalse);
      expect(envelope.isSurfaceEligible, isFalse);
      expect(envelope.data, {'turn': 1});
    });

    test('plugin extension types decode flagged unknown (merge-extensible map)', () {
      final envelope = SessionEventEnvelope.fromJson({
        'type': 'agent-team/journal',
        'seq': 2,
        'time': 0,
        'data': <String, Object?>{},
        'ignorable': true,
      });
      expect(envelope.isKnown, isFalse);
      expect(envelope.ignorable, isTrue);
    });

    test('surface metadata accepted only on surface-eligible members', () {
      final surface = SessionEventEnvelope.fromJson({
        'type': 'assistant/message',
        'seq': 3,
        'time': 0,
        'data': {'turn': 1, 'step': 1},
        'sourceEventSeqs': [1, 2],
        'surfaceOp': 'append',
      });
      expect(surface.sourceEventSeqs, [1, 2]);
      expect(surface.surfaceOp?.isReplace, isFalse);

      // Non-surface events never carry it — mirrors the compiler-enforced
      // Session.append constraint.
      expect(
        () => SessionEventEnvelope.fromJson({
          'type': 'turn/start',
          'seq': 4,
          'time': 0,
          'data': {},
          'sourceEventSeqs': [1],
        }),
        throwsArgumentError,
      );
    });

    test('replace surface op decodes the inclusive range', () {
      final op = SurfaceOp.fromJson({'op': 'replace', 'start': 3, 'end': 5});
      expect(op.isReplace, isTrue);
      expect(op.start, 3);
      expect(op.end, 5);
      expect(() => SurfaceOp.fromJson({'op': 'replace'}), throwsArgumentError);
    });

    test('malformed envelopes reject loudly', () {
      // seq must be an integer.
      expect(
        () => SessionEventEnvelope.fromJson({
          'type': 'turn/start', 'seq': '1', 'time': 0, 'data': {},
        }),
        throwsArgumentError,
      );
      // time is required.
      expect(
        () => SessionEventEnvelope.fromJson({
          'type': 'turn/start', 'seq': 1, 'data': {},
        }),
        throwsArgumentError,
      );
      // ignorable only carries the literal true.
      expect(
        () => SessionEventEnvelope.fromJson({
          'type': 'turn/start', 'seq': 1, 'time': 0, 'data': {}, 'ignorable': false,
        }),
        throwsArgumentError,
      );
    });
  });

  group('required-on-read gate', () {
    test('unrecognized required event refuses reconstruction', () {
      final envelope = SessionEventEnvelope.fromJson({
        'type': 'agent-team/journal',
        'seq': 9,
        'time': 0,
        'data': <String, Object?>{},
      });
      expect(envelope.isKnown, isFalse);
      expect(
        () => envelope.requireKnown(),
        throwsA(predicate((e) =>
            e is StateError &&
            e.message.contains('refusing reconstruction') &&
            e.message.contains('agent-team/journal') &&
            e.message.contains('seq 9'))),
      );
    });

    test('unrecognized ignorable event passes the gate', () {
      final envelope = SessionEventEnvelope.fromJson({
        'type': 'plugin/heartbeat',
        'seq': 10,
        'time': 0,
        'data': <String, Object?>{},
        'ignorable': true,
      });
      expect(envelope.requireKnown(), same(envelope));
    });

    test('unknown-to-consumer but core-known types pass the gate', () {
      final envelope = SessionEventEnvelope.fromJson({
        'type': 'request/header',
        'seq': 11,
        'time': 0,
        'data': {'reason': 'initial'},
      });
      expect(envelope.requireKnown().isKnown, isTrue);
    });
  });
}
