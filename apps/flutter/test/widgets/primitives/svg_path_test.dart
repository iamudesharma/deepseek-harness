import 'dart:ui' show Offset;

import 'package:dsh_flutter/src/widgets/primitives/svg_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSvgPathData', () {
    test('parses absolute M/L/Z into a closed triangle', () {
      final path = parseSvgPathData('M0 0L10 0L10 8Z');
      final bounds = path.getBounds();
      expect(bounds.left, 0);
      expect(bounds.top, 0);
      expect(bounds.right, 10);
      expect(bounds.bottom, 8);
      expect(path.contains(const Offset(9, 7)), isTrue);
      expect(path.contains(const Offset(1, 7)), isFalse);
    });

    test('parses H/V shorthands against the current point', () {
      final path = parseSvgPathData('M2 3H9V6H2Z');
      final bounds = path.getBounds();
      expect(bounds.left, 2);
      expect(bounds.top, 3);
      expect(bounds.right, 9);
      expect(bounds.bottom, 6);
    });

    test('parses cubic segments with their control points', () {
      final path = parseSvgPathData('M0 0C1 4 3 4 4 0');
      final bounds = path.getBounds();
      // Path.getBounds is the control-point hull bound (conservative), which
      // is exactly what the brand geometry pins rely on.
      expect(bounds.right, 4);
      expect(bounds.bottom, 4);
    });

    test('throws on relative or unsupported commands (fail loud)', () {
      expect(() => parseSvgPathData('m0 0'), throwsFormatException);
      expect(() => parseSvgPathData('M0 0c1 1 2 2 3 3'), throwsFormatException);
      expect(() => parseSvgPathData('M0 0A1 1 0 0 1 5 5'), throwsFormatException);
      expect(() => parseSvgPathData('M0 0Q1 1 5 5'), throwsFormatException);
      expect(() => parseSvgPathData('12 34M0 0'), throwsFormatException);
      expect(() => parseSvgPathData('M0 0X5'), throwsFormatException);
      expect(() => parseSvgPathData('M0'), throwsFormatException);
    });
  });
}
