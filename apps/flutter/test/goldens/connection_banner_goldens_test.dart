// DsConnectionBanner goldens — visual evidence for the superset banner.
//
// React ConnectionIndicator.tsx renders a single warning strip while
// reconnecting (states: disconnected / connecting / recovered, single warn
// chrome). Flutter DsConnectionBanner is a superset that surfaces all live
// carrier states the connection controller exposes: connecting (business
// tertiary), reconnecting (warn), disconnected (error), needsReauth (error +
// lock), and connected/idle (hidden). The recovered success flash has no Dart
// equivalent — the controller transitions directly to connected and hides the
// banner, which matches the host generation contract. These goldens pin the
// superset chrome so the visual pass is reviewable and the extra states are
// honest, not a silent drift.
library;

import 'package:dsh_flutter/src/core/connection/connection_client.dart' as conn;
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/connection_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Widget> banners, ThemeMode mode) => ProviderScope(
  child: MaterialApp(
    theme: buildLightTheme(),
    darkTheme: buildDarkTheme(),
    themeMode: mode,
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: banners,
        ),
      ),
    ),
  ),
);

List<Widget> _allBanners() => const [
  DsConnectionBanner(state: conn.ConnectionState.connecting),
  SizedBox(height: 12),
  DsConnectionBanner(state: conn.ConnectionState.reconnecting),
  SizedBox(height: 12),
  DsConnectionBanner(state: conn.ConnectionState.disconnected),
  SizedBox(height: 12),
  DsConnectionBanner(state: conn.ConnectionState.needsReauth),
  SizedBox(height: 12),
  // connected renders null chrome (SizedBox.shrink) — include for layout proof.
  DsConnectionBanner(state: conn.ConnectionState.connected),
];

void main() {
  testWidgets('connection banner superset light', (tester) async {
    tester.view.physicalSize = const Size(760, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(_allBanners(), ThemeMode.light));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/connection_banner_light.png'),
    );
  });

  testWidgets('connection banner superset dark', (tester) async {
    tester.view.physicalSize = const Size(760, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(_allBanners(), ThemeMode.dark));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/connection_banner_dark.png'),
    );
  });

  testWidgets('connection banner collapsed connected hides', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(
            body: DsConnectionBanner(
              state: conn.ConnectionState.connected,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Connecting'), findsNothing);
    expect(find.text('Reconnecting'), findsNothing);
    expect(find.text('Disconnected'), findsNothing);
    expect(find.text('Needs re-auth'), findsNothing);
  });
}
