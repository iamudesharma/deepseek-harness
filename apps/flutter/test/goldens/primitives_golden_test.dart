import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_button.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_modal.dart';

void main() {
  group('DsButton golden', () {
    testWidgets('light desktop', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(body: Center(child: DsButton(label: 'Primary', variant: DsButtonVariant.primary))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(DsButton), matchesGoldenFile('goldens/button_light_desktop.png'));
    });

    testWidgets('ghost narrow', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(body: Center(child: DsButton(label: 'Ghost', variant: DsButtonVariant.ghost))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(DsButton), matchesGoldenFile('goldens/button_ghost_narrow.png'));
    });

    testWidgets('dark primary', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: ThemeMode.dark,
            home: const Scaffold(body: Center(child: DsButton(label: 'Dark', variant: DsButtonVariant.primary))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(DsButton), matchesGoldenFile('goldens/button_dark.png'));
    });
  });

  group('DsModal golden', () {
    testWidgets('modal light', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(body: DsModal(title: 'Test Modal', child: Text('Content'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(DsModal), matchesGoldenFile('goldens/modal_light.png'));
    });
  });
}
