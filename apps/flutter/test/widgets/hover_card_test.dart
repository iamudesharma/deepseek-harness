import 'package:dsh_flutter/src/widgets/primitives/hover_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dwell = Duration(milliseconds: 300);
  const grace = Duration(milliseconds: 100);

  Future<void> pumpCard(
    WidgetTester tester, {
    bool enabled = true,
    Alignment alignment = Alignment.center,
    String? copyText,
    void Function()? onCopy,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: alignment,
              child: DsHoverCard(
                trigger: const SizedBox(width: 100, height: 40),
                content: const Text('hover-card-content'),
                openDelay: dwell,
                closeDelay: grace,
                enabled: enabled,
                copyText: copyText,
                onCopy: onCopy,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Attaches one mouse pointer on the anchor center and returns it. The card
  /// opens to the right of the anchor, so points inside the card are probed
  /// from the anchor's real rect (follower paint transforms are invisible to
  /// `getRect`-style finders).
  Future<TestGesture> hoverAnchor(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(DsHoverCard)),
    );
    await tester.pump();
    return gesture;
  }

  testWidgets('opens only after the full dwell on the anchor', (tester) async {
    await pumpCard(tester);
    final gesture = await hoverAnchor(tester);

    await gesture.moveTo(tester.getCenter(find.byType(DsHoverCard)));
    await tester.pump(dwell - const Duration(milliseconds: 50));
    expect(find.text('hover-card-content'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('hover-card-content'), findsOneWidget);
  });

  testWidgets('leaving the anchor closes after the grace delay', (
    tester,
  ) async {
    await pumpCard(tester);
    final gesture = await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 50));
    expect(find.text('hover-card-content'), findsOneWidget);

    // Park the pointer far from both anchor and card.
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(grace - const Duration(milliseconds: 50));
    expect(find.text('hover-card-content'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('hover-card-content'), findsNothing);
  });

  testWidgets('the card is reachable: resting on it cancels the grace close', (
    tester,
  ) async {
    await pumpCard(tester);
    final gesture = await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 50));

    // Cross the 8px gap onto the opened card: 20px right of the anchor's
    // right edge, vertically level with the trigger center.
    final anchorTopRight = tester.getTopRight(find.byType(DsHoverCard));
    await gesture.moveTo(anchorTopRight + const Offset(28, 0));
    await tester.pump(grace + const Duration(milliseconds: 200));
    expect(find.text('hover-card-content'), findsOneWidget);
  });

  testWidgets('flips to the left of the anchor near the right viewport edge', (
    tester,
  ) async {
    // Anchor flush against the right edge: targetRight + 8 + cardWidth
    // overflows the viewport, so placement must mirror to the left side.
    await pumpCard(tester, alignment: Alignment.centerRight);
    final gesture = await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 50));
    // Commit the post-frame flip measurement before probing.
    await tester.pump();

    // A point left of the anchor is inside the flipped card and outside any
    // unflipped one — resting there cancels the close only when flipped.
    final anchorTopLeft = tester.getTopLeft(find.byType(DsHoverCard));
    await gesture.moveTo(anchorTopLeft + const Offset(-28, 20));
    await tester.pump(grace + const Duration(milliseconds: 200));
    expect(find.text('hover-card-content'), findsOneWidget);
  });

  testWidgets('disabled suppresses opening', (tester) async {
    await pumpCard(tester, enabled: false);
    await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 100));
    expect(find.text('hover-card-content'), findsNothing);
  });

  testWidgets('disabling mid-hover closes an open card immediately', (
    tester,
  ) async {
    await pumpCard(tester);
    await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 50));
    expect(find.text('hover-card-content'), findsOneWidget);

    await pumpCard(tester, enabled: false);
    await tester.pump();
    expect(find.text('hover-card-content'), findsNothing);
  });

  testWidgets('copy row fires onCopy when copyText is set', (tester) async {
    var copies = 0;
    await pumpCard(tester, copyText: '/tmp/workspace', onCopy: () => copies++);
    await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 50));

    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copies, 1);
  });

  testWidgets('no copy row renders without copyText', (tester) async {
    await pumpCard(tester);
    await hoverAnchor(tester);
    await tester.pump(dwell + const Duration(milliseconds: 50));

    expect(find.text('Copy'), findsNothing);
  });
}
