import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/files/file_upload_service.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ConnectionClient _client(
  Future<http.Response> Function(http.BaseRequest) handler,
) {
  return ConnectionClient(
    baseUrl: 'http://localhost:8787',
    httpClient: MockClient(handler),
  );
}

String _receiptBody() => jsonEncode({
      'ok': true,
      'value': {
        'receiptId': 'receipt-1',
        'file': {'attachmentId': 'att-1', 'name': 'a.txt', 'bytes': 3},
      },
    });

void main() {
  test('posts octet-stream with session query and parses receipt', () async {
    http.BaseRequest? seen;
    final service = FileUploadService(
      _client((req) async {
        seen = req;
        return http.Response(_receiptBody(), 200);
      }),
    );
    expect(service.available, isTrue);

    var progressCalls = 0;
    final outcome = await service.upload(
      sessionId: SessionId('s-1'),
      bytes: Uint8List.fromList([1, 2, 3]),
      name: 'a.txt',
      onProgress: (loaded, total) {
        progressCalls++;
        expect(loaded, 3);
        expect(total, 3);
      },
    );

    final sent = seen!;
    expect(sent.url.path, '/api/session/uploadFileBinary');
    expect(sent.url.queryParameters['sessionId'], 's-1');
    expect(sent.url.queryParameters['name'], 'a.txt');
    expect(sent.headers['content-type'], 'application/octet-stream');
    expect(progressCalls, 1);

    expect(outcome, isA<FileUploadSuccess>());
    final receipt = (outcome as FileUploadSuccess).receipt;
    expect(receipt.receiptId, 'receipt-1');
    expect(receipt.attachmentId, 'att-1');
    expect(receipt.name, 'a.txt');
    expect(receipt.bytes, 3);
  });

  test('omits blank names from the query', () async {
    http.BaseRequest? seen;
    final service = FileUploadService(
      _client((req) async {
        seen = req;
        return http.Response(_receiptBody(), 200);
      }),
    );
    await service.upload(
      sessionId: SessionId('s-1'),
      bytes: Uint8List.fromList([9]),
      name: '   ',
    );
    expect(seen!.url.queryParameters.containsKey('name'), isFalse);
  });

  test('returns business failures as values', () async {
    final service = FileUploadService(
      _client((_) async {
        return http.Response(
          jsonEncode({
            'ok': false,
            'error': {'code': 'gone', 'message': 'nope', 'details': {}},
          }),
          200,
        );
      }),
    );
    final outcome = await service.upload(
      sessionId: SessionId('s-1'),
      bytes: Uint8List.fromList([1]),
    );
    expect(outcome, isA<FileUploadFailure>());
    expect((outcome as FileUploadFailure).code, 'gone');
  });

  test('non-200 transport status throws', () async {
    final service = FileUploadService(
      _client((_) async => http.Response('busy', 500)),
    );
    expect(
      () => service.upload(
        sessionId: SessionId('s-1'),
        bytes: Uint8List.fromList([1]),
      ),
      throwsStateError,
    );
  });

  test('malformed JSON throws FormatException', () async {
    final service = FileUploadService(
      _client((_) async => http.Response('not json{{{', 200)),
    );
    await expectLater(
      () => service.upload(
        sessionId: SessionId('s-1'),
        bytes: Uint8List.fromList([1]),
      ),
      throwsFormatException,
    );
  });

  test('invalid shapes throw TypeError', () async {
    for (final body in [
      '{"ok": "yes"}',
      '{"ok": false, "error": {"code": 1}}',
      '{"ok": true, "value": {"receiptId": 7}}',
      '{"ok": true, "value": {"receiptId": "r", "file": {"attachmentId": "a", "name": "n", "bytes": -1}}}',
    ]) {
      final service = FileUploadService(
        _client((_) async => http.Response(body, 200)),
      );
      await expectLater(
        () => service.upload(
          sessionId: SessionId('s-1'),
          bytes: Uint8List.fromList([1]),
        ),
        throwsA(isA<TypeError>()),
      );
    }
  });
}
