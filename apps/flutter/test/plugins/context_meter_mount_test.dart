/// Context-meter mount tests — the meter lives in the composer trailing row
/// (React InputBar trailing: model seat, ContextMeter, [stop], primary) and
/// renders nothing until pressure + capacity arrive.
library;

import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/projection_store.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/context_meter.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _pumpMeter(
  WidgetTester tester,
  SessionProjectionStore store,
) async {
  final container = ProviderContainer(
    overrides: [
      sessionProjectionStores.overrideWith((ref, arg) => store),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: ContextMeter(sessionId: 's-meter')),
      ),
    ),
  );
  container
      .read(localeServiceProvider)
      .register(kConversationNamespace, {
        'zh': kConversationZh,
        'en': kConversationEn,
      });
  await tester.pumpAndSettle();
  return container;
}

SessionProjectionStore _storeWithPressure() {
  final store = SessionProjectionStore();
  expect(
    store.offer('contextPressure', {
      'projectedTokens': 4500,
      'contextWindow': 10000,
      'systemTokens': 0,
      'toolsTokens': 0,
      'messageTokens': 0,
    }, 1),
    isTrue,
  );
  expect(
    store.offer('contextBreakdown', {
      'systemTokens': 1000,
      'toolsTokens': 500,
      'messageTokens': 3000,
    }, 1),
    isTrue,
  );
  return store;
}

void main() {
  testWidgets('renders nothing without pressure', (tester) async {
    await _pumpMeter(tester, SessionProjectionStore());
    expect(find.byType(Tooltip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ring carries the localized occupancy label', (tester) async {
    final container = await _pumpMeter(tester, _storeWithPressure());
    container.read(localeServiceProvider).setLocale('en');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == '45% of context used',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens the localized breakdown panel', (tester) async {
    final container = await _pumpMeter(tester, _storeWithPressure());
    container.read(localeServiceProvider).setLocale('en');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(find.text('System prompt'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
