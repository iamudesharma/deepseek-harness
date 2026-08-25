import 'dart:io';

import 'package:dsh_flutter/src/theme/dsw_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Token-parity evidence for [theme.tokens]: the React inspection contract's
/// canonical semantic aliases exist in BOTH palette modes in the Dart layer,
/// and the repo rule "no literal colors outside the token file" holds.
void main() {
  group('semantic alias coverage', () {
    final light = DswAliases.light();
    final dark = DswAliases.dark();

    // The --dsw-alias-* names BUILTIN_INSPECT_TOKENS declares in
    // ui-theme/src/client/index.ts, mapped to their Dart fields.
    final inspected = <String, Color Function(DswAliases)>{
      'bg-base': (a) => a.bgBase,
      'bg-layer-1': (a) => a.bgLayer1,
      'bg-layer-2': (a) => a.bgLayer2,
      'bg-overlay': (a) => a.bgOverlay,
      'border-l1': (a) => a.borderL1,
      'border-l2': (a) => a.borderL2,
      'brand-primary': (a) => a.brandPrimary,
      'label-primary': (a) => a.labelPrimary,
      'label-secondary': (a) => a.labelSecondary,
      'state-error-primary': (a) => a.stateErrorPrimary,
      'state-success-primary': (a) => a.stateSuccessPrimary,
      'state-warn-primary': (a) => a.stateWarnPrimary,
    };

    test('every inspected alias resolves in both modes', () {
      for (final entry in inspected.entries) {
        expect(() => entry.value(light), returnsNormally,
            reason: 'missing light alias ${entry.key}');
        expect(() => entry.value(dark), returnsNormally,
            reason: 'missing dark alias ${entry.key}');
      }
    });

    test('scheme-dependent aliases differ across modes', () {
      expect(inspected['bg-base']!(light), isNot(inspected['bg-base']!(dark)));
      expect(inspected['label-primary']!(light), isNot(inspected['label-primary']!(dark)));
    });

    test('sidebar specific token exists in both modes', () {
      expect(() => light.specificSidebarFill, returnsNormally);
      expect(() => dark.specificSidebarFill, returnsNormally);
    });
  });

  test('no literal Color( values outside the token file', () {
    // Component-local ports of React literals are exempt when they cite their
    // source; the palette itself stays centralized in dsw_tokens.dart.
    const exemptions = {
      'lib/src/routing/app_router.dart':
          'hero glow ellipse ported from ui-conversation EmptyHero.tsx (#6187D8 @ 8%)',
    };
    final offenders = <String>[];
    for (final dir in ['lib/src/features', 'lib/src/widgets', 'lib/src/core', 'lib/src/routing']) {
      Directory(dir).listSync(recursive: true).whereType<File>().forEach((file) {
        final rel = file.path;
        if (!file.path.endsWith('.dart')) return;
        if (exemptions.containsKey(rel)) return;
        if (file.readAsStringSync().contains('Color(0x')) offenders.add(file.path);
      });
    }
    expect(offenders, isEmpty);
  });
}
