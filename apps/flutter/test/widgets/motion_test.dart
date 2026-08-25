import 'package:dsh_flutter/src/theme/motion.dart';
import 'package:dsh_flutter/src/widgets/primitives/state_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        // disableAnimations is the Flutter flag corresponding to
        // prefers-reduced-motion.
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('prefersReducedMotion reflects disableAnimations',
      (tester) async {
    // Builder reads the flag and renders text of the resolved value.
    Widget probe = Builder(
      builder: (context) => Text(
        prefersReducedMotion(context) ? 'reduced' : 'full',
      ),
    );
    await tester.pumpWidget(_harness(probe, reduceMotion: true));
    await tester.pump();
    expect(find.text('reduced'), findsOneWidget);
    expect(find.text('full'), findsNothing);

    await tester.pumpWidget(_harness(probe));
    await tester.pump();
    expect(find.text('full'), findsOneWidget);
  });

  testWidgets(
      'StateDot ongoing collapses to a static cell under reduced motion',
      (tester) async {
    await tester.pumpWidget(_harness(
      const StateDot(state: StateDotState.ongoing),
      reduceMotion: true,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    // Reduced motion: the StateDot itself renders no CustomPaint chase
    // (Material/Scaffold chrome has its own CustomPaints outside it).
    expect(
      find.descendant(
        of: find.byType(StateDot),
        matching: find.byWidgetPredicate((w) => w is CustomPaint),
      ),
      findsNothing,
    );
    // Static collapse is a decorated Container.
    expect(
      find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
      findsWidgets,
    );
  });

  testWidgets('StateDot ongoing still animates when motion is full',
      (tester) async {
    await tester.pumpWidget(_harness(
      const StateDot(state: StateDotState.ongoing),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint),
      findsWidgets,
    );
  });
}