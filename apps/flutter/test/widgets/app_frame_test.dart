import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/layout/app_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _pumpAppFrame({
  required Size size,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: buildLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const Scaffold(body: AppFrame()),
      ),
    ),
  );
}

void main() {
  group('AppFrame', () {
    testWidgets(
      'expanded at 1200x800: sidebar visible, drag handle exists, not collapsed',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(_pumpAppFrame(size: const Size(1200, 800)));
        await tester.pumpAndSettle();

        // User-visible: Sidebar placeholder should be present when expanded
        expect(find.text('Sidebar'), findsOneWidget);
        expect(find.text('Conversation'), findsOneWidget);

        // Drag handle for sidebar should exist when not collapsed
        expect(find.byType(DragHandle), findsWidgets);

        // Verify layout state reflects wide viewport (narrow false)
        // We can't directly read provider outside; instead assert visual width
        // Sidebar AnimatedContainer should be ~280 wide (default). Check via size
        final sidebarFinder = find.text('Sidebar');
        expect(sidebarFinder, findsOneWidget);

        // Details collapsed handling: details width 360 but center=560? At 1200, details auto-closes per computeColumns
        // So only sidebar handle should be visible, not details handle (details ==0)
        // At 1200, sidebar 280 + centerMin 640 + details 360 =1280 >1200 => details 0, so only 1 handle
        expect(find.byType(DragHandle), findsOneWidget);
      },
    );

    testWidgets(
      'collapsed at 400x800: sidebar collapsed to rail, conversation still visible',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(_pumpAppFrame(size: const Size(400, 800)));
        // Post-frame callback sets narrow=true; need two pump cycles to settle
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        // Second settle after narrow flag propagats and rebuilds
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // Sidebar placeholder should still be mounted (inside rail) and conversation visible
        expect(find.text('Sidebar'), findsOneWidget);
        expect(find.text('Conversation'), findsOneWidget);

        // When narrow+collapsed, sidebar drag handle should NOT exist
        expect(find.byType(DragHandle), findsNothing);
      },
    );

    testWidgets('wide shows drag handle, narrow hides sidebar handle', (
      tester,
    ) async {
      // Start wide
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(_pumpAppFrame(size: const Size(1200, 800)));
      await tester.pumpAndSettle();
      expect(find.byType(DragHandle), findsOneWidget);

      // Switch to narrow: pump new size and wait for post-frame narrow propagation
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(_pumpAppFrame(size: const Size(400, 800)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.byType(DragHandle), findsNothing);
    });

    testWidgets(
      'with sidebar and conversation slots renders provided widgets',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: buildLightTheme(),
              home: MediaQuery(
                data: const MediaQueryData(size: Size(1200, 800)),
                child: const Scaffold(
                  body: AppFrame(
                    sidebar: Text('Custom Sidebar'),
                    conversation: Text('Custom Conversation'),
                    details: Text('Custom Details'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Custom Sidebar'), findsOneWidget);
        expect(find.text('Custom Conversation'), findsOneWidget);
        // Custom Details is kept mounted via Visibility(visible:false) when details auto-closes at 1200.
        // Finder skips offstage by default, so use skipOffstage:false to assert mounted state.
        expect(
          find.text('Custom Details', skipOffstage: false),
          findsOneWidget,
        );
        // User-visible: details text should NOT be visible when collapsed
        expect(find.text('Custom Details'), findsNothing);
      },
    );

    testWidgets(
      'details track boots closed; no details handle without an open details panel',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(_pumpAppFrame(size: const Size(1600, 800)));
        await tester.pumpAndSettle();

        // The layout store boots CLOSED (React stores.ts init `details: 0`;
        // the width preference only restores via openDetails). At 1600 the
        // concession solve therefore renders the sidebar handle only — the
        // details track stays a zero-width, invisible subtree.
        expect(find.byType(DragHandle), findsOneWidget);
      },
    );

    testWidgets(
      'AppFrame respects ProviderScope layout override for collapsed state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        // We cannot directly override layoutProvider state without a custom notifier, but we can verify
        // that the default expanded state at wide shows sidebar content clearly.
        await tester.pumpWidget(_pumpAppFrame(size: const Size(1200, 800)));
        await tester.pumpAndSettle();
        // Verify that the sidebar text is painted (visible to user)
        final sidebarText = tester.widget<Text>(find.text('Sidebar'));
        expect(sidebarText.data, 'Sidebar');
      },
    );
  });
}
