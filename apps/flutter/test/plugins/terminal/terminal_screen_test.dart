import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/plugins/terminal/locales.dart';
import 'package:dsh_flutter/src/plugins/terminal/ui/terminal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Answering fake: opens one canned session, records opens.
///
/// The `terminal/*` wire shape is pinned separately against a scripted host
/// in `connection_client_rpc_test.dart`; this fake keeps the widget test in
/// the fake-async zone (real sockets stall under `testWidgets`).
class _AnsweringClient extends ConnectionClient {
  _AnsweringClient() : super(baseUrl: '');

  /// Open calls observed, in order.
  int opens = 0;

  @override
  Future<Map<String, dynamic>> terminalOpen({
    String? name,
    String? cwd,
    String? type,
  }) async {
    opens++;
    return {
      'sessionId': 'pty-1',
      'name': 'panel',
      'type': 'shell',
      'status': {'kind': 'running'},
      'motd': 'ready',
    };
  }
}

void main() {
  testWidgets('empty pool renders the opener; opening selects a tab', (
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

    // Empty state with the localized title and hint.
    expect(find.text('暂无终端会话'), findsOneWidget);

    // Opening through the bottom row creates the tab and the emulator view.
    await tester.tap(find.text('新建会话'));
    await tester.pump();

    expect(client.opens, 1);
    expect(find.text('panel'), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
  });
}
