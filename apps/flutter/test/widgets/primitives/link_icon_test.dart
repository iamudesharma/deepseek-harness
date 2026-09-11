import 'package:dsh_flutter/src/widgets/primitives/link_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyLinkPath', () {
    test('code, web, and data extensions share code', () {
      expect(classifyLinkPath('src/a.ts'), LinkIconKind.code);
      expect(classifyLinkPath('C:\\proj\\main.dart'), LinkIconKind.code);
      expect(classifyLinkPath('data/report.csv'), LinkIconKind.code);
      expect(classifyLinkPath('site/index.HTML'), LinkIconKind.code);
    });

    test('image and document extensions', () {
      expect(classifyLinkPath('shot.PNG'), LinkIconKind.image);
      expect(classifyLinkPath('deck.pptx'), LinkIconKind.document);
    });

    test('unknown and missing extensions fall to other', () {
      expect(classifyLinkPath('README'), LinkIconKind.other);
      expect(classifyLinkPath('archive.zip'), LinkIconKind.other);
    });

    test('never returns url or folder', () {
      for (final path in [
        'https://example.com/x.ts',
        '/tmp/folder.name/x',
        'a/b/c',
      ]) {
        final kind = classifyLinkPath(path);
        expect(kind, isNot(LinkIconKind.url));
        expect(kind, isNot(LinkIconKind.folder));
      }
    });
  });

  group('DsLinkIcon', () {
    testWidgets('every kind builds a 14px glyph', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final kind in LinkIconKind.values)
                  DsLinkIcon(kind: kind),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(DsLinkIcon), findsNWidgets(LinkIconKind.values.length));
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        expect(icon.size, 14);
      }
    });
  });
}
