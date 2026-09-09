import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/workspace/workspace_provider.dart';
import 'package:dsh_flutter/src/plugins/conversation/locales.dart';
import 'package:dsh_flutter/src/plugins/conversation/ui/conversation_screen.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/locales.dart'
    show kPermissionAccessEn, kPermissionAccessNamespace, kPermissionAccessZh;
import 'package:dsh_flutter/src/plugins/permission_presets/permission_session_provider.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/ui/permission_seat.dart';
import 'package:dsh_flutter/src/plugins/workspace/locales.dart'
    show kWorkspaceEn, kWorkspaceNamespace, kWorkspaceZh;
import 'package:dsh_flutter/src/plugins/workspace/ui/workspace_picker_chip.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient extends ConnectionClient {
  _FakeClient() : super(baseUrl: '');
}

SessionSummary _blank(String id, {String? cwd}) {
  return SessionSummary(
    sessionId: SessionId(id),
    updatedAt: 1,
    running: false,
    blank: true,
    cwd: cwd,
  );
}

WorkspaceView _workspace(
  String id,
  String name, {
  String? cwd,
  List<SessionId> sessionIds = const [],
}) {
  return WorkspaceView(
    workspaceId: WorkspaceId(id),
    name: name,
    cwd: cwd,
    sessionIds: sessionIds,
  );
}

ProviderContainer _container({
  List<SessionSummary> sessions = const [],
  List<WorkspaceView> workspaces = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      connectionClientProvider.overrideWithValue(_FakeClient()),
      workspaceListProvider.overrideWithValue(AsyncValue.data(workspaces)),
    ],
  );
  addTearDown(container.dispose);
  container.read(localeServiceProvider).register(kConversationNamespace, {
    'zh': kConversationZh,
    'en': kConversationEn,
  });
  container.read(localeServiceProvider).register(kWorkspaceNamespace, {
    'zh': kWorkspaceZh,
    'en': kWorkspaceEn,
  });
  container.read(localeServiceProvider).register(kPermissionAccessNamespace, {
    'zh': kPermissionAccessZh,
    'en': kPermissionAccessEn,
  });
  container.read(localeServiceProvider).setLocale('en');
  for (final s in sessions) {
    container.read(sessionsProvider.notifier).addSession(s);
  }
  if (sessions.isNotEmpty) {
    // The hero chip and permission seat read the *current* session (React
    // selection cell), not the raw map: select the seeded session.
    container.read(sessionsProvider.notifier).setCurrent(sessions.first.sessionId);
  }
  return container;
}

Future<void> _pumpChip(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(body: WorkspacePickerChip()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('blank hero workspace chip', () {
    testWidgets('shows the session workspace name', (tester) async {
      final container = _container(
        sessions: [_blank('s1', cwd: '/work/hhh')],
        workspaces: [
          _workspace(
            'w1',
            'hhh',
            cwd: '/work/hhh',
            sessionIds: [SessionId('s1')],
          ),
        ],
      );
      await _pumpChip(tester, container);
      expect(find.text('hhh'), findsOneWidget);
      expect(find.text('Choose workspace'), findsNothing);
    });

    testWidgets('bridges a bare cwd through its basename', (tester) async {
      final container = _container(
        sessions: [_blank('s1', cwd: '/work/hhh')],
      );
      await _pumpChip(tester, container);
      expect(find.text('hhh'), findsOneWidget);
    });

    testWidgets('falls back to the choose-workspace placeholder', (
      tester,
    ) async {
      final container = _container(sessions: [_blank('s1')]);
      await _pumpChip(tester, container);
      expect(find.text('Choose workspace'), findsOneWidget);
    });
  });

  group('blank hero composer posture', () {
    Future<void> pumpHero(
      WidgetTester tester,
      ProviderContainer container,
      String sid,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ConversationScreen(sessionId: sid),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hero placeholder when a workspace is set', (tester) async {
      final container = _container(
        sessions: [_blank('s1', cwd: '/work/hhh')],
        workspaces: [
          _workspace(
            'w1',
            'hhh',
            cwd: '/work/hhh',
            sessionIds: [SessionId('s1')],
          ),
        ],
      );
      await pumpHero(tester, container, 's1');
      expect(
        find.text(
          'Describe what you want to build... / commands, @ files or sessions',
        ),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.enabled, isTrue);
    });

    testWidgets('inert choose-workspace posture without a workspace', (
      tester,
    ) async {
      final container = _container(sessions: [_blank('s1')]);
      await pumpHero(tester, container, 's1');
      expect(find.text('Choose a workspace to start'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.enabled, isFalse);
    });
  });

  group('composer permission seat labels', () {
    Future<void> pumpSeat(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const Scaffold(body: PermissionSeat()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('built-in values resolve through the locale dictionary', (
      tester,
    ) async {
      final container = _container(sessions: [_blank('s1')]);
      container.read(permissionSelectProvider('s1').notifier).state =
          const PermissionSelect(
            options: [
              PresetOption(value: 'read-only', name: 'read-only'),
              PresetOption(value: 'workspace-write', name: 'workspace-write'),
            ],
            currentValue: 'workspace-write',
          );
      await pumpSeat(tester, container);
      // React `displayPermissionPreset`: kebab value + conventional host name
      // renders the product label, never the raw id.
      expect(find.text('Workspace Write'), findsOneWidget);
      expect(find.text('workspace-write'), findsNothing);
    });

    testWidgets('renamed presets keep their own name verbatim', (
      tester,
    ) async {
      final container = _container(sessions: [_blank('s1')]);
      container.read(permissionSelectProvider('s1').notifier).state =
          const PermissionSelect(
            options: [
              PresetOption(value: 'workspace-write', name: 'Team Write'),
            ],
            currentValue: 'workspace-write',
          );
      await pumpSeat(tester, container);
      expect(find.text('Team Write'), findsOneWidget);
    });
  });
}
