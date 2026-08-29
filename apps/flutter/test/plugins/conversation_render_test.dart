import 'package:dsh_flutter/src/plugins/conversation/ui/ansi_span.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_shortcuts.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ANSI spans', () {
    test('green code colors the segment; reset returns to fallback', () {
      final span = ansiToSpan(
        '\x1B[32mOK\x1B[0m plain',
        fallbackColor: const Color(0xFFCCCCCC),
      );
      final children = span.children!;
      expect(children, hasLength(2));
      expect((children[0].style!.color), const Color(0xFF16A34A));
      expect(children[1].style!.color, const Color(0xFFCCCCCC));
    });

    test('bold toggles weight; unknown CSI stripped', () {
      final span = ansiToSpan('\x1B[1mhead\x1B[0mtail');
      expect(span.children, hasLength(2));
      expect(span.children![0].style!.fontWeight, FontWeight.bold);
    });
  });

  group('ConversationShortcuts', () {
    testWidgets('Enter fires submit; Escape fires cancel', (tester) async {
      var submitted = 0;
      var cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () => submitted++,
              onCancel: () => cancelled++,
              child: const TextField(),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submitted, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('Shift+Enter never matches the plain submit activator', (
      tester,
    ) async {
      var submitted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onSubmit: () => submitted++,
              // A bare Focus consumes nothing, so every key reaches the seam.
              child: const Focus(autofocus: true, child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(submitted, 0);
    });

    testWidgets('undo/redo ride Cmd on Apple hosts', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var undos = 0;
      var redos = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onUndo: () => undos++,
              onRedo: () => redos++,
              child: const Focus(autofocus: true, child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      // Cmd+Z undo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(undos, 1);

      // Cmd+Shift+Z redo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(redos, 1);

      // Regression: typing a capital Z (bare Shift+Z) must not redo.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(redos, 1);

      // Ctrl+Y is not an Apple redo.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(redos, 1);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('undo/redo ride Ctrl (+Ctrl+Y) off Apple', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      var undos = 0;
      var redos = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationShortcuts(
              onUndo: () => undos++,
              onRedo: () => redos++,
              child: const Focus(autofocus: true, child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      // Ctrl+Z undo; Ctrl+Shift+Z and Ctrl+Y both redo.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(undos, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(redos, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(redos, 2);

      // Meta+Z is not a non-Apple undo.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(undos, 1);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
