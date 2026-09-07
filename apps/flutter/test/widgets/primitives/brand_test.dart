// Brand primitive contracts pinned against the React sources:
// `packages/client/ui-primitives/src/FishLogo.tsx` and `BrandWordmark.tsx`.
//
// The geometry assertions use the native viewBox bounds computed from the
// exact figma extracts; any replacement of the artwork with an approximation
// moves these bounds by whole units and fails here.
library;

import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/brandwordmark.dart';
import 'package:dsh_flutter/src/widgets/primitives/fish_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {ThemeMode mode = ThemeMode.light}) => ProviderScope(
  child: MaterialApp(
    theme: buildLightTheme(),
    darkTheme: buildDarkTheme(),
    themeMode: mode,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('DsFishLogo', () {
    testWidgets('renders at the native 23.16:17.04 ratio (default width 24)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const DsFishLogo()));
      final Size box = tester.getSize(find.byType(DsFishLogo));
      expect(box.width, 24);
      expect(box.height, closeTo(24 * 17.04 / 23.16, 0.001));
    });

    testWidgets('scales with size (hero usage is 34 wide)', (tester) async {
      await tester.pumpWidget(_wrap(const DsFishLogo(size: 34)));
      final Size box = tester.getSize(find.byType(DsFishLogo));
      expect(box.width, 34);
      expect(box.height, closeTo(34 * 17.04 / 23.16, 0.001));
    });

    testWidgets('stays decorative unless labeled (React aria-hidden)', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      // Bare: excluded from the semantics tree entirely.
      await tester.pumpWidget(_wrap(const DsFishLogo()));
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);

      // Labeled: carries an image semantics node.
      await tester.pumpWidget(
        _wrap(const DsFishLogo(semanticLabel: 'DeepSeek fish')),
      );
      expect(find.bySemanticsLabel('DeepSeek fish'), findsOneWidget);

      handle.dispose();
    });

    test('fish path carries the exact figma extract bounds', () {
      final Rect bounds = kFishLogoPath.getBounds();
      // Control-point extremes from the React `d` (-0.2229, -0.0264) ..
      // (23.1738, 17.1657); tolerance absorbs Skia's curve-hull refinement.
      expect(bounds.left, closeTo(-0.223, 0.05));
      expect(bounds.top, closeTo(-0.026, 0.05));
      expect(bounds.right, closeTo(23.174, 0.05));
      expect(bounds.bottom, closeTo(17.166, 0.05));
      expect(kFishLogoViewBox, const Size(23.16, 17.04));
    });
  });

  group('DsBrandWordmark', () {
    testWidgets('width follows the selected artwork (182 or 156 at size 24)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              DsBrandWordmark(key: Key('full')),
              DsBrandWordmark(key: Key('name'), includeMark: false),
            ],
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('full'))).width,
        closeTo(24 * 182 / 24, 0.001),
      );
      expect(
        tester.getSize(find.byKey(const Key('full'))).height,
        closeTo(24, 0.001),
      );
      // Without the mark React renders viewBox `26 0 156 24` → 156/24 scale.
      expect(
        tester.getSize(find.byKey(const Key('name'))).width,
        closeTo(24 * 156 / 24, 0.001),
      );
    });

    test('artwork composition matches the React svg groups', () {
      // "deepseek" letterforms + divider + chevron before the whale clip
      // group, one whale path, seven HARNESS badge glyph paths.
      expect(kWordmarkNamePaths, hasLength(9));
      expect(kWordmarkBadgeTextPaths, hasLength(7));
      expect(kWordmarkViewBoxWidth, 182);
    });

    test('whale mark keeps the React clip window bounds', () {
      final Rect bounds = kWordmarkWhalePath.getBounds();
      // Native whale placement inside the wordmark: control-point extremes
      // (-0.0813, 3.4955) .. (23.3154, 20.6875).
      expect(bounds.left, closeTo(-0.081, 0.05));
      expect(bounds.top, closeTo(3.496, 0.05));
      expect(bounds.right, closeTo(23.315, 0.05));
      expect(bounds.bottom, closeTo(20.688, 0.05));
    });

    test('name letterforms occupy the 26..182 band', () {
      Rect union = kWordmarkNamePaths.first.getBounds();
      for (final Path path in kWordmarkNamePaths.skip(1)) {
        union = union.expandToInclude(path.getBounds());
      }
      expect(union.left, closeTo(26.956, 0.05));
      expect(union.top, closeTo(4.628, 0.05));
      expect(union.right, closeTo(121.517, 0.05));
      expect(union.bottom, closeTo(21.644, 0.05));
    });

    test('badge glyphs sit on the plate between 132.8 and 178.5', () {
      Rect union = kWordmarkBadgeTextPaths.first.getBounds();
      for (final Path path in kWordmarkBadgeTextPaths.skip(1)) {
        union = union.expandToInclude(path.getBounds());
      }
      expect(union.left, closeTo(132.848, 0.05));
      expect(union.top, closeTo(8.800, 0.05));
      expect(union.right, closeTo(178.449, 0.05));
      expect(union.bottom, closeTo(16.291, 0.05));
    });
  });
}
