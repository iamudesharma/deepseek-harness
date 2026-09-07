import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/widgets/layout/menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('menu bar wraps content with View and Terminal menus', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        currentSessionIdProvider.overrideWithValue(SessionId('s-1')),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DshMenuBar(child: Text('content'))),
        ),
      ),
    );
    await tester.pump();

    // Content passes through untouched.
    expect(find.text('content'), findsOneWidget);
    // The native menus exist with session-scoped destinations enabled.
    final bar = tester.widget<PlatformMenuBar>(
      find.byType(PlatformMenuBar),
    );
    final top = bar.menus.whereType<PlatformMenu>().toList(growable: false);
    expect(top.map((menu) => menu.label), ['View', 'Terminal']);
    final terminal = top[1].menus
        .whereType<PlatformMenuItem>()
        .toList(growable: false);
    expect(
      terminal.map((item) => item.label),
      ['Open Console Terminal', 'Background Jobs'],
    );
    expect(terminal.every((item) => item.onSelected != null), isTrue);
  });

  testWidgets('session destinations disable without a current session', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DshMenuBar(child: Text('content'))),
        ),
      ),
    );
    await tester.pump();

    final bar = tester.widget<PlatformMenuBar>(
      find.byType(PlatformMenuBar),
    );
    final top = bar.menus.whereType<PlatformMenu>().toList(growable: false);
    final terminal = top[1].menus
        .whereType<PlatformMenuItem>()
        .toList(growable: false);
    // No session, no destinations — but the bar still wraps content.
    expect(terminal.every((item) => item.onSelected == null), isTrue);
    expect(find.text('content'), findsOneWidget);
  });
}
