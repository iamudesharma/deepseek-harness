import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RpcError', () {
    test('decodes a known code with its details object', () {
      final error = RpcError.fromJson({
        'code': 'session-not-found',
        'message': 'no such session',
        'details': {'sessionId': 'abc'},
      });
      expect(error.code, RpcErrorCode.sessionNotFound);
      expect(error.message, 'no such session');
      expect(error.details, {'sessionId': 'abc'});
    });

    test('round-trips through toJson', () {
      const error = RpcError(
        code: RpcErrorCode.internal,
        message: 'boom',
        details: {},
      );
      expect(RpcError.fromJson(error.toJson()).code, RpcErrorCode.internal);
    });

    test('rejects a code outside the closed union (mirrors rpcErrorSchema)', () {
      expect(
        () => RpcError.fromJson({
          'code': 'totally-unknown',
          'message': 'x',
          'details': <String, Object?>{},
        }),
        throwsArgumentError,
      );
    });

    test('rejects a missing details object', () {
      expect(
        () => RpcError.fromJson({'code': 'internal', 'message': 'x'}),
        throwsArgumentError,
      );
    });
  });

  group('transportError', () {
    test('folds any thrown value into the internal catch-all', () {
      final result = transportError<int>(StateError('stream died'));
      result.fold(
        ok: (_) => fail('expected the failure branch'),
        failure: (error) {
          expect(error.code, RpcErrorCode.internal);
          expect(error.message, contains('stream died'));
        },
      );
    });
  });

  group('parseRpcMessage', () {
    test('decodes every wire member and preserves fields', () {
      final messages = [
        ClientRequest(rpcId: const RpcId('r1'), method: 'session.list', payload: {}),
        ServerResponse(rpcId: const RpcId('r1'), result: RpcSuccess<Object?>(42)),
        ServerRequest(rpcId: const RpcId('h1'), method: 'approval.request', payload: {'toolName': 'bash'}),
        ClientResponse(rpcId: const RpcId('h1'), result: RpcFailure<Object?>(const RpcError(code: RpcErrorCode.cancelled, message: 'gone', details: {}))),
      ];
      for (final message in messages) {
        final wire = <String, Object?>{
          'type': message.typeWire,
          'rpcId': message.rpcId.value,
          if (message is ClientRequest) ...{'method': message.method, 'payload': message.payload},
          if (message is ServerRequest) ...{'method': message.method, 'payload': message.payload},
          if (message is ServerResponse) 'result': _wireResult(message.result),
          if (message is ClientResponse) 'result': _wireResult(message.result),
        };
        final decoded = parseRpcMessage(wire);
        expect(decoded.typeWire, message.typeWire);
        expect(decoded.rpcId, message.rpcId);
      }
    });

    test('echo discipline: response ids are whatever the wire carried', () {
      final response = parseRpcMessage({
        'type': 'server-response',
        'rpcId': 'same-id',
        'result': {'ok': true, 'value': null},
      }) as ServerResponse;
      expect(response.rpcId.value, 'same-id');
    });

    test('throws on an unknown discriminant', () {
      expect(
        () => parseRpcMessage({'type': 'carrier-noise'}),
        throwsArgumentError,
      );
    });

    test('throws when result carries neither branch shape', () {
      expect(
        () => parseRpcMessage({
          'type': 'server-response',
          'rpcId': 'r1',
          'result': {'ok': false},
        }),
        throwsArgumentError,
      );
    });
  });
}

Map<String, Object?> _wireResult(RpcResult<Object?> result) => result.fold(
      ok: (value) => {'ok': true, 'value': value},
      failure: (error) => {'ok': false, 'error': error.toJson()},
    );
