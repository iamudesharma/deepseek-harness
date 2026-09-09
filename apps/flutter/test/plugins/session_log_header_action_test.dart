/// Session-log download header-action tests — Flutter port of React
/// `SessionLogDownloadHeaderAction` (`HeaderAction.tsx`): the capsule renders
/// through the `header.utilities` hole only with a current session, and shows
/// the localized action copy.
library;

import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/commands/locales.dart';
import 'package:dsh_flutter/src/plugins/commands/ui/session_log_header_action.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _pumpChip(
  WidgetTester tester, {
  bool withCurrent = true,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(sessionsProvider.notifier)
      .addSession(
        SessionSummary(
          sessionId: const SessionId('s-export'),
          updatedAt: 0,
          running: false,
          blank: false,
          title: 'Export me',
        ),
      );
  if (withCurrent) {
    container.read(sessionsProvider.notifier).setCurrent(
      const SessionId('s-export'),
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: SessionLogHeaderAction()),
      ),
    ),
  );
  container
      .read(localeServiceProvider)
      .register(kSessionLogDownloadNamespace, {
        'zh': kSessionLogDownloadZh,
        'en': kSessionLogDownloadEn,
      });
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders localized capsule with a current session', (
    tester,
  ) async {
    await _pumpChip(tester);
    // Default locale is zh (React `zh` copy).
    expect(find.text('Session 日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing without a current session', (tester) async {
    await _pumpChip(tester, withCurrent: false);
    expect(find.text('Session 日志'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
