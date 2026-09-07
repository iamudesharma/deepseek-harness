import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_shortcuts.dart';
import 'package:dsh_flutter/src/widgets/primitives/ansi.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Distinct token stand-ins, so every test asserts which token a basic ANSI
/// color resolved to rather than a theme default.
const AnsiColors tokens = AnsiColors(
  labelPrimary: Color(0xFF111111),
  labelTertiary: Color(0xFF222222),
  stateErrorPrimary: Color(0xFFAA0000),
  stateErrorSecondary: Color(0xFFAA1111),
  stateSuccessPrimary: Color(0xFF00AA00),
  stateSuccessSecondary: Color(0xFF00AA11),
  stateWarnPrimary: Color(0xFFAA4400),
  stateWarnSecondary: Color(0xFFAA5511),
  stateBusinessPrimary: Color(0xFF0000AA),
);

String plainText(AnsiLine line) => [for (final span in line) span.text].join();

void main() {
  group('ANSI spans', () {
    test('basic colors map to tokens; reset inherits', () {
      final lines = parseAnsiLines(
        '\x1B[32mOK\x1B[0m plain\n\x1B[94mblue',
        colors: tokens,
      );
      expect(lines, hasLength(2));
      expect(plainText(lines[0]), 'OK plain');
      expect(lines[0][0].style!.color, tokens.stateSuccessPrimary);
      expect(lines[0][1].style, isNull);
      // Bright blue maps to the static blue-400 token.
      expect(lines[1][0].style!.color, AnsiColors.blue400);
      // Literal palette when no tokens are available.
      final literal = parseAnsiLines('\x1B[32mOK');
      expect(literal[0][0].style!.color, const Color(0xFF00BB00));
    });

    test('bold toggles weight; non-SGR CSI consumed without effect', () {
      final lines = parseAnsiLines('\x1B[1mhead\x1B[0mtail\x1B[?25l');
      expect(plainText(lines[0]), 'headtail');
      expect(lines[0][0].style!.fontWeight, FontWeight.bold);
      expect(lines[0][1].style, isNull);
    });

    test('italic, underline and strike map to decorations', () {
      final lines = parseAnsiLines(
        '\x1B[3mitalic\x1B[0m \x1B[4munder\x1B[0m \x1B[9mstrike\x1B[0m',
      );
      expect(lines[0][0].style!.fontStyle, FontStyle.italic);
      expect(lines[0][2].style!.decoration, TextDecoration.underline);
      expect(lines[0][4].style!.decoration, TextDecoration.lineThrough);
      // Underline and strikethrough share one slot; the later declaration
      // wins, matching the reference parser.
      expect(parseAnsiLines('\x1B[4;9mx')[0][0].style!.decoration,
          TextDecoration.lineThrough);
      expect(parseAnsiLines('\x1B[9;4mx')[0][0].style!.decoration,
          TextDecoration.underline);
    });

    test('dim fades its color; hidden is transparent', () {
      final dimmed = parseAnsiLines('\x1B[2m\x1B[31mdimRed\x1B[0m',
          colors: tokens);
      final dimColor = dimmed[0][0].style!.color!;
      expect(dimColor.a, closeTo(0.7, 0.01));
      // A dim run with no color of its own fades the inherited color.
      final dimInherited = parseAnsiLines('\x1B[2mfaded',
          colors: tokens, defaultColor: const Color(0xFF888888));
      expect(dimInherited[0][0].style!.color,
          const Color(0xFF888888).withValues(alpha: 0.7));
      final hidden = parseAnsiLines('\x1B[8msecret\x1B[0m plain');
      expect(hidden[0][0].style!.color, const Color(0x00000000));
    });

    test('reverse swaps foreground and background', () {
      final lines = parseAnsiLines('\x1B[31;44;7mswap', colors: tokens);
      // A run that paints its own background keeps the literal ANSI pair.
      expect(lines[0][0].style!.color, const Color(0xFF0000BB));
      expect(lines[0][0].style!.backgroundColor, const Color(0xFFBB0000));
    });

    test('background stays literal; fg with bg keeps the literal pair', () {
      final lines = parseAnsiLines('\x1B[31;44mred on blue\x1B[49;32mgreen',
          colors: tokens);
      expect(lines[0][0].style!.color, const Color(0xFFBB0000));
      expect(lines[0][0].style!.backgroundColor, const Color(0xFF0000BB));
      // Once the background clears, the foreground maps to its token again.
      expect(lines[0][1].style!.color, tokens.stateSuccessPrimary);
      expect(lines[0][1].style!.backgroundColor, isNull);
    });

    test('256-palette and truecolor stay literal', () {
      final lines = parseAnsiLines(
        '\x1B[38;5;208mc256\x1B[0m\x1B[38;2;10;20;30mtrue\x1B[0m'
        '\x1B[48;5;196mbg256',
      );
      expect(lines[0][0].style!.color, const Color(0xFFFF8700));
      expect(lines[0][1].style!.color,
          const Color.fromARGB(0xFF, 10, 20, 30));
      expect(lines[0][2].style!.backgroundColor, isNotNull);
    });

    test('OSC, charset and inert control sequences vanish', () {
      final lines = parseAnsiLines('hi\x1B]0;title\x07 there a\x07b\x1B(Bc');
      expect(plainText(lines[0]), 'hi there abc');
    });

    test('carriage-return redraw overwrites instead of appending', () {
      final lines = parseAnsiLines('100%\rOK');
      // A terminal keeps whatever each column last had: OK overwrites 10 and
      // the shorter redraw leaves the 0 standing.
      expect(plainText(lines[0]), 'OK0%');
    });

    test('backspace moves the cursor without erasing', () {
      expect(plainText(parseAnsiLines('abc\bX')[0]), 'abX');
      expect(plainText(parseAnsiLines('abc\b')[0]), 'abc');
    });

    test('erase-in-line modes replay per the CSI spec', () {
      // EL2 clears the whole line but keeps the cursor column, so the next
      // write lands where it would in a real terminal.
      expect(plainText(parseAnsiLines('foo\x1B[2Kbar')[0]), '   bar');
      // EL0 erases from the cursor rightwards; the cursor column is kept,
      // so the following write lands where it would in a real terminal.
      expect(plainText(parseAnsiLines('foo\x1B[0Kx')[0]), 'foox');
      // A redraw writes from column 0, then EL0 trims the stale tail.
      expect(plainText(parseAnsiLines('foo\r\x1B[0Kz')[0]), 'z');
      // EL1 erases from the line start through the cursor, which keeps its
      // column: the blank cells stay, so x lands on the erased cursor cell.
      expect(plainText(parseAnsiLines('abcdef\x1B[1Kx')[0]), '      x');
      // Only the first parameter selects the mode; the rest are ignored, so
      // `1;2K` erases exactly as `1K` — blanks through the cursor stay.
      expect(plainText(parseAnsiLines('foo\x1B[1;2Kbar')[0]), '   bar');
    });

    test('erase stamps the current SGR state onto the blanks', () {
      final lines = parseAnsiLines('abc\x1B[41m\r\x1B[1K', colors: tokens);
      expect(plainText(lines[0]), ' bc');
      expect(lines[0][0].style!.backgroundColor, const Color(0xFFBB0000));
    });

    test('SGR state threads across lines; a newline does not reset it', () {
      final lines = parseAnsiLines('\x1B[31mred\nstill\n\x1B[0mplain',
          colors: tokens);
      expect(lines[0][0].style!.color, tokens.stateErrorPrimary);
      expect(lines[1][0].style!.color, tokens.stateErrorPrimary);
      expect(lines[2][0].style, isNull);
    });

    test('a carriage return that ends a CRLF line is dropped', () {
      final lines = parseAnsiLines('a\r\nb');
      expect(lines, hasLength(2));
      expect(plainText(lines[0]), 'a');
      expect(plainText(lines[1]), 'b');
    });

    test('wide characters occupy two columns and redraw blanks the pair', () {
      expect(plainText(parseAnsiLines('汉字')[0]), '汉字');
      // Overwriting the lead cell of a wide pair blanks its spacer instead
      // of closing the gap.
      expect(plainText(parseAnsiLines('汉字\rX')[0]), 'X 字');
    });

    test('zero-width marks attach to the cell already written', () {
      expect(plainText(parseAnsiLines('e\u0301x')[0]), 'e\u0301x');
    });

    test('tabs: literal on plain lines, blanks on replayed lines', () {
      // A line with no cursor movement keeps its tab as literal text.
      expect(plainText(parseAnsiLines('a\tb')[0]), 'a\tb');
      // Once the line replays, a tab fills the cells it skips as blanks up
      // to the next 8-column stop.
      expect(plainText(parseAnsiLines('a\tb\rX')[0]), 'X       b');
    });

    test('one entry per output line, trailing blank included', () {
      final lines = parseAnsiLines('a\n');
      expect(lines, hasLength(2));
      expect(lines[1], isEmpty);
      // Empty input still yields one line.
      expect(parseAnsiLines(''), hasLength(1));
    });

    test('ansiToSpan joins the lines into one selectable span tree', () {
      final span = ansiToSpan('a\nb', colors: tokens);
      expect(span.children, hasLength(1));
      expect((span.children![0] as TextSpan).text, 'a\nb');
      expect(ansiToSpan(''), const TextSpan(text: ''));
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
