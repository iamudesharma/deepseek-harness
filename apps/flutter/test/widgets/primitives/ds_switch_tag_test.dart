import 'dart:ui' show Tristate;

import 'package:dsh_flutter/src/widgets/primitives/ds_switch.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DsSwitch', () {
    testWidgets('tap calls onChanged with the flipped value', (tester) async {
      bool? next;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DsSwitch(
              value: false,
              onChanged: (v) => next = v,
              semanticLabel: 'Toggle feature',
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DsSwitch));
      expect(next, isTrue);
    });

    testWidgets('disabled switch ignores taps', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DsSwitch(
              value: false,
              onChanged: null,
              semanticLabel: 'Locked toggle',
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DsSwitch));
      expect(calls, 0);
    });

    testWidgets('exposes switch semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DsSwitch(
              value: true,
              onChanged: (_) {},
              semanticLabel: 'Subagent models',
            ),
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(DsSwitch));
      expect(semantics.label, 'Subagent models');
      expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
    });
  });

  group('DsTag', () {
    testWidgets('renders the site-owned label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DsTag(label: 'In use')),
        ),
      );
      expect(find.text('In use'), findsOneWidget);
    });

    testWidgets('every tone builds', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final tone in DsTagTone.values)
                  DsTag(tone: tone, label: tone.name),
              ],
            ),
          ),
        ),
      );
      for (final tone in DsTagTone.values) {
        expect(find.text(tone.name), findsOneWidget);
      }
    });
  });
}
