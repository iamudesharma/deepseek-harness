/// Queue-sheet parity tests — Flutter port of React `QueueDock` behavior:
/// queued-only rows with text preview, localized count, sending-status
/// echoes for unadmitted submissions, and steer gated on running state.
library;

import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart';
import 'package:dsh_flutter/src/plugins/conversation/queue_state.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/queue_sheet.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

QueuedInboxItem _row(String id, String text) => QueuedInboxItem(
  id: id,
  placement: 'queued',
  message: <String, Object?>{
    'content': [
      <String, Object?>{'type': 'text', 'text': text},
    ],
  },
  rpcId: 'rpc-$id',
);

SessionSummary _summary({bool running = true}) => SessionSummary(
  sessionId: const SessionId('s-q'),
  updatedAt: 0,
  running: running,
  blank: false,
  title: 'Q',
);

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  List<QueuedInboxItem> rows = const [],
  List<Message> optimistic = const [],
  bool running = true,
}) async {
  final queue = QueueController()..replace('s-q', rows);
  final container = ProviderContainer(
    overrides: [
      queueProvider.overrideWith((ref) => queue),
      optimisticMessagesProvider.overrideWith((ref, arg) => optimistic),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(sessionsProvider.notifier)
      .addSession(_summary(running: running));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: QueueSheet(sessionId: 's-q')),
      ),
    ),
  );
  container.read(localeServiceProvider).register(kConversationNamespace, {
    'zh': kConversationZh,
    'en': kConversationEn,
  });
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('QueuedInboxItem decodes wire rpcId', () {
    final item = QueuedInboxItem.fromJson({
      'id': 'q1',
      'placement': 'queued',
      'message': <String, Object?>{},
      'rpcId': 'rpc-1',
    });
    expect(item.rpcId, 'rpc-1');
    final legacy = QueuedInboxItem.fromJson({
      'id': 'q2',
      'placement': 'queued',
      'message': <String, Object?>{},
    });
    expect(legacy.rpcId, isNull);
  });

  testWidgets('rows render preview with localized count, no debug id', (
    tester,
  ) async {
    await _pumpSheet(tester, rows: [_row('q1', 'Hello queue')]);
    expect(find.text('Hello queue'), findsOneWidget);
    expect(find.text('1 条排队消息'), findsOneWidget);
    // React shows preview only — no `placement • id` debug subtitle.
    expect(find.textContaining('queued •'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unadmitted submission echoes with sending status', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      rows: [_row('q1', 'Hello queue')],
      optimistic: [
        Message(
          id: 'opt-1',
          role: MessageRole.user,
          content: 'Fresh prompt',
          time: 1,
          requestId: 'rpc-fresh',
        ),
      ],
    );
    expect(find.text('2 条排队消息'), findsOneWidget);
    expect(find.text('Fresh prompt'), findsOneWidget);
    expect(find.text('发送中…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admitted submission echo hides', (tester) async {
    await _pumpSheet(
      tester,
      rows: [_row('q1', 'Hello queue')],
      optimistic: [
        Message(
          id: 'opt-1',
          role: MessageRole.user,
          content: 'Hello queue',
          time: 1,
          requestId: 'rpc-q1',
        ),
      ],
    );
    // Admitted by queue rpcId: only the durable row shows.
    expect(find.text('1 条排队消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle session disables steer without crashing', (tester) async {
    await _pumpSheet(tester, rows: [_row('q1', 'Hello queue')], running: false);
    expect(find.text('Hello queue'), findsOneWidget);
    // Disabled actions render dimmed (React `.action:disabled` 0.45).
    expect(
      find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.45),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
