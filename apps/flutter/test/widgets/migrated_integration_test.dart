import 'package:dsh_flutter/src/features/sidebar/sidebar.dart';
import 'package:dsh_flutter/src/plugins/trajectory/trajectory_provider.dart';
import 'package:dsh_flutter/src/plugins/trajectory/ui/trajectory_screen.dart';
import 'package:dsh_flutter/src/plugins/tool/tool_models.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:dsh_flutter/src/widgets/primitives/ds_tooltip.dart';
import 'package:dsh_flutter/src/widgets/primitives/json_tree.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Composed-surface evidence for the Migrated → Integrated promotions of
/// component.ui-primitives.{JsonTree, Tooltip, icons}: each test drives the
/// primitive through its real consuming widget (trajectory turn records,
/// collapsed sidebar rail) rather than the barrel export.
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    ),
  );
}

/// Trajectory with one settled turn carrying a real tool call fold: map args,
/// a JSON-encoded string result, and a second plain-text-result call.
Trajectory _trajectory() {
  final int now = DateTime.now().millisecondsSinceEpoch;
  return Trajectory(
    sessionId: 's1',
    turns: [
      Turn(
        id: 'turn-1',
        ordinal: 1,
        title: 'Inspect files',
        startTime: now - 1000,
        endTime: now,
        status: TurnStatus.completed,
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'call-1',
            toolName: 'search',
            kind: ToolCallKind.search,
            status: ToolCallStatus.success,
            args: <String, dynamic>{'pattern': 'main', 'limit': 5},
            result: '{"matches": ["a.dart", "b.dart"], "count": 2}',
            time: now - 500,
          ),
          ToolCall(
            id: 'call-2',
            toolName: 'bash',
            kind: ToolCallKind.bash,
            status: ToolCallStatus.error,
            args: <String, dynamic>{'command': 'exit 1'},
            result: 'fatal: not a git repository',
            time: now - 100,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('Trajectory turn records mount DsJsonTree (TrajectoryTable.tsx RecordPayload parity)', () {
    testWidgets(
      'expanded call reveals payload and JSON-container result as trees',
      (tester) async {
        await tester.pumpWidget(
          _wrap(TrajectoryTimeline(trajectory: _trajectory())),
        );
        // Expand the turn card.
        await tester.tap(find.text('Inspect files'));
        await tester.pumpAndSettle();
        expect(find.text('Tool calls'), findsOneWidget);
        // Records render collapsed first.
        expect(find.byType(DsJsonTree), findsNothing);

        // Expand the search record: args tree + decoded result tree.
        await tester.tap(find.text('search · success'));
        await tester.pumpAndSettle();
        expect(find.text('Payload JSON'), findsOneWidget);
        expect(find.text('"pattern"'), findsOneWidget);
        expect(find.text('"main"'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('Result JSON'), findsOneWidget);
        // Nested composite rows summarize as `"name"  [ n ]` titles; the only
        // exact "2" text is the count leaf value.
        expect(find.textContaining('"matches"'), findsOneWidget);
        expect(find.text('"a.dart"'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets('non-JSON result falls back to the mono block', (tester) async {
      await tester.pumpWidget(
        _wrap(TrajectoryTimeline(trajectory: _trajectory())),
      );
      await tester.tap(find.text('Inspect files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bash · error'));
      await tester.pumpAndSettle();
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('fatal: not a git repository'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });
  });

  group('Collapsed rail controls carry DsTooltip plates (SidebarRoot.tsx rail-tooltip parity)', () {
    Finder railTooltips() => find.descendant(
      of: find.byType(NavigationRail),
      matching: find.byType(DsTooltip),
    );

    Future<void> pumpRail(WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(width: 400, child: Sidebar(collapsed: true))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets(
      'rail wraps New session, search, add-workspace and expand controls',
      (tester) async {
        await pumpRail(tester);
        expect(railTooltips(), findsNWidgets(4));
        // No bare Material tooltip param remains: every Tooltip under the rail is
        // DsTooltip-owned with the token plate decoration.
        final ThemeData theme = Theme.of(
          tester.element(find.byType(NavigationRail)),
        );
        final aliases = theme.extension<DswThemeExtension>()!.aliases;
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        expect(tooltips, isNotEmpty);
        for (final Tooltip tooltip in tooltips) {
          expect(
            (tooltip.decoration as BoxDecoration).color,
            aliases.tooltipBg,
          );
          expect(tooltip.waitDuration, const Duration(milliseconds: 500));
        }
      },
    );

    testWidgets('hovering New session shows the plate after the 500ms delay', (
      tester,
    ) async {
      await pumpRail(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.byIcon(Icons.add)));
      // Inside the delay window nothing shows yet.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('New session'), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('New session'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text('New session'), findsNothing);
    });
  });
}
