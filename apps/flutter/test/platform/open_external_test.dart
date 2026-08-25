import 'package:dsh_flutter/src/platform/open_external.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeUrl', () {
    test('allows http/https/mailto', () {
      expect(sanitizeUrl('https://example.com'), 'https://example.com');
      expect(sanitizeUrl('http://a.b/c?q=1'), 'http://a.b/c?q=1');
      expect(sanitizeUrl('mailto:a@b.com'), 'mailto:a@b.com');
    });
    test('blocks javascript/data/file', () {
      expect(sanitizeUrl('javascript:alert(1)'), isNull);
      expect(sanitizeUrl('data:text/html,hi'), isNull);
      expect(sanitizeUrl('file:///etc/passwd'), isNull);
      expect(sanitizeUrl('relative/path'), isNull);
    });
  });
  group('isExternalHttpUrl', () {
    test('true only for http/https', () {
      expect(isExternalHttpUrl('https://x'), isTrue);
      expect(isExternalHttpUrl('http://x'), isTrue);
      expect(isExternalHttpUrl('mailto:a@b'), isFalse);
      expect(isExternalHttpUrl('javascript:x'), isFalse);
    });
  });
}
