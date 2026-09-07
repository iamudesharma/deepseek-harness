import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/code_block.dart';
import 'package:dsh_flutter/src/widgets/primitives/markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('DsMarkdown fenced code blocks', () {
    testWidgets('fence renders a labeled block with a copy button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DsMarkdown(data: 'Before\n```dart\nvoid main() {}\n```\nAfter'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('code-block')), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-block-copy')), findsOneWidget);
      // Prose around the fence still renders.
      expect(find.textContaining('Before'), findsWidgets);
      expect(find.textContaining('After'), findsWidgets);
    });

    testWidgets('unlabeled fence falls back to the code label', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: '```\nplain text\n```')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('code-block')), findsOneWidget);
      expect(find.text('code'), findsOneWidget);
    });

    testWidgets('inline code keeps the text style (no block)', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: 'Use `print` here')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('code-block')), findsNothing);
      expect(find.textContaining('print'), findsWidgets);
    });

    testWidgets('copy button writes the fenced source', (tester) async {
      final List<MethodCall> clipboardWrites = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: '```sh\necho hi\n```')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('code-block-copy')));
      await tester.pump();

      expect(clipboardWrites, hasLength(1));
      expect(
        (clipboardWrites.single.arguments as Map)['text'],
        'echo hi',
      );
      // Copied confirmation swaps the icon, then reverts after its window.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    });
  });

  group('CodeBlock', () {
    testWidgets('trims one trailing newline for display', (tester) async {
      await tester.pumpWidget(
        _wrap(const CodeBlock(code: 'a\nb\n', language: 'text')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('code-block')), findsOneWidget);
      expect(find.text('text'), findsOneWidget);
    });
  });
}
