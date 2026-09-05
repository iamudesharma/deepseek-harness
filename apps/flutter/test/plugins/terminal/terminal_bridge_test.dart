import 'dart:convert';
import 'dart:io';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/plugins/terminal/terminal_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted Typert host answering the six console verbs from canned values,
/// recording every call for payload assertions.
class _TerminalHost {
  final List<(String, Map<String, dynamic>)> calls = [];
  Map<String, dynamic> Function(String, Map<String, dynamic>)? onCall;

  HttpServer? _server;

  Future<String> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      final path = request.uri.path;
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final payload = (decoded['payload'] as Map).cast<String, dynamic>();
      final args = (payload['args'] as Map).cast<String, dynamic>();
      final call = args['request'] as Map? ?? args;
      calls.add((path, call.cast<String, dynamic>()));
      final answer =
          onCall?.call(path, call.cast<String, dynamic>()) ??
          <String, dynamic>{};
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'type': 'server-response',
          'rpcId': decoded['rpcId'],
          'result': {'ok': true, 'value': answer},
        }),
      );
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() async => _server?.close(force: true);
}

ProviderContainer _container(_TerminalHost host, String baseUrl) {
  final container = ProviderContainer(
    overrides: [
      connectionClientProvider.overrideWithValue(
        ConnectionClient(baseUrl: baseUrl),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(host.stop);
  return container;
}

void main() {
  test('open paints the MOTD and selects the session', () async {
    final host = _TerminalHost();
    host.onCall = (path, _) => path == '/api/terminal/open'
        ? {
            'sessionId': 'pty-1',
            'name': 'panel',
            'type': 'shell',
            'status': {'kind': 'running'},
            'motd': r'ready$ ',
          }
        : <String, dynamic>{};
    final container = _container(host, await host.start());

    await container.read(terminalSessionsProvider.notifier).open();
    // Let the MOTD write settle through the emulator buffer.
    await Future<void>.delayed(Duration.zero);

    final pool = container.read(terminalSessionsProvider);
    expect(pool.sessions, hasLength(1));
    expect(pool.selected?.sessionId, 'pty-1');
    expect(host.calls.single.$1, '/api/terminal/open');
  });

  test('typing echoes locally; Enter submits and paints the viewport', () async {
    final host = _TerminalHost();
    host.onCall = (path, call) {
      if (path == '/api/terminal/open') {
        return {
          'sessionId': 'pty-1',
          'type': 'shell',
          'status': {'kind': 'running'},
          'motd': '',
        };
      }
      if (path == '/api/terminal/send') {
        expect(call['text'], 'echo hi');
        expect(call['submit'], true);
        return {
          'viewport': 'hi\r\n',
          'waitReason': 'stdin_read',
          'sessionStatus': {'kind': 'running'},
          'truncated': false,
        };
      }
      return <String, dynamic>{};
    };
    final container = _container(host, await host.start());
    final notifier = container.read(terminalSessionsProvider.notifier);

    await notifier.open();
    final session = container.read(terminalSessionsProvider).selected!;
    notifier.handleOutput(session, 'echo hi');
    expect(session.pending.toString(), 'echo hi');
    notifier.handleOutput(session, '\r');
    // The submit runs async; the send settles through the scripted host.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final settled = container.read(terminalSessionsProvider).selected!;
    expect(settled.pending.toString(), isEmpty);
    expect(settled.busy, isFalse);
    expect(settled.error, isNull);
  });

  test('backspace erases one pending char; arrows are swallowed', () async {
    final host = _TerminalHost();
    host.onCall = (path, _) => path == '/api/terminal/open'
        ? {'sessionId': 'pty-1', 'type': 'shell', 'status': {'kind': 'running'}}
        : <String, dynamic>{};
    final container = _container(host, await host.start());
    final notifier = container.read(terminalSessionsProvider.notifier);

    await notifier.open();
    final session = container.read(terminalSessionsProvider).selected!;
    notifier.handleOutput(session, 'ab');
    notifier.handleOutput(session, '\x7f');
    expect(session.pending.toString(), 'a');
    // Arrow keys carry no logical content for the line-mode host.
    notifier.handleOutput(session, '\x1b[D\x1b[C');
    expect(session.pending.toString(), 'a');
  });

  test('Ctrl+C signals the foreground group without submitting', () async {
    final host = _TerminalHost();
    host.onCall = (path, call) {
      if (path == '/api/terminal/open') {
        return {
          'sessionId': 'pty-1',
          'type': 'shell',
          'status': {'kind': 'running'},
        };
      }
      if (path == '/api/terminal/signal') {
        expect(call['signal'], 'SIGINT');
        return {'delivered': true, 'targetPgid': 7};
      }
      return <String, dynamic>{};
    };
    final container = _container(host, await host.start());
    final notifier = container.read(terminalSessionsProvider.notifier);

    await notifier.open();
    final session = container.read(terminalSessionsProvider).selected!;
    notifier.handleOutput(session, 'sleep 99');
    notifier.handleOutput(session, '\x03');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      host.calls.map((call) => call.$1),
      contains('/api/terminal/signal'),
    );
    expect(host.calls.map((call) => call.$1), isNot(contains('/api/terminal/send')));
    final settled = container.read(terminalSessionsProvider).selected!;
    expect(settled.pending.toString(), isEmpty);
  });

  test('an exited viewport marks the session closed', () async {
    final host = _TerminalHost();
    host.onCall = (path, _) {
      if (path == '/api/terminal/open') {
        return {
          'sessionId': 'pty-1',
          'type': 'shell',
          'status': {'kind': 'running'},
        };
      }
      return {
        'viewport': '',
        'waitReason': 'session_exit',
        'sessionStatus': {
          'kind': 'exited',
          'exitCode': 0,
        },
        'truncated': false,
      };
    };
    final container = _container(host, await host.start());
    final notifier = container.read(terminalSessionsProvider.notifier);

    await notifier.open();
    final session = container.read(terminalSessionsProvider).selected!;
    notifier.handleOutput(session, 'exit\r');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final settled = container.read(terminalSessionsProvider).selected!;
    expect(settled.exited, isTrue);
    expect(settled.exitCode, 0);
  });

  test('close drops the buffer; refresh keeps buffers for live sessions', () async {
    final host = _TerminalHost();
    host.onCall = (path, _) {
      if (path == '/api/terminal/open') {
        return {
          'sessionId': 'pty-1',
          'type': 'shell',
          'status': {'kind': 'running'},
        };
      }
      if (path == '/api/terminal/list') {
        return {
          'sessions': [
            {'sessionId': 'pty-1', 'type': 'shell', 'status': {'kind': 'running'}},
          ],
        };
      }
      if (path == '/api/terminal/close') return {'closed': true};
      return <String, dynamic>{};
    };
    final container = _container(host, await host.start());
    final notifier = container.read(terminalSessionsProvider.notifier);

    await notifier.open();
    final before = container.read(terminalSessionsProvider).selected!;
    await notifier.refresh();
    // The buffer survives a refresh that still reports the session.
    expect(
      container.read(terminalSessionsProvider).selected?.terminal,
      same(before.terminal),
    );

    await notifier.close('pty-1');
    expect(container.read(terminalSessionsProvider).sessions, isEmpty);
    expect(host.calls.last.$1, '/api/terminal/close');
  });
}
