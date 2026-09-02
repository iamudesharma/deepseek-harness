import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingClient extends ConnectionClient {
  _RecordingClient() : super(baseUrl: '');
  final List<String> methods = [];
  final List<Map<String, dynamic>> payloads = [];
  Map<String, dynamic> answer = {};

  @override
  Future<Map<String, dynamic>> callMethod(String method, Map<String, dynamic> payload) async {
    methods.add(method);
    payloads.add(payload);
    return answer;
  }
}

void main() {
  group('CommandUi default executor — P1 commands/execute parity', () {
    test('uses commands/execute with agentId/line/images slash, not session/prompt', () async {
      final client = _RecordingClient()..answer = {'commandId': 'c1', 'result': {'kind': 'success', 'text': 'ok'}};
      final exec = defaultCommandExecutor(client);
      final out = await exec(const SessionId('sess-1'), '/plan off');
      expect(client.methods.single, 'commands/execute');
      expect(client.payloads.single['agentId'], 'sess-1');
      expect(client.payloads.single['line'], '/plan off');
      expect(client.payloads.single['images'], isEmpty);
      expect(out.ok, isTrue);
      expect(out.text, 'ok');
    });

    test('unknown command maps to unknown-command error (undefined -> {})', () async {
      final client = _RecordingClient()..answer = const {};
      final exec = defaultCommandExecutor(client);
      final out = await exec(const SessionId('s-1'), '/unknown');
      expect(out.ok, isFalse);
      expect(out.text, 'unknown command: /unknown');
    });

    test('result kind error maps to error outcome', () async {
      final client = _RecordingClient()..answer = {'result': {'kind': 'error', 'text': 'not allowed'}};
      final exec = defaultCommandExecutor(client);
      final out = await exec(const SessionId('s-1'), '/permission danger-full-access');
      expect(out.ok, isFalse);
      expect(out.text, 'not allowed');
    });

    test('legacy command slot fallback still works for older host', () async {
      final client = _RecordingClient()..answer = {'command': {'kind': 'success', 'text': 'legacy ok'}};
      final exec = defaultCommandExecutor(client);
      final out = await exec(const SessionId('s-1'), '/feedback hi');
      expect(out.ok, isTrue);
      expect(out.text, 'legacy ok');
    });

    test('executor does not call session/prompt', () async {
      final client = _RecordingClient()..answer = {'result': {'kind': 'success'}};
      final exec = defaultCommandExecutor(client);
      await exec(const SessionId('s-1'), '/plan');
      expect(client.methods, isNot(contains('session/prompt')));
      expect(client.methods, isNot(contains('session.prompt')));
    });
  });
}
