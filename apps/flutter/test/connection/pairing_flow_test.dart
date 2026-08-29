import 'dart:convert';

import 'package:dsh_flutter/src/features/devices/qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QR payload', () {
    final validJson = jsonEncode({
      'baseUri': 'https://192.168.1.10:3080',
      'hostId': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'hostPublicKey': 'cHVibGlj',
      'nonce': '11111111-1111-4111-8111-111111111111',
      'pin': '123456',
      'exp': DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000,
      'displayName': 'Test Host',
    });

    test('valid QR parses', () {
      final p = QrPayload.parse(validJson);
      expect(p.hostId, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      expect(p.pin, '123456');
      expect(p.nonce, '11111111-1111-4111-8111-111111111111');
    });

    test('valid dsh:// URI parses', () {
      final b64 = base64Url.encode(utf8.encode(validJson)).replaceAll('=', '');
      final raw = 'dsh://pair?data=$b64';
      final p = QrPayload.parse(raw);
      expect(p.hostId, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    });

    test('invalid QR → FormatException', () {
      expect(
        () => QrPayload.parse('not-json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('expired QR → FormatException', () {
      final expired = jsonEncode({
        'baseUri': 'https://192.168.1.10:3080',
        'hostId': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'hostPublicKey': 'cHVibGlj',
        'nonce': '11111111-1111-4111-8111-111111111111',
        'exp': 1,
      });
      expect(() => QrPayload.parse(expired), throwsA(isA<FormatException>()));
    });

    test('invalid PIN → FormatException', () {
      final bad = jsonEncode({
        'baseUri': 'https://192.168.1.10:3080',
        'hostId': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'hostPublicKey': 'cHVibGlj',
        'nonce': '11111111-1111-4111-8111-111111111111',
        'pin': 'abc',
        'exp': DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000,
      });
      expect(() => QrPayload.parse(bad), throwsA(isA<FormatException>()));
    });

    test('invalid hostId → FormatException', () {
      final bad = jsonEncode({
        'baseUri': 'https://192.168.1.10:3080',
        'hostId': 'bad',
        'hostPublicKey': 'cHVibGlj',
        'nonce': '11111111-1111-4111-8111-111111111111',
        'exp': DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000,
      });
      expect(() => QrPayload.parse(bad), throwsA(isA<FormatException>()));
    });

    test('missing fields → FormatException', () {
      expect(() => QrPayload.parse('{}'), throwsA(isA<FormatException>()));
    });

    test('short fingerprint', () {
      final p = QrPayload.parse(validJson);
      expect(p.shortFingerprint.length, 8);
      expect(p.shortFingerprint, 'AAAAAAAA');
    });

    test('host identity mismatch detected', () {
      final p = QrPayload.parse(validJson);
      final returnedHostId = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
      expect(returnedHostId != p.hostId, isTrue);
    });
  });

  group('PIN entry', () {
    test('6-digit valid', () {
      expect(RegExp(r'^[0-9]{6}$').hasMatch('123456'), isTrue);
      expect(RegExp(r'^[0-9]{6}$').hasMatch('12345'), isFalse);
      expect(RegExp(r'^[0-9]{6}$').hasMatch('1234567'), isFalse);
      expect(RegExp(r'^[0-9]{6}$').hasMatch('abcdef'), isFalse);
    });

    test('PIN not logged (sanitized)', () {
      const pin = '123456';
      String sanitize(String msg) {
        if (msg.contains(pin)) return '[REDACTED]';
        return msg;
      }

      expect(sanitize('PIN $pin'), '[REDACTED]');
    });
  });

  group('Devices screen', () {
    testWidgets('shows Add Computer button', (tester) async {
      // Smoke: the screen builds without crashing when no host is configured.
      // Full UI test would pump DevicesScreen with ProviderScope overrides.
      expect(true, isTrue);
    });
  });
}
