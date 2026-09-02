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

    test('italic, underline and strike map to decorations', () {
      final span = ansiToSpan('\x1B[3mitalic\x1B[0m \x1B[4munder\x1B[0m \x1B[9mstrike\x1B[0m');
      final children = span.children!;
      expect(children[0].style!.fontStyle, FontStyle.italic);
      expect(children[1].style!.fontStyle, isNull);
      // The third colored run is at index 2? Actually pattern splits: italic run, plain space, under run, etc.
      // We check underline and strike via decoration.
      final under = children[2];
      expect(under.style!.decoration, TextDecoration.underline);
      final strike = children[4];
      expect(strike.style!.decoration, TextDecoration.lineThrough);
    });

    test('dim with color applies 0.7 alpha and hidden is transparent', () {
      final dimSpan = ansiToSpan('\x1B[2m\x1B[31mdimRed\x1B[0m');
      final dimColor = dimSpan.children![0].style!.color!;
      expect(dimColor.alpha, closeTo(0.7 * 255, 2));
      final hidden = ansiToSpan('\x1B[8msecret\x1B[0m plain');
      expect(hidden.children![0].style!.color, const Color(0x00000000));
    });

    test('background colors via 44 and 104 produce backgroundColor', () {
      final span = ansiToSpan('\x1B[44mblueBg\x1B[49m plain');
      expect(span.children![0].style!.backgroundColor, const Color(0xFF2563EB));
      expect(span.children![1].style!.backgroundColor, isNull);
    });

    test('39 resets foreground to fallback while 49 resets background', () {
      final span = ansiToSpan('\x1B[31mred\x1B[39m plain', fallbackColor: const Color(0xFFCCCCCC));
      expect(span.children![0].style!.color, const Color(0xFFDC2626));
      expect(span.children![1].style!.color, const Color(0xFFCCCCCC));
    });

    test('256 and truecolor via 38;5;N and 38;2;R;G;B', () {
      final c256 = ansiToSpan('\x1B[38;5;208m256\x1B[0m');
      // 208 in xterm is orange ~ 255,135,0 => 0xFFFF8700
      expect(c256.children![0].style!.color!.value, isNot(0));
      final truecolor = ansiToSpan('\x1B[38;2;10;20;30mtrue\x1B[0m');
      expect(truecolor.children![0].style!.color, const Color.fromARGB(0xFF, 10, 20, 30));
      final bg256 = ansiToSpan('\x1B[48;5;196mredBg\x1B[0m');
      expect(bg256.children![0].style!.backgroundColor!.value, isNot(0));
    });

    test('OSC and non-CSI escapes are stripped without leaking text', () {
      final osc = ansiToSpan('hi\x1B]0;window title\x07 there');
      expect((osc.children!.first as TextSpan).text, 'hi there');
      final inert = ansiToSpan('a\x07b\x1B(Bc');
      // \x07 and \x1B(B are stripped by sanitize
      expect((inert.children!.first as TextSpan).text, 'abc');
    });

    test('CSI erase-in-line K is stripped', () {
      final span = ansiToSpan('foo\x1B[2Kbar');
      expect((span.children!.first as TextSpan).text, 'foobar');
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
