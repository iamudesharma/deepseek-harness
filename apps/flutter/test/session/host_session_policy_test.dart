import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/session/host_session_policy.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sessionCreatePayload', () {
    test('carries the workspace binding only when declared', () {
      expect(sessionCreatePayload(workspaceId: 'ws-1'), {
        'workspaceId': 'ws-1',
      });
      expect(sessionCreatePayload(), isEmpty);
      // cwd rides alone without a workspace binding.
      expect(sessionCreatePayload(cwd: '/tmp'), {'cwd': '/tmp'});
    });
  });

  group('isWorkspaceAttachFailure', () {
    test(
      'matches the workspace/not-found wire literal in transport errors',
      () {
        expect(
          isWorkspaceAttachFailure(
            Exception(
              'session.create: '
              'workspace/not-found: no workspace ws-9',
            ),
          ),
          isTrue,
        );
        expect(
          isWorkspaceAttachFailure(
            Exception(
              'session.create: '
              'workspace-not-found: no workspace ws-9',
            ),
          ),
          isTrue,
        );
        expect(isWorkspaceAttachFailure(Exception('agent-busy')), isFalse);
      },
    );
    test('matches the typed slash-vocabulary exceptions', () {
      expect(
        isWorkspaceAttachFailure(
          RemoteMethodException(
            code: RpcErrorCode.workspaceNotFound,
            message: 'workspace "ws-9" not found',
            details: const {},
          ),
        ),
        isTrue,
      );
      expect(
        isWorkspaceAttachFailure(
          RemoteMethodException(
            code: RpcErrorCode.workspaceAttachFailed,
            message: 'could not attach',
            details: const {'sessionId': 's-1'},
          ),
        ),
        isTrue,
      );
    });
  });

  group('adoptHostBornSession', () {
    test(
      'projects a blank, idle summary — entity birth precedes first message',
      () {
        final summary = adoptHostBornSession(const SessionId('s-new'), now: 42);
        expect(summary.sessionId.value, 's-new');
        expect(summary.updatedAt, 42);
        expect(summary.running, isFalse);
        expect(summary.blank, isTrue);
      },
    );

    test('defaults updatedAt to wall-clock adoption time', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final summary = adoptHostBornSession(const SessionId('s-new'));
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(summary.updatedAt, inInclusiveRange(before, after));
    });
  });
}
