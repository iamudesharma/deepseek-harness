import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/conversation/queue_state.dart';
import 'package:dsh_flutter/src/plugins/subagent/ui/subagent_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted client answering `subagents/list` with a fixed catalog.
class _ListClient extends ConnectionClient {
  _ListClient({required this.catalog}) : super(baseUrl: 'http://127.0.0.1:9');

  final Map<String, dynamic> catalog;

  @override
  Future<Map<String, dynamic>> subagentList({
    required String parentSessionId,
  }) async {
    return catalog;
  }
}

void main() {
  group('isQueueMutable', () {
    test('root sessions are always mutable', () {
      expect(
        isQueueMutable(
          origin: null,
          parentSessionId: null,
          sessionId: 's1',
          childModes: null,
        ),
        isTrue,
      );
      expect(
        isQueueMutable(
          origin: 'user',
          parentSessionId: null,
          sessionId: 's1',
          childModes: null,
        ),
        isTrue,
      );
    });

    test('subagent-owned sessions follow the durable mode', () {
      expect(
        isQueueMutable(
          origin: 'subagent',
          parentSessionId: 'p',
          sessionId: 'c1',
          childModes: const {'c1': 'continuable'},
        ),
        isTrue,
      );
      expect(
        isQueueMutable(
          origin: 'subagent',
          parentSessionId: 'p',
          sessionId: 'c1',
          childModes: const {'c1': 'one-shot'},
        ),
        isFalse,
      );
    });

    test('unknown modes fail closed', () {
      // Loading/error: modes unresolved.
      expect(
        isQueueMutable(
          origin: 'subagent',
          parentSessionId: 'p',
          sessionId: 'c1',
          childModes: null,
        ),
        isFalse,
      );
      // Missing parent link.
      expect(
        isQueueMutable(
          origin: 'subagent',
          parentSessionId: null,
          sessionId: 'c1',
          childModes: const {'c1': 'continuable'},
        ),
        isFalse,
      );
      // Child absent from the catalog.
      expect(
        isQueueMutable(
          origin: 'subagent',
          parentSessionId: 'p',
          sessionId: 'c9',
          childModes: const {'c1': 'continuable'},
        ),
        isFalse,
      );
    });
  });

  group('subagentChildModesProvider', () {
    test('parses child modes, skips diagnostics', () async {
      final container = ProviderContainer(
        overrides: [
          connectionClientProvider.overrideWithValue(
            _ListClient(
              catalog: {
                'entries': [
                  {'kind': 'child', 'id': 'c1', 'mode': 'continuable'},
                  {'kind': 'child', 'id': 'c2', 'mode': 'one-shot'},
                  {'kind': 'diagnostic', 'id': 'c3', 'reason': 'corrupt'},
                  {'kind': 'child', 'id': 'c4', 'mode': 'future-mode'},
                ],
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final modes = await container.read(
        subagentChildModesProvider('p1').future,
      );
      expect(modes, {'c1': 'continuable', 'c2': 'one-shot'});
    });
  });

  group('prompt content validation (API layer)', () {
    test('hasPromptContent mirrors the Host rule', () {
      expect(ConnectionClient.hasPromptContent([]), isFalse);
      expect(
        ConnectionClient.hasPromptContent([
          {'type': 'text', 'text': '   '},
        ]),
        isFalse,
      );
      expect(
        ConnectionClient.hasPromptContent([
          {'type': 'text', 'text': '  hi  '},
        ]),
        isTrue,
      );
      expect(
        ConnectionClient.hasPromptContent([
          {'type': 'image', 'data': '...'},
        ]),
        isTrue,
      );
    });

    test('sendMessage rejects empty content without a round-trip', () async {
      final client = _ListClient(catalog: const {});
      await expectLater(
        client.sendMessage(sessionId: SessionId('s1'), content: '   '),
        throwsArgumentError,
      );
    });
  });
}
