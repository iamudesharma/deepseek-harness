/// Composer stop-posture unit tests — pure port of InputBar.tsx
/// `primaryStops` / `interruptible`: a running ordinary session turns the
/// primary disc into Stop over an empty (or owner-blocked) draft, while a
/// running subagent session keeps Send primary with an independent Stop.
library;

import 'package:dsh_flutter/src/plugins/conversation/ui/composer.dart'
    show composerStopPosture;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('composerStopPosture', () {
    test('idle session never stops', () {
      const posture = (
        primaryStops: false,
        independentStop: false,
      );
      expect(
        composerStopPosture(
          running: false,
          origin: null,
          draftEmpty: true,
          enabled: true,
        ),
        posture,
      );
    });

    test('running ordinary session with empty draft stops primary', () {
      final posture = composerStopPosture(
        running: true,
        origin: null,
        draftEmpty: true,
        enabled: true,
      );
      expect(posture.primaryStops, isTrue);
      expect(posture.independentStop, isFalse);
    });

    test('running ordinary session with draft keeps send primary', () {
      final posture = composerStopPosture(
        running: true,
        origin: null,
        draftEmpty: false,
        enabled: true,
      );
      expect(posture.primaryStops, isFalse);
      expect(posture.independentStop, isFalse);
    });

    test('owner-blocked draft keeps Stop primary', () {
      final posture = composerStopPosture(
        running: true,
        origin: null,
        draftEmpty: false,
        enabled: false,
      );
      expect(posture.primaryStops, isTrue);
    });

    test('running subagent session exposes independent Stop', () {
      final posture = composerStopPosture(
        running: true,
        origin: 'subagent',
        draftEmpty: true,
        enabled: true,
      );
      expect(posture.primaryStops, isFalse);
      expect(posture.independentStop, isTrue);
    });
  });
}
