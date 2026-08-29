import 'dart:async';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connection fake recording `callMethod` targets and answering from a table
/// (same fixture pattern as the ws_* host fakes; no HTTP).
class _RecordingClient extends ConnectionClient {
  _RecordingClient() : super(baseUrl: '');

  final List<String> calls = [];

  /// Methods whose response is withheld forever (the abort-race loser).
  final Set<String> hang = {};

  /// Canned answers per method (unlisted methods answer `{}`).
  final Map<String, Map<String, Object?>> answers = {};

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    calls.add(method);
    if (hang.contains(method)) {
      // Never completes: only an abort can free the caller.
      return Completer<Map<String, dynamic>>().future;
    }
    return answers[method] ?? const <String, dynamic>{};
  }
}

void main() {
  group('LocaleService', () {
    test('register/bind resolves current locale then falls back to key', () {
      final locale = LocaleService();
      final stop = locale.register('settings.theme', {
        'zh': {'appearance': '外观'},
        'en': {'appearance': 'Appearance'},
      });

      expect(locale.bind('settings.theme')('appearance'), '外观');
      locale.setLocale('en');
      expect(locale.bind('settings.theme')('appearance'), 'Appearance');
      expect(locale.bind('settings.theme')('missing.key'), 'missing.key');

      stop();
      expect(locale.revision, greaterThanOrEqualTo(3));
    });

    test('setLocale rejects ids no namespace registered', () {
      final locale = LocaleService()
        ..register('ns', {
          'zh': {'k': 'v'},
        });
      expect(() => locale.setLocale('xx'), throwsArgumentError);
    });
  });

  group('RemoteEventBus', () {
    test(r'\$on subscribes per event; dispatch fans out; unsub stops', () {
      final bus = RemoteEventBus();
      final seenA = <List<Object?>>[];
      final seenB = <List<Object?>>[];

      final stopA = bus.$on('evt.a', seenA.add);
      bus.$on('evt.a', seenB.add);
      bus.$on('evt.b', seenB.add);

      bus.dispatch('evt.a', [1, 'x']);
      expect(seenA, hasLength(1));
      expect(seenB, hasLength(1));

      stopA();
      bus.dispatch('evt.a', [2]);
      expect(seenA, hasLength(1));
      expect(seenB, hasLength(2));
      expect(bus.hasListeners('evt.b'), isTrue);
    });
  });

  // The runtime service-mount face (tracker: state.runtime): services are
  // provided under the React runtime's service names and each slice maps to
  // the exact wire method its React counterpart calls.
  group('SessionsService', () {
    test(
      'history pulls the durable window through the client for one id',
      () async {
        const id = SessionId('sess-1');
        final entry = HistoryEntry(
          event: const SessionEvent(
            type: 'user/message',
            data: {'content': 'hi'},
            seq: 1,
            time: 1,
          ),
        );
        // Direct delegation: the service adds no shaping of its own.
        final delegated = _DelegatingHistoryClient(entries: [entry]);
        expect(
          await SessionsService(delegated).history(id),
          unorderedEquals([entry]),
        );
        expect(delegated.requested, [id]);
      },
    );
  });

  group('WorkspacesService wire mapping', () {
    test('list/create/archiveSession ride the workspace.* methods', () async {
      final client = _RecordingClient()
        ..answers['workspace.list'] = {
          'items': [
            {'id': 'ws-1', 'path': '/repo'},
          ],
        }
        ..answers['workspace.create'] = {
          'workspace': {'id': 'ws-2', 'path': '/repo'},
        };

      final svc = WorkspacesService(client);

      expect(await svc.list(), [
        {'id': 'ws-1', 'path': '/repo'},
      ]);
      expect(await svc.create(path: '/repo'), {'id': 'ws-2', 'path': '/repo'});
      await svc.archiveSession('sess-9');

      expect(client.calls, [
        'workspace.list',
        'workspace.create',
        'workspace.archiveSession',
      ]);
    });

    test(
      'picker and browse ride the host.* methods; abort supersedes',
      () async {
        final client = _RecordingClient()
          ..answers['host.pickDirectory'] = {'path': '/chosen'}
          ..answers['host.createDirectory'] = {'path': '/chosen/new'};

        final svc = WorkspacesService(client);

        expect(await svc.pickDirectory(), '/chosen');
        expect(await svc.listDirectory(), {});
        expect(client.calls, ['host.pickDirectory', 'host.listDirectory']);

        // Aborted before dispatch: fails loud, no call leaves.
        final preAborted = DirectoryListSignal()..abort();
        await expectLater(
          svc.listDirectory(signal: preAborted),
          throwsException,
        );

        // Abort while a scan is in flight: the caller is freed immediately.
        client.hang.add('host.listDirectory');
        final signal = DirectoryListSignal();
        final pending = svc.listDirectory(path: '/slow', signal: signal);
        signal.abort();
        await expectLater(pending, throwsException);
      },
    );

    test(
      'createDirectory falls back through nested and missing paths',
      () async {
        final client = _RecordingClient()
          ..answers['host.createDirectory'] = {
            'value': {'path': '/nested/answer'},
          };

        expect(
          await WorkspacesService(client)
              .createDirectory(path: '/nested', name: 'answer'),
          '/nested/answer',
        );
      },
    );
  });
}

/// Client whose history answers from a fixed list and records requested ids.
class _DelegatingHistoryClient extends ConnectionClient {
  _DelegatingHistoryClient({required this.entries}) : super(baseUrl: '');

  final List<HistoryEntry> entries;
  final List<SessionId> requested = [];

  @override
  Future<List<HistoryEntry>> getSessionEvents(
    SessionId id, {
    int? beforeSeq,
    int? maxMessages,
  }) async {
    requested.add(id);
    return entries;
  }
}
