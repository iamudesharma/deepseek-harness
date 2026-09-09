import 'dart:async' show Completer, Future;

import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/features/workspace/workspace_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake host client with scripted `session/create` answers.
class _FakeSessionClient extends ConnectionClient {
  _FakeSessionClient() : super(baseUrl: '');

  int createCalls = 0;
  int listCalls = 0;
  Future<SessionId> Function()? onCreate;
  List<SessionSummary> listAnswer = const [];

  @override
  Future<SessionId> createSession({
    String? workspaceId,
    String? cwd,
    String? sessionId,
    String? agentPreset,
  }) async {
    createCalls++;
    final handler = onCreate;
    if (handler != null) return handler();
    return SessionId('host-created');
  }

  @override
  Future<List<SessionSummary>> getSessions() async {
    listCalls++;
    return listAnswer;
  }
}

SessionSummary _summary(
  String id, {
  bool blank = false,
  String? cwd,
  bool running = false,
}) {
  return SessionSummary(
    sessionId: SessionId(id),
    updatedAt: 1,
    running: running,
    blank: blank,
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

ProviderContainer _container(
  _FakeSessionClient client, {
  List<SessionSummary> sessions = const [],
  List<WorkspaceView> workspaces = const [],
  Set<SessionId> archived = const {},
}) {
  final container = ProviderContainer(
    overrides: [
      connectionClientProvider.overrideWithValue(client),
      workspaceListProvider.overrideWithValue(AsyncValue.data(workspaces)),
      workspaceArchivedIdsProvider.overrideWithValue(archived),
    ],
  );
  addTearDown(container.dispose);
  for (final s in sessions) {
    container.read(sessionsProvider.notifier).addSession(s);
  }
  return container;
}

/// Grab a [WidgetRef] bound to [container] (driver for the provider-level
/// ensure helper, which takes the widget ref like its chip call site).
Future<WidgetRef> _refOf(WidgetTester tester, ProviderContainer container) async {
  WidgetRef? captured;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured!;
}

void main() {
  group('resolveSessionWorkspace', () {
    final ws = _workspace(
      'w1',
      'hhh',
      cwd: '/work/hhh',
      sessionIds: [SessionId('s1')],
    );
    test('explicit pick wins over session membership', () {
      final other = _workspace('w2', 'other', sessionIds: [SessionId('s1')]);
      expect(
        resolveSessionWorkspace(
          summary: _summary('s1', cwd: '/work/hhh'),
          selectedId: WorkspaceId('w2'),
          workspaces: [ws, other],
        )?.name,
        'other',
      );
    });

    test('session membership resolves without a pick', () {
      expect(
        resolveSessionWorkspace(
          summary: _summary('s1', cwd: '/work/hhh'),
          selectedId: null,
          workspaces: [ws],
        )?.name,
        'hhh',
      );
    });

    test('unknown session and no pick resolves to null (caller bridges cwd)', () {
      expect(
        resolveSessionWorkspace(
          summary: _summary('ghost', cwd: '/work/hhh'),
          selectedId: null,
          workspaces: [ws],
        ),
        isNull,
      );
      expect(
        resolveSessionWorkspace(
          summary: null,
          selectedId: null,
          workspaces: [ws],
        ),
        isNull,
      );
    });
  });

  group('ensureBlankSessionInWorkspace', () {
    testWidgets('reuses the blank session already in the workspace, no Host create', (
      tester,
    ) async {
      final client = _FakeSessionClient();
      final existing = _summary('s1', blank: true, cwd: '/work/hhh');
      final container = _container(
        client,
        sessions: [existing],
        workspaces: [
          _workspace(
            'w1',
            'hhh',
            cwd: '/work/hhh',
            sessionIds: [SessionId('s1')],
          ),
        ],
      );
      final id = await ensureBlankSessionInWorkspace(
        await _refOf(tester, container),
        WorkspaceId('w1'),
      );
      expect(id, SessionId('s1'));
      expect(client.createCalls, 0);
      expect(container.read(sessionsProvider).current, SessionId('s1'));
    });

    testWidgets('creates and adopts the Host id when no reusable blank exists', (
      tester,
    ) async {
      final client = _FakeSessionClient();
      client.listAnswer = [_summary('host-created', blank: true)];
      final container = _container(
        client,
        sessions: [_summary('s-busy', cwd: '/work/hhh')],
        workspaces: [_workspace('w1', 'hhh', cwd: '/work/hhh')],
      );
      final id = await ensureBlankSessionInWorkspace(
        await _refOf(tester, container),
        WorkspaceId('w1'),
      );
      // Host-authoritative: the returned id is the Host-minted one, and the
      // client never fabricated an identity (create echoed 'host-created').
      expect(id, SessionId('host-created'));
      expect(client.createCalls, 1);
      expect(client.listCalls, 1);
      expect(container.read(sessionsProvider).current, SessionId('host-created'));
    });

    testWidgets('concurrent picks share one Host round-trip', (tester) async {
      final client = _FakeSessionClient();
      // Gate instead of a real delay: testWidgets runs FakeAsync, where
      // `Future.delayed` never fires without pumping.
      final Completer<void> gate = Completer<void>();
      client.onCreate = () async {
        await gate.future;
        return SessionId('host-once');
      };
      client.listAnswer = [_summary('host-once', blank: true)];
      final container = _container(
        client,
        workspaces: [_workspace('w1', 'hhh', cwd: '/work/hhh')],
      );
      final WidgetRef testRef = await _refOf(tester, container);
      final Future<SessionId> first = ensureBlankSessionInWorkspace(
        testRef,
        WorkspaceId('w1'),
      );
      final Future<SessionId> second = ensureBlankSessionInWorkspace(
        testRef,
        WorkspaceId('w1'),
      );
      gate.complete();
      final results = await Future.wait([first, second]);
      expect(results, [SessionId('host-once'), SessionId('host-once')]);
      expect(client.createCalls, 1);
    });

    testWidgets('archived blanks are not reused', (tester) async {
      final client = _FakeSessionClient();
      client.listAnswer = [_summary('host-created', blank: true)];
      final container = _container(
        client,
        sessions: [_summary('s1', blank: true, cwd: '/work/hhh')],
        workspaces: [
          _workspace(
            'w1',
            'hhh',
            cwd: '/work/hhh',
            sessionIds: [SessionId('s1')],
          ),
        ],
        archived: {SessionId('s1')},
      );
      final id = await ensureBlankSessionInWorkspace(
        await _refOf(tester, container),
        WorkspaceId('w1'),
      );
      expect(id, SessionId('host-created'));
      expect(client.createCalls, 1);
    });
  });

  group('createSessionWithFallback', () {
    test('adopts the Host-published echo id on attach failure', () async {
      final client = _FakeSessionClient();
      client.onCreate = () async {
        throw RemoteMethodException(
          code: RpcErrorCode.workspaceAttachFailed,
          message: 'attach failed',
          details: const {'sessionId': 'host-echo-1'},
        );
      };
      final id = await createSessionWithFallback(
        client,
        workspaceId: WorkspaceId('w1'),
        cwd: '/work/hhh',
      );
      expect(id, SessionId('host-echo-1'));
      expect(client.createCalls, 1);
    });

    test('non-attach failures rethrow without a second call', () async {
      final client = _FakeSessionClient();
      client.onCreate = () async {
        throw RemoteMethodException(
          code: RpcErrorCode.internal,
          message: 'boom',
          details: const {},
        );
      };
      await expectLater(
        createSessionWithFallback(client, workspaceId: WorkspaceId('w1')),
        throwsA(isA<RemoteMethodException>()),
      );
      expect(client.createCalls, 1);
    });
  });
}
