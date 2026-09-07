import 'package:dsh_flutter/src/platform/open_external.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeUrl parity with markdown/render.tsx', () {
    test('allows http/https/mailto', () {
      expect(sanitizeUrl('https://example.com'), 'https://example.com');
      expect(sanitizeUrl('http://a.b/c?q=1'), 'http://a.b/c?q=1');
      expect(sanitizeUrl('mailto:a@b.com'), 'mailto:a@b.com');
      // Upper-cased schemes are case-insensitive like new URL().protocol.
      expect(sanitizeUrl('HTTP://example.com'), 'HTTP://example.com');
      expect(sanitizeUrl('HtTpS://x'), 'HtTpS://x');
      expect(sanitizeUrl('MAILTO:TEST@Example.COM'), 'MAILTO:TEST@Example.COM');
      // Surrounding whitespace is trimmed before the allowlist check.
      expect(sanitizeUrl('  https://example.com  '), 'https://example.com');
    });
    test('blocks javascript/data/file and relative URLs', () {
      expect(sanitizeUrl('javascript:alert(1)'), isNull);
      expect(sanitizeUrl('JAVASCRIPT:alert(1)'), isNull);
      expect(sanitizeUrl('  javascript:alert(1)'), isNull);
      expect(sanitizeUrl('JaVaScRiPt:alert(1)'), isNull);
      expect(sanitizeUrl('data:text/html,hi'), isNull);
      expect(sanitizeUrl('DATA:text/html,hi'), isNull);
      expect(sanitizeUrl('file:///etc/passwd'), isNull);
      expect(sanitizeUrl('relative/path'), isNull);
      expect(sanitizeUrl('#anchor'), isNull);
      expect(sanitizeUrl('/absolute/path'), isNull);
      expect(sanitizeUrl(''), isNull);
      expect(sanitizeUrl('   '), isNull);
    });
    test('DsMarkdown javascript link never reaches launcher', () {
      // Mirrors primitives_remediation_test's widget tap but at unit seam:
      // sanitizeUrl must null-out script destinations before openExternal.
      expect(sanitizeUrl('javascript:void(0)'), isNull);
      expect(sanitizeUrl('javascript:  void(0)'), isNull);
      expect(
        sanitizeUrl("javascript:alert('xss')"),
        isNull,
      );
    });
  });
  group('isExternalHttpUrl', () {
    test('true only for http/https (mailto is not external)', () {
      expect(isExternalHttpUrl('https://x'), isTrue);
      expect(isExternalHttpUrl('http://x'), isTrue);
      expect(isExternalHttpUrl('HTTP://x'), isTrue);
      expect(isExternalHttpUrl('mailto:a@b'), isFalse);
      expect(isExternalHttpUrl('javascript:x'), isFalse);
      expect(isExternalHttpUrl('  https://x  '), isTrue);
      expect(isExternalHttpUrl('file:///x'), isFalse);
    });
  });
}
