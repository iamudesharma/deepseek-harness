import 'dart:typed_data';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/historical_image_cache.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAttachmentClient extends ConnectionClient {
  _FakeAttachmentClient({
    this.readAttachmentImpl,
    this.callMethodImpl,
  }) : super(baseUrl: '');

  final Future<Uint8List> Function(SessionId, String)? readAttachmentImpl;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? callMethodImpl;

  final List<Map<String, dynamic>> callMethodPayloads = [];
  final List<String> callMethods = [];

  @override
  Future<Uint8List> readAttachment(SessionId sessionId, String attachmentId) {
    if (readAttachmentImpl != null) return readAttachmentImpl!(sessionId, attachmentId);
    return super.readAttachment(sessionId, attachmentId);
  }

  @override
  Future<Map<String, dynamic>> callMethod(String method, Map<String, dynamic> payload) async {
    callMethods.add(method);
    callMethodPayloads.add(payload);
    if (callMethodImpl != null) return callMethodImpl!(method, payload);
    return <String, dynamic>{};
  }
}

void main() {
  group('HistoricalImageCache fallback wrapper', () {
    test('uses typed readAttachment primary path when bytes available', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final client = _FakeAttachmentClient(
        readAttachmentImpl: (_, __) async => bytes,
      );
      final cache = HistoricalImageCache(client);
      final url = await cache.imageUrl(const SessionId('s1'), 'att-1');
      expect(url, startsWith('data:image/png;base64,'));
      expect(client.callMethods, isEmpty);
      expect(cache.peekImageUrl(const SessionId('s1'), 'att-1'), url);
    });

    test('fallback uses session/attachment with {request:{sessionId,attachmentId}}', () async {
      Map<String, dynamic>? capturedPayload;
      final client = _FakeAttachmentClient(
        readAttachmentImpl: (_, __) async => throw Exception('primary failed'),
        callMethodImpl: (method, payload) async {
          capturedPayload = payload;
          // Return base64 data shape
          return {
            'data': 'aGVsbG8=',
            'attachment': {'mediaType': 'image/jpeg'},
          };
        },
      );
      final cache = HistoricalImageCache(client);
      final url = await cache.imageUrl(const SessionId('sess-42'), 'att-99');
      expect(client.callMethods.single, 'session/attachment');
      expect(capturedPayload, isNotNull);
      // The payload must be wrapped as {request:{sessionId,attachmentId}}.
      // ConnectionClient.callMethod will further wrap in {args: ...}, but the
      // outer shape we pass here must contain 'request'.
      expect(capturedPayload!['request'], isA<Map>());
      final req = capturedPayload!['request'] as Map;
      expect(req['sessionId'], 'sess-42');
      expect(req['attachmentId'], 'att-99');
      expect(url, 'data:image/jpeg;base64,aGVsbG8=');
    });

    test('fallback shape mismatch is not bare {sessionId,attachmentId}', () async {
      // Regression: earlier code passed bare {sessionId,attachmentId} which
      // produced gateway error "missing 'request'". Ensure we never pass bare.
      Map<String, dynamic>? payload;
      final client = _FakeAttachmentClient(
        readAttachmentImpl: (_, __) async => throw Exception('fail'),
        callMethodImpl: (method, p) async {
          payload = p;
          return {'dataUrl': 'data:image/png;base64,abc'};
        },
      );
      final cache = HistoricalImageCache(client);
      await cache.imageUrl(const SessionId('s1'), 'a1');
      expect(payload!.containsKey('sessionId'), isFalse);
      expect(payload!.containsKey('attachmentId'), isFalse);
      expect(payload!.containsKey('request'), isTrue);
    });

    test('dedupes concurrent callers on same key', () async {
      var calls = 0;
      final client = _FakeAttachmentClient(
        readAttachmentImpl: (_, __) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return Uint8List.fromList([9, 9]);
        },
      );
      final cache = HistoricalImageCache(client);
      final f1 = cache.imageUrl(const SessionId('s1'), 'a1');
      final f2 = cache.imageUrl(const SessionId('s1'), 'a1');
      expect(identical(f1, f2), isFalse); // futures are same instance via _inflight? Check equality
      final results = await Future.wait([f1, f2]);
      expect(results[0], results[1]);
      expect(calls, 1);
    });
  });
}
