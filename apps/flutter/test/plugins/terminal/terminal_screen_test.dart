import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/terminal/locales.dart';
import 'package:dsh_flutter/src/plugins/terminal/ui/terminal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Answering fake: opens canned sessions, records the cwd each open sent.
///
/// The `terminal/*` wire shape is pinned separately against a scripted host
/// in `connection_client_rpc_test.dart`; this fake keeps the widget test in
/// the fake-async zone (real sockets stall under `testWidgets`).
class _AnsweringClient extends ConnectionClient {
  _AnsweringClient() : super(baseUrl: '');

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

void main() {
  testWidgets('empty pool auto-opens an unnamed session without a name prompt', (
    tester,
  ) async {
    final client = _AnsweringClient();
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
        child: const MaterialApp(home: Scaffold(body: TerminalScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The empty pool auto-opened one session; no name field was shown.
    expect(client.opens, 1);
    expect(client.cwds, [null]);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('panel-1'), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
  });

  testWidgets('the opener row spawns one more session and keeps no owner name', (
    tester,
  ) async {
    final client = _AnsweringClient();
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
        child: const MaterialApp(home: Scaffold(body: TerminalScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('新建会话'));
    await tester.pump();
    await tester.pump();

    expect(client.opens, 2);
    expect(find.text('panel-1'), findsOneWidget);
    expect(find.text('panel-2'), findsOneWidget);
  });
}
