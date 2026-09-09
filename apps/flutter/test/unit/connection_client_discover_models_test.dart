import 'dart:convert';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Regression coverage for `llmDiscoverModels` unwrapping.
///
/// The host's `remoteDiscoverModels` answers `RemoteResult<readonly T[]>`, so
/// `result.value` is a bare JSON array (React reads `response.value`
/// directly; the fixture serves the same shape). [_unwrapValue] wraps a
/// top-level array as `{'_list': ...}` — the face must read that slot, not a
/// `models` key that only older reply shapes carry. Reading `models` alone
/// dropped every discovered candidate and the editor showed "The provider
/// listed no models" for providers the host had just listed.
void main() {
  group('ConnectionClient.llmDiscoverModels', () {
    MockClient mockFor(Object? value) {
      return MockClient((http.Request req) async {
        final envelope = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'type': 'server-response',
            'rpcId': envelope['rpcId'],
            'result': {'ok': true, 'value': value},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
    }

    test('unwraps the host bare-array reply', () async {
      Map<String, dynamic>? captured;
      final mock = MockClient((http.Request req) async {
        captured = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'type': 'server-response',
            'rpcId': captured!['rpcId'],
            'result': {
              'ok': true,
              'value': [
                {
                  'id': 'minimax-m3',
                  'name': 'MiniMax-M3',
                  'contextWindow': 1000000,
                  'maxTokens': 131072,
                },
                {'id': 'qwen3.8-flash'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ConnectionClient(
        baseUrl: 'http://fake',
        httpClient: mock,
      );
      final models = await client.llmDiscoverModels(
        settingsNs: 'llm-pi-ai',
        provider: 'opencode-go',
      );
      expect(models.length, 2);
      expect(models[0]['id'], 'minimax-m3');
      expect(models[0]['name'], 'MiniMax-M3');
      expect(models[0]['contextWindow'], 1000000);
      expect(models[1], {'id': 'qwen3.8-flash'});
      // Wire contract: slash endpoint with {settingsNs, request} args, and
      // absent optionals stay absent (React omits empty baseURL the same way).
      expect(captured!['method'], 'llm/discoverModels');
      final args =
          (captured!['payload'] as Map<String, dynamic>)['args']
              as Map<String, dynamic>;
      expect(args['settingsNs'], 'llm-pi-ai');
      expect(args['request'], {'provider': 'opencode-go'});
    });

    test('keeps the models-key fallback reply shape', () async {
      final client = ConnectionClient(
        baseUrl: 'http://fake',
        httpClient: mockFor({
          'models': [
            {'id': 'a-model', 'name': 'A Model'},
          ],
        }),
      );
      final models = await client.llmDiscoverModels(
        settingsNs: 'llm-pi-ai',
        provider: 'opencode-go',
      );
      expect(models, [
        {'id': 'a-model', 'name': 'A Model'},
      ]);
    });

    test('empty host array stays empty', () async {
      final client = ConnectionClient(
        baseUrl: 'http://fake',
        httpClient: mockFor(const []),
      );
      expect(
        await client.llmDiscoverModels(
          settingsNs: 'llm-pi-ai',
          provider: 'opencode-go',
        ),
        isEmpty,
      );
    });
  });
}
