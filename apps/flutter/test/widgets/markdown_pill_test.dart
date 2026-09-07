import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/markdown.dart';
import 'package:flutter/material.dart';
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
  group('DsMarkdown inline code pills', () {
    testWidgets('normal inline code renders pill text', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: 'Use `print` here')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('print'), findsWidgets);
      expect(find.byKey(const ValueKey('code-block')), findsNothing);
    });

    testWidgets('file-like inline code renders with code icon',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(data: 'Edit `src/App.jsx` now')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('src/App.jsx'), findsWidgets);
      expect(find.byIcon(Icons.code_rounded), findsOneWidget);
    });

    testWidgets('URL inline code renders with link icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(
            data: 'Open `http://127.0.0.1:3080` now')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('http://127.0.0.1:3080'), findsWidgets);
      expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    });

    testWidgets('bash fence renders Copy text button', (tester) async {
      await tester.pumpWidget(
        _wrap(const DsMarkdown(
            data: '```bash\nnpm run build\n```')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('code-block')), findsOneWidget);
      expect(find.text('bash'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });
  });
}
