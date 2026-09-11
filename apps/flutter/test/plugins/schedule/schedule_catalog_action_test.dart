import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/session_provider.dart';
import 'package:dsh_flutter/src/plugins/schedule/locales.dart';
import 'package:dsh_flutter/src/plugins/schedule/schedule_models.dart';
import 'package:dsh_flutter/src/plugins/schedule/schedule_provider.dart';
import 'package:dsh_flutter/src/plugins/schedule/ui/schedule_catalog_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _sid = 's-schedule';

Map<String, dynamic> _wire({
  required String id,
  required String kind,
  required String prompt,
  int? everySeconds,
  required String scheduledAt,
}) {
  return {
    'id': id,
    'kind': kind,
    'prompt': prompt,
    // ignore: use_null_aware_elements
    if (everySeconds case final v?) 'everySeconds': v,
    'scheduledAt': scheduledAt,
  };
}

/// English-bound locale with the schedule dictionaries registered (mirrors
/// what `SchedulePlugin.apply` contributes at boot).
LocaleService _englishScheduleLocale() {
  final service = LocaleService();
  service.register(kScheduleNamespace, {
    'zh': kScheduleZh,
    'en': kScheduleEn,
  });
  service.setLocale('en');
  return service;
}

Widget _harness({List<Map<String, dynamic>> schedule = const []}) {
  final id = SessionId(_sid);
  return ProviderScope(
    overrides: [
      currentSessionIdProvider.overrideWithValue(id),
      scheduleProjectionProvider(
        _sid,
      ).overrideWith((ref) => scheduleRecordsFromList(schedule)),
      localeServiceProvider.overrideWithValue(_englishScheduleLocale()),
    ],
    child: const MaterialApp(
      home: Scaffold(body: Center(child: ScheduleCatalogAction())),
    ),
  );
}

void main() {
  testWidgets('renders nothing without schedule records', (tester) async {
    await tester.pumpWidget(_harness());
    expect(find.byType(ScheduleCatalogAction), findsOneWidget);
    expect(find.textContaining('reminder'), findsNothing);
  });

  testWidgets('trigger shows count and menu lists rows', (tester) async {
    await tester.pumpWidget(
      _harness(schedule: [
          _wire(
            id: 'r-over',
            kind: 'after',
            prompt: 'Overdue reminder',
            scheduledAt: '2020-01-01T00:00:00.000Z',
          ),
          _wire(
            id: 'r-every',
            kind: 'every',
            prompt: 'Hourly sync',
            everySeconds: 3600,
            scheduledAt: '2099-01-01T00:00:00.000Z',
          ),
        ]),
    );

    expect(find.text('2 reminders'), findsOneWidget);

    await tester.tap(find.text('2 reminders'));
    await tester.pumpAndSettle();

    expect(find.text('Overdue reminder'), findsOneWidget);
    expect(find.text('Hourly sync'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Once'), findsOneWidget);
    expect(find.text('Every 1 hour'), findsOneWidget);
  });

  testWidgets('renders nothing without a current session', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: ScheduleCatalogAction())),
        ),
      ),
    );
    expect(find.textContaining('reminder'), findsNothing);
  });
}
