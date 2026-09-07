import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dsh_flutter/src/core/connection/tls_pinning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches the fingerprint of the same bytes', () {
    final der = Uint8List.fromList(utf8.encode('fake-cert-der'));
    final fingerprint = base64Url.encode(sha256.convert(der).bytes);
    expect(certificateMatchesPin(der, fingerprint), isTrue);
  });

  test('accepts padded fingerprints and rejects mismatches', () {
    final der = Uint8List.fromList(utf8.encode('fake-cert-der'));
    final unpadded = base64Url
        .encode(sha256.convert(der).bytes)
        .replaceAll('=', '');
    expect(certificateMatchesPin(der, '$unpadded=='), isTrue);
    expect(certificateMatchesPin(der, List.filled(43, 'A').join()), isFalse);
    expect(
      certificateMatchesPin(Uint8List.fromList(utf8.encode('other')), unpadded),
      isFalse,
    );
  });

  test('fails closed on malformed fingerprints', () {
    final der = Uint8List.fromList(utf8.encode('fake-cert-der'));
    expect(certificateMatchesPin(der, ''), isFalse);
    expect(certificateMatchesPin(der, 'short'), isFalse);
    expect(certificateMatchesPin(der, List.filled(44, 'A').join()), isFalse);
  });

  test('normalizeFingerprint strips padding', () {
    expect(normalizeFingerprint('abc=='), 'abc');
    expect(normalizeFingerprint('abc'), 'abc');
  });
}
