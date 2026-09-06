import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/plugins/terminal/locales.dart';
import 'package:dsh_flutter/src/plugins/terminal/terminal_models.dart';
import 'package:dsh_flutter/src/plugins/terminal/ui/terminal_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Answering fake: opens canned sessions, records the cwd each open sent.
class _RecordingClient extends ConnectionClient {
  _RecordingClient() : super(baseUrl: '');

  /// Open calls observed, in order.
  int opens = 0;

  /// The `cwd` argument of each open call.
  final List<String?> cwds = [];

  @override
  Future<Map<String, dynamic>> terminalOpen({
    String? name,
    String? cwd,
    String? type,
  }) async {
    opens++;
    cwds.add(cwd);
    return {
      'sessionId': 'pty-$opens',
      'name': 'panel-$opens',
      'type': 'shell',
      'status': {'kind': 'running'},
      'motd': 'ready',
    };
  }
}

const SessionSummary _summary = SessionSummary(
  sessionId: SessionId('s1'),
  updatedAt: 0,
  running: false,
  blank: false,
  cwd: '/repo/deepseek',
);

void main() {
  testWidgets('hidden by default: the dock renders nothing', (tester) async {
    final client = _RecordingClient();
    final container = ProviderContainer(
      overrides: [connectionClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    container
        .read(localeServiceProvider)
        .register(kTerminalNamespace, {'zh': kTerminalZh, 'en': kTerminalEn});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TerminalDock(sessionId: 's1'))),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(TerminalView), findsNothing);
    expect(client.opens, 0);
  });

  testWidgets('revealing the dock auto-opens one session at the session cwd', (
    tester,
  ) async {
    final client = _RecordingClient();
    final container = ProviderContainer(
      overrides: [
        connectionClientProvider.overrideWithValue(client),
        sessionByIdProvider.overrideWith((ref, id) => _summary),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(localeServiceProvider)
        .register(kTerminalNamespace, {'zh': kTerminalZh, 'en': kTerminalEn});
    container.read(terminalPanelVisibleProvider.notifier).state = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TerminalDock(sessionId: 's1'))),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Unnamed session, spawned at the owning chat session's cwd, shown in
    // the dock header.
    expect(client.opens, 1);
    expect(client.cwds, ['/repo/deepseek']);
    expect(find.text('/repo/deepseek'), findsOneWidget);
    expect(find.text('panel-1'), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
  });

  testWidgets('the hide control collapses the dock', (tester) async {
    final client = _RecordingClient();
    final container = ProviderContainer(
      overrides: [
        connectionClientProvider.overrideWithValue(client),
        sessionByIdProvider.overrideWith((ref, id) => _summary),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(localeServiceProvider)
        .register(kTerminalNamespace, {'zh': kTerminalZh, 'en': kTerminalEn});
    container.read(terminalPanelVisibleProvider.notifier).state = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TerminalDock(sessionId: 's1'))),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('收起终端'));
    await tester.pump();
    await tester.pump();

    expect(container.read(terminalPanelVisibleProvider), isFalse);
    expect(find.byType(TerminalView), findsNothing);
    // The pool survives the collapse: re-revealing never re-opens.
    expect(client.opens, 1);
  });
}
