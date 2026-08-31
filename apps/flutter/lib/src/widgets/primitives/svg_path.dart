/// Minimal SVG path-data parser for the vendored brand artwork extracts.
///
/// The figma fillGeometry dumps in `fish_logo.dart` / `brandwordmark.dart`
/// use absolute `M`/`L`/`H`/`V`/`C`/`Z` commands only; this parser accepts
/// exactly that grammar and throws on anything else so a silently
/// mis-rendered glyph can never ship.
library;

import 'dart:ui' show Path;

/// Parses absolute SVG path data into a [Path].
///
/// Throws [FormatException] for relative commands, arcs, or any other token
/// outside the M/L/H/V/C/Z grammar the brand artwork uses.
Path parseSvgPathData(String d) {
  final Path path = Path();
  final _Scanner scanner = _Scanner(d);
  double x = 0;
  double y = 0;
  while (true) {
    scanner.skipSeparators();
    if (scanner.atEnd) break;
    final String command = scanner.takeCommand();
    switch (command) {
      case 'M':
        x = scanner.takeNumber();
        y = scanner.takeNumber();
        path.moveTo(x, y);
      case 'L':
        x = scanner.takeNumber();
        y = scanner.takeNumber();
        path.lineTo(x, y);
      case 'H':
        x = scanner.takeNumber();
        path.lineTo(x, y);
      case 'V':
        y = scanner.takeNumber();
        path.lineTo(x, y);
      case 'C':
        final double x1 = scanner.takeNumber();
        final double y1 = scanner.takeNumber();
        final double x2 = scanner.takeNumber();
        final double y2 = scanner.takeNumber();
        x = scanner.takeNumber();
        y = scanner.takeNumber();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Z':
        path.close();
      default:
        throw FormatException(
          'unsupported SVG path command "$command" (parser accepts absolute M/L/H/V/C/Z only)',
        );
    }
  }
  return path;
}

/// Character scanner over path data: commands are single letters, numbers are
/// plain decimals separated by spaces, commas, or sign boundaries.
class _Scanner {
  _Scanner(this._data);

  final String _data;
  int _pos = 0;

  bool get atEnd => _pos >= _data.length;

  void skipSeparators() {
    while (_pos < _data.length) {
      final int codeUnit = _data.codeUnitAt(_pos);
      // Space, tab, newline, carriage return, comma.
      if (codeUnit == 0x20 ||
          codeUnit == 0x09 ||
          codeUnit == 0x0A ||
          codeUnit == 0x0D ||
          codeUnit == 0x2C) {
        _pos++;
      } else {
        break;
      }
    }
  }

  String takeCommand() {
    final int codeUnit = _data.codeUnitAt(_pos);
    final bool isLetter =
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A);
    if (!isLetter) {
      throw FormatException(
        'expected an SVG path command at offset $_pos in "$_data"',
      );
    }
    _pos++;
    return _data.substring(_pos - 1, _pos);
  }

  double takeNumber() {
    skipSeparators();
    final int start = _pos;
    if (_pos < _data.length && (_data[_pos] == '-' || _data[_pos] == '+')) {
      _pos++;
    }
    bool seenDigit = false;
    while (_pos < _data.length) {
      final int codeUnit = _data.codeUnitAt(_pos);
      if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        seenDigit = true;
        _pos++;
      } else if (codeUnit == 0x2E) {
        _pos++;
      } else {
        break;
      }
    }
    if (!seenDigit) {
      throw FormatException('expected a number at offset $start in "$_data"');
    }
    return double.parse(_data.substring(start, _pos));
  }
}
