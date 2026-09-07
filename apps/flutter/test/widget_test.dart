import 'package:dsh_flutter/main.dart';
import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart'
    show activeSlotsProvider;
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plugins/ws_input/host_fixture.dart' show WsInputRecordingClient;

void main() {
  testWidgets('App loads with welcome', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionClientProvider.overrideWithValue(WsInputRecordingClient()),
        ],
        child: const DshApp(),
      ),
    );

    // Drive the async host activation to quiescence.
    final element = tester.element(find.byType(DshApp));
    final container = ProviderScope.containerOf(element);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      if (container.read(activeSlotsProvider) != null) break;
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Boot succeeded end-to-end: the hero shell swapped in, no error screen.
    expect(find.textContaining('failed to activate'), findsNothing);
    // Hero shell (HeroShell.tsx parity): headline + Preview badge + inert
    // composer hint when no workspace is pending.
    expect(find.text('Into the Unknown'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Choose a workspace to start'), findsOneWidget);
  });
}
