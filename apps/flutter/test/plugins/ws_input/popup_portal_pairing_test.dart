/// OverlayPortal pairing regression: switching sessions swaps the popup
/// shell's controller, and the composer card's GlobalKey reparenting on
/// hero/active transitions then moves the subtree. Previously the portal was
/// keyed by popup identity, so the swap remounted it — orphaning the shared
/// controller pairing (a later dispose nulls the successor's claim) — and
/// the move tripped `OverlayPortal`'s attach assertion in `activate()`
/// (red screen on sidebar "+" in the reported flow).
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:dsh_flutter/src/plugins/commands/command_directory.dart';
import 'package:dsh_flutter/src/plugins/commands/ui/popup_select_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CommandUiService service;

  setUp(() {
    service = CommandUiService(
      directory: CommandDirectory(fetchCommands: (_) async => const []),
      execute: (_, __) async => CommandExecutionOutcome.success(),
    );
    bindActivatedCommandUi(service);
    addTearDown(() {
      bindActivatedCommandUi(null);
      service.disposePopups();
    });
  });

  void seedSession(WidgetTester tester, String sid) {
    final context = tester.element(find.byType(Scaffold));
    final container = ProviderScope.containerOf(context);
    container.read(sessionsProvider.notifier).addSession(
          SessionSummary(
            sessionId: SessionId(sid),
            updatedAt: 0,
            running: false,
            blank: false,
          ),
        );
    container.read(sessionsProvider.notifier).setCurrent(SessionId(sid));
  }

  final GlobalKey moveKey = GlobalKey(debugLabel: 'portal-move-probe');

  Future<void> pumpShell(WidgetTester tester, {required bool centered}) {
    Widget probe() => KeyedSubtree(
          key: moveKey,
          child: const PopupSelectOverlay(),
        );
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            // The mover MUST be a GlobalKey: only global-key reparenting
            // runs the deactivate/activate cycle (a ValueKey swap merely
            // tears down and rebuilds, never calling activate()).
            body: centered ? Center(child: probe()) : Align(
                    alignment: Alignment.topLeft,
                    child: probe(),
                  ),
          ),
        ),
      ),
    );
  }

  testWidgets('session swap plus subtree move keeps the portal pairing', (
    tester,
  ) async {
    await pumpShell(tester, centered: false);
    await tester.pump();
    seedSession(tester, 's-a');
    await tester.pump();
    // Sidebar "+": a fresh session becomes current, swapping the resolved
    // popup controller (previously a portal remount keyed by popup
    // identity, orphaning the pairing mid-frame).
    seedSession(tester, 's-b');
    await tester.pump();
    // Hero transition moves the card subtree (GlobalKey reparenting),
    // reactivating the portal element: the pairing must still hold it.
    await pumpShell(tester, centered: true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
