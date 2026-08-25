import 'package:dsh_flutter/src/widgets/primitives/dsh_menu_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool closed;

  Future<void> pump(WidgetTester tester, {Color barrierColor = Colors.transparent}) async {
    closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DshMenuScaffold(
          barrierColor: barrierColor,
          onClose: () => closed = true,
          child: const Center(
            child: Material(
              child: SizedBox(
                width: 200,
                height: 200,
                child: Column(
                  children: [
                    Text('Menu item one'),
                    Text('Menu item two'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(); // flush focus post-frame callback
  }

  testWidgets('Escape dismisses the popover', (tester) async {
    await pump(tester);
    expect(closed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('barrier tap still dismisses', (tester) async {
    await pump(tester);
    // Tap far outside the centered menu (hit the barrier layer).
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('focus returns to the previously focused node on close',
      (tester) async {
    final FocusNode anchor = FocusNode(debugLabel: 'anchor');
    var closedCount = 0;
    var open = false;
    late StateSetter setOpen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // Mirrors the welcome screen: the popover is a Stack-hosted
        // full-viewport overlay, so the Scaffold body gives it bounds.
        body: StatefulBuilder(
          builder: (context, setState) {
            setOpen = setState;
            return Stack(
              children: [
                TextButton(
                  focusNode: anchor,
                  onPressed: () {},
                  child: const Text('Anchor'),
                ),
                if (open)
                  DshMenuScaffold(
                    onClose: () => closedCount += 1,
                    child: const Center(child: Text('menu')),
                  ),
              ],
            );
          },
        ),
      ),
    ));
    // The trigger holds focus, as after a chip click.
    anchor.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, anchor);
    // Open the popover while the anchor still holds focus (real open flow).
    setOpen(() => open = true);
    await tester.pump();
    await tester.pump();
    // Escape closes; the close path restores keyboard focus to the node that
    // held focus before the popover opened.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closedCount, 1);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, anchor);
  });

  testWidgets('non-escape keys fall through to menu', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(closed, isFalse);
  });
}
