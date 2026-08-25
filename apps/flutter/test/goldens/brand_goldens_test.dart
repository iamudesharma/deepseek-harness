// Brand primitive goldens — visual evidence that the exact figma extracts
// render correctly in both themes: fish ink, wordmark letterforms, badge
// plate, and the knocked-out HARNESS badge glyphs.
library;

import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/brandwordmark.dart';
import 'package:dsh_flutter/src/widgets/primitives/fish_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, ThemeMode mode) => ProviderScope(
      child: MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: mode,
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: child)),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget child, ThemeMode mode) async {
  tester.view.physicalSize = const Size(400, 120);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(Center(child: child), mode));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fish logo light', (tester) async {
    await _pump(tester, const DsFishLogo(size: 34), ThemeMode.light);
    await expectLater(find.byType(DsFishLogo), matchesGoldenFile('goldens/fish_logo_light.png'));
  });

  testWidgets('fish logo dark', (tester) async {
    await _pump(tester, const DsFishLogo(size: 34), ThemeMode.dark);
    await expectLater(find.byType(DsFishLogo), matchesGoldenFile('goldens/fish_logo_dark.png'));
  });

  testWidgets('brand wordmark light', (tester) async {
    await _pump(tester, const DsBrandWordmark(), ThemeMode.light);
    await expectLater(
        find.byType(DsBrandWordmark), matchesGoldenFile('goldens/brand_wordmark_light.png'));
  });

  testWidgets('brand wordmark dark', (tester) async {
    await _pump(tester, const DsBrandWordmark(), ThemeMode.dark);
    await expectLater(
        find.byType(DsBrandWordmark), matchesGoldenFile('goldens/brand_wordmark_dark.png'));
  });

  testWidgets('brand wordmark without mark light', (tester) async {
    await _pump(tester, const DsBrandWordmark(includeMark: false), ThemeMode.light);
    await expectLater(find.byType(DsBrandWordmark),
        matchesGoldenFile('goldens/brand_wordmark_name_light.png'));
  });
}
