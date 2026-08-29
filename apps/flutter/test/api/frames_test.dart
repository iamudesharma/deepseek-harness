import 'package:dsh_flutter/src/core/api/frames.dart';
import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MuxFrame.fromJson', () {
    test('decodes session/event with optional tool view', () {
      const rpcId = 'push-1';
      final request = StreamRequest(
        rpcId: RpcId(rpcId),
        frame: MuxFrame.fromJson({
          'type': 'session/event',
          'sessionId': 's1',
          'event': {'type': 'x', 'seq': 1},
          'view': {
            'for': 'call',
            'view': {'kind': 'bash'},
          },
        }),
      );
      final frame = request.frame as SessionEventFrame;
      expect(frame.sessionId.value, 's1');
      expect(frame.event, {'type': 'x', 'seq': 1});
      expect(frame.view, isA<ToolCallIntent>());
    });

    test('decodes control and push variants field-exact', () {
      final subscribed = MuxFrame.fromJson({
        'type': 'session/subscribed',
        'sessionId': 's1',
        'lastSeq': 7,
      }) as SessionSubscribedFrame;
      expect(subscribed.lastSeq, 7);

      final queue = MuxFrame.fromJson({
        'type': 'session/queue',
        'sessionId': 's1',
        'items': [
          {
            'id': 'm1',
            'placement': 'steering',
            'message': {'role': 'user'},
          },
        ],
      }) as SessionQueueFrame;
      expect(queue.items.single.placement, 'steering');

      final projection = MuxFrame.fromJson({
        'type': 'session/projection',
        'sessionId': 's1',
        'key': 'todos',
        'value': [1, 2],
        'seq': 3,
      }) as SessionProjectionFrame;
      expect(projection.seq, 3);

      final streamError = MuxFrame.fromJson({
        'type': 'stream/error',
        'error': {
          'code': 'internal',
          'message': 'carriage detached',
          'details': {},
        },
      }) as StreamErrorFrame;
      expect(streamError.error.code, RpcErrorCode.internal);
    });

    test('approval frames round-trip the answerable shape', () {
      final requested = MuxFrame.fromJson({
        'type': 'approval/requested',
        'sessionId': 's1',
        'approvalId': 'a1',
        'toolName': 'bash',
        'callId': 'c1',
        'reason': 'needs write access',
      }) as ApprovalRequestedFrame;
      expect(requested.toolName, 'bash');
      expect(requested.callId, 'c1');

      final resolved = MuxFrame.fromJson({
        'type': 'approval/resolved',
        'sessionId': 's1',
        'approvalId': 'a1',
        'outcome': 'approved-once',
      }) as ApprovalResolvedFrame;
      expect(resolved.outcome, 'approved-once');
    });

    test('question frames carry ids and outcomes', () {
      final requested = MuxFrame.fromJson({
        'type': 'question/requested',
        'sessionId': 's1',
        'questions': [
          {'id': 'q1'},
        ],
      }) as QuestionRequestedFrame;
      expect(requested.questions.single['id'], 'q1');

      final resolved = MuxFrame.fromJson({
        'type': 'question/resolved',
        'sessionId': 's1',
        'questionRpcId': 'h9',
        'outcome': 'answered',
      }) as QuestionResolvedFrame;
      expect(resolved.questionRpcId.value, 'h9');
    });

    test(
      'throws on an unknown mux discriminant (host schema owns validity)',
      () {
        expect(
          () => MuxFrame.fromJson({'type': 'session/something-else'}),
          throwsArgumentError,
        );
      },
    );
  });

  group('HostFrame.fromJson', () {
    test('decodes lifecycle and workspace snapshots field-exact', () {
      final added = HostFrame.fromJson({
        'type': 'host/session-added',
        'sessionId': 's2',
        'blank': true,
        'origin': 'subagent',
        'cwd': '/tmp/proj',
      }) as SessionAddedFrame;
      expect(added.blank, isTrue);
      expect(added.origin, 'subagent');

      expect(
        (HostFrame.fromJson({
          'type': 'host/session-removed',
          'sessionId': 's2',
        }) as SessionRemovedFrame).sessionId.value,
        's2',
      );

      expect(
        (HostFrame.fromJson({
          'type': 'host/session-status',
          'sessionId': 's2',
          'running': false,
        }) as SessionStatusFrame).running,
        isFalse,
      );

      expect(
        (HostFrame.fromJson({
          'type': 'host/agent-error',
          'sessionId': 's2',
          'message': 'boom',
        }) as AgentErrorFrame).message,
        'boom',
      );

      expect(
        (HostFrame.fromJson({
          'type': 'host/workspace-changed',
          'workspace': {'workspaceId': 'w1'},
        }) as WorkspaceChangedFrame).workspace,
        {'workspaceId': 'w1'},
      );

      expect(
        (HostFrame.fromJson({
          'type': 'host/workspace-order-changed',
          'workspaceIds': ['w2', 'w1'],
        }) as WorkspaceOrderChangedFrame).workspaceIds,
        ['w2', 'w1'],
      );

      expect(
        (HostFrame.fromJson({
          'type': 'host/archived-sessions-changed',
          'archivedSessionIds': ['s9'],
        }) as ArchivedSessionsChangedFrame).archivedSessionIds,
        ['s9'],
      );

      final remote = HostFrame.fromJson({
        'type': 'host/remote-event',
        'event': 'some/host/event',
        'args': [1, 'two'],
      }) as RemoteEventFrame;
      expect(remote.args, [1, 'two']);
    });

    test('throws on an unknown host discriminant', () {
      expect(
        () => HostFrame.fromJson({'type': 'host/nonsense'}),
        throwsArgumentError,
      );
    });
  });

  group('QueuedInboxItem', () {
    test('rejects a placement outside the closed set', () {
      expect(
        () => QueuedInboxItem.fromJson({
          'id': 'm1',
          'placement': 'someday',
          'message': {},
        }),
        throwsArgumentError,
      );
    });
  });
}
