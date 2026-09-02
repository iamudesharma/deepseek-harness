// DsOnboardingSurface goldens — primitive-level visual proof.
//
// React OnboardingSurface.tsx is a body-portaled mask (rgba 0,0,0,0.24 +
// blur 2) + opaque stage that sets #root inert. It has NO production
// consumer: the only <OnboardingSurface usages live in
// ui-primitives/tests/onboarding-surface.client.spec.tsx. Flutter
// DsOnboardingSurface ports the chrome as a full-screen Material with a
// 480-wide stage, progress dots, and CTA row, and exposes the same inertness
// structurally (full-screen takeover replaces content). Like Pill, this row
// is Verified at primitive level without fabricating a consumer — the goldens
// pin the chrome, and composition remains NotApplicable until a React surface
// actually mounts it.
library;

import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/onboarding_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(DsOnboardingSurface surface, ThemeMode mode) => ProviderScope(
  child: MaterialApp(
    theme: buildLightTheme(),
    darkTheme: buildDarkTheme(),
    themeMode: mode,
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: surface),
  ),
);

const _steps = <DsOnboardingStep>[
  DsOnboardingStep(
    title: 'Welcome',
    description: 'Explore the harness — your sessions live here.',
  ),
  DsOnboardingStep(
    title: 'Workspaces',
    description: 'Create a workspace to group sessions by folder.',
  ),
  DsOnboardingStep(
    title: 'Ready',
    description: 'You are all set. Start building.',
  ),
];

void main() {
  testWidgets('onboarding surface light first step', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(
        const DsOnboardingSurface(steps: _steps, currentStep: 0),
        ThemeMode.light,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DsOnboardingSurface),
      matchesGoldenFile('goldens/onboarding_surface_light_first.png'),
    );
  });

  testWidgets('onboarding surface light last step', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(
        const DsOnboardingSurface(steps: _steps, currentStep: 2),
        ThemeMode.light,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DsOnboardingSurface),
      matchesGoldenFile('goldens/onboarding_surface_light_last.png'),
    );
  });

  testWidgets('onboarding surface dark first step', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(
        const DsOnboardingSurface(steps: _steps, currentStep: 0),
        ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DsOnboardingSurface),
      matchesGoldenFile('goldens/onboarding_surface_dark.png'),
    );
  });
}
