import 'dart:convert';

import 'package:dsh_flutter/src/features/devices/qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hostId = List.filled(43, 'A').join();
  final hostPub = base64Encode(utf8.encode('fake-spki-bytes'));
  const nonce = '11111111-1111-4111-8111-111111111111';
  const futureExp = 9999999999999;

  Map<String, dynamic> baseJson() => {
    'baseUri': 'https://192.168.1.10:3080',
    'hostId': hostId,
    'hostPublicKey': hostPub,
    'nonce': nonce,
    'exp': futureExp,
  };

  test('parses plain JSON and exposes the fingerprint', () {
    final payload = QrPayload.parse(jsonEncode(baseJson()));
    expect(payload.baseUri.toString(), 'https://192.168.1.10:3080');
    expect(payload.hostId, hostId);
    expect(payload.shortFingerprint, hostId.substring(0, 8));
    expect(payload.pin, isNull);
  });

  test('round-trips through toQrUri and parse', () {
    final payload = QrPayload(
      baseUri: Uri.parse('https://192.168.1.10:3080'),
      hostId: hostId,
      hostPublicKey: hostPub,
      nonce: nonce,
      pin: '123456',
      exp: futureExp,
      displayName: 'Desk',
      certFp: List.filled(43, 'B').join(),
    );
    final uri = payload.toQrUri();
    expect(uri.scheme, 'dsh');
    expect(uri.host, 'pair');
    final decoded = QrPayload.parse(uri.toString());
    expect(decoded.toJson(), payload.toJson());
    expect(decoded.certFp, payload.certFp);
  });

  test('parses bare base64url JSON', () {
    final raw = base64Url.encode(utf8.encode(jsonEncode(baseJson())));
    final payload = QrPayload.parse(raw);
    expect(payload.nonce, nonce);
  });

  test('rejects expired payloads', () {
    final json = baseJson()..['exp'] = 1000;
    expect(() => QrPayload.parse(jsonEncode(json)), throwsFormatException);
  });

  test('rejects missing fields and bad shapes', () {
    expect(() => QrPayload.parse('{}'), throwsFormatException);
    expect(() => QrPayload.parse('dsh://pair'), throwsFormatException);
    expect(() => QrPayload.parse('dsh://pair?data=!!!'), throwsFormatException);
    expect(
      () => QrPayload.parse(jsonEncode({...baseJson(), 'hostId': 'short'})),
      throwsFormatException,
    );
    expect(
      () => QrPayload.parse(jsonEncode({...baseJson(), 'pin': '12'})),
      throwsFormatException,
    );
    expect(
      () => QrPayload.parse(jsonEncode({...baseJson(), 'certFp': 'short'})),
      throwsFormatException,
    );
  });
}
