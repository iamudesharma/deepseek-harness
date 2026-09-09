/// Session-header preset-pill regression tests — the header itself renders
/// no agent/mode pill; the single visible indicator is slot-owned
/// (`AgentPresetHeaderLabel`, actions id `agent-preset`). A hardcoded copy
/// duplicated the same `summary.agentPreset` state side-by-side with it.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/session_header.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHeader(WidgetTester tester, SessionSummary summary) async {
    final seeded = ProviderContainer();
    addTearDown(seeded.dispose);
    seeded.read(sessionsProvider.notifier).addSession(summary);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: seeded,
        child: MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: SessionHeaderView(sessionId: summary.sessionId.value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SessionSummary summaryWithPreset() => SessionSummary(
    sessionId: const SessionId('s-preset'),
    updatedAt: 0,
    running: false,
    blank: false,
    title: 'hi',
    agentPreset: 'standard',
  );

  testWidgets('title renders with no hardcoded preset pill', (tester) async {
    await pumpHeader(tester, summaryWithPreset());
    expect(find.text('hi'), findsOneWidget);
    // The removed hardcoded pill mapped 'standard' → 'Standard'; the
    // slot-owned label ('Standard mode') arrives only through the actions
    // hole, which is empty without plugin activation.
    expect(find.text('Standard'), findsNothing);
    expect(find.text('Standard mode'), findsNothing);
  });

  testWidgets('header keeps title and tabs; session log is hole-owned', (tester) async {
    await pumpHeader(tester, summaryWithPreset());
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Trajectory'), findsOneWidget);
    // The session-log capsule arrives only through the header.utilities
    // hole (React `session-log-download` contributor); the header itself
    // renders no hardcoded copy.
    expect(find.text('Session log'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
