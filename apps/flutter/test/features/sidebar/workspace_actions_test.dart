import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/sidebar/sidebar.dart';
import 'package:dsh_flutter/src/features/workspace/workspace_provider.dart';
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records `workspace/delete` + `workspace/archiveSession` calls with
/// injectable failures, so the sidebar menus pin the typed wire faces
/// (never the stubbed SnackBar, never a bare `callMethod` envelope).
class _FakeWorkspaceClient extends ConnectionClient {
  _FakeWorkspaceClient() : super(baseUrl: '');

  int deleteCalls = 0;
  String? lastDeleteId;
  Object? deleteError;

  int archiveCalls = 0;
  String? lastArchiveId;
  List<String>? archiveAnswer;
  Object? archiveError;

  @override
  Future<void> workspaceDelete({required String workspaceId}) async {
    deleteCalls++;
    lastDeleteId = workspaceId;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Map<String, dynamic>> workspaceArchiveSession({
    required String sessionId,
  }) async {
    archiveCalls++;
    lastArchiveId = sessionId;
    if (archiveError != null) throw archiveError!;
    return {
      'archivedSessionIds': archiveAnswer ?? [sessionId],
    };
  }
}

const _ws = WorkspaceView(
  workspaceId: WorkspaceId('w1'),
  name: 'One',
  cwd: '/work/one',
  sessionIds: [SessionId('s1'), SessionId('s2')],
);

SessionSummary _session(String id, String title, int updatedAt) =>
    SessionSummary(
      sessionId: SessionId(id),
      updatedAt: updatedAt,
      running: false,
      blank: false,
      cwd: '/work/one',
      title: title,
    );

/// Pumps the real sidebar with a counting workspace-list override so a
/// `ref.invalidate(workspaceListProvider)` is observable as a rebuild.
Future<ProviderContainer> _pumpSidebar(
  WidgetTester tester,
  _FakeWorkspaceClient fake,
  void Function() onBuilds,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionClientProvider.overrideWithValue(fake),
        workspaceListProvider.overrideWith((ref) {
          onBuilds();
          return const AsyncValue.data(<WorkspaceView>[_ws]);
        }),
        deviceClockProvider.overrideWith((ref) => Stream.value(0)),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 360,
            height: 800,
            child: Sidebar(collapsed: false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Sidebar)),
  );
  container.read(sessionsProvider.notifier).addSession(_session('s1', 'Alpha', 1000));
  container.read(sessionsProvider.notifier).addSession(_session('s2', 'Beta', 2000));
  await tester.pumpAndSettle();
  return container;
}

/// The row menu owning [rowLabel] (workspace group header or session row).
Future<void> _openRowMenu(
  WidgetTester tester,
  String rowLabel,
) async {
  final headerRow = find
      .ancestor(of: find.text(rowLabel), matching: find.byType(Row))
      .first;
  final menu = find.descendant(
    of: headerRow,
    matching: find.byType(PopupMenuButton<String>),
  );
  expect(menu, findsOneWidget, reason: 'row menu for $rowLabel');
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('workspace delete — WorkspaceBrowser.tsx parity', () {
    testWidgets('confirm calls the typed wire once and refreshes the list', (
      tester,
    ) async {
      final fake = _FakeWorkspaceClient();
      var builds = 0;
      final container = await _pumpSidebar(tester, fake, () => builds++);
      final before = builds;
      expect(before, greaterThan(0));

      await _openRowMenu(tester, 'One');
      // Workspace menu is [rename, delete]: the trailing item deletes.
      await tester.tap(find.byType(PopupMenuItem<String>).last);
      await tester.pumpAndSettle();
      // Confirm dialog keeps its copy; the trailing action confirms.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.deleteCalls, 1);
      expect(fake.lastDeleteId, 'w1');
      expect(find.textContaining('Delete failed'), findsNothing);
      // The follow-backed list was invalidated (rebuild on next read).
      container.read(workspaceListProvider);
      expect(builds, greaterThan(before));
    });

    testWidgets('host failure surfaces a SnackBar with the real message', (
      tester,
    ) async {
      final fake = _FakeWorkspaceClient()..deleteError = Exception('gone');
      await _pumpSidebar(tester, fake, () {});

      await _openRowMenu(tester, 'One');
      await tester.tap(find.byType(PopupMenuItem<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.deleteCalls, 1);
      expect(find.textContaining('Delete failed'), findsOneWidget);
      expect(find.textContaining('gone'), findsOneWidget);
    });
  });

  group('session archive — navigation.ts parity', () {
    testWidgets('archiving the current session clears the selection', (
      tester,
    ) async {
      final fake = _FakeWorkspaceClient();
      final container = await _pumpSidebar(tester, fake, () {});
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s2'));
      await tester.pumpAndSettle();

      await _openRowMenu(tester, 'Beta');
      // Session menu is [rename, fork, archive]: the trailing item archives.
      await tester.tap(find.byType(PopupMenuItem<String>).last);
      await tester.pumpAndSettle();

      expect(fake.archiveCalls, 1);
      expect(fake.lastArchiveId, 's2');
      expect(container.read(sessionsProvider).current, isNull);
      expect(find.textContaining('Archive failed'), findsNothing);
    });

    testWidgets('archiving a background session keeps the selection', (
      tester,
    ) async {
      final fake = _FakeWorkspaceClient();
      final container = await _pumpSidebar(tester, fake, () {});
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s2'));
      await tester.pumpAndSettle();

      await _openRowMenu(tester, 'Alpha');
      await tester.tap(find.byType(PopupMenuItem<String>).last);
      await tester.pumpAndSettle();

      expect(fake.archiveCalls, 1);
      expect(fake.lastArchiveId, 's1');
      expect(
        container.read(sessionsProvider).current,
        const SessionId('s2'),
      );
    });

    testWidgets('host failure surfaces an Archive failed SnackBar', (
      tester,
    ) async {
      final fake = _FakeWorkspaceClient()
        ..archiveError = Exception('denied');
      final container = await _pumpSidebar(tester, fake, () {});
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s2'));
      await tester.pumpAndSettle();

      await _openRowMenu(tester, 'Beta');
      await tester.tap(find.byType(PopupMenuItem<String>).last);
      await tester.pumpAndSettle();

      expect(fake.archiveCalls, 1);
      expect(find.textContaining('Archive failed'), findsOneWidget);
      // The failed archive keeps the selection (React keeps current too).
      expect(
        container.read(sessionsProvider).current,
        const SessionId('s2'),
      );
    });
  });
}
