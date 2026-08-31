/// ANSI SGR → styled spans for tool-card output. Port of the subset of
/// `ansi.ts` behavior visible in tool cards: SGR color/weight codes are
/// preserved as span styling; other CSI sequences are stripped.
library;

import 'package:flutter/material.dart';

/// Known SGR foreground codes mapped to stable palette roles. Colors resolve
/// through the caller-provided palette so tokens stay centralized.
const Map<int, Color> _standardFg = {
  30: Color(0xFF4B5563), // black-ish
  31: Color(0xFFDC2626), // red
  32: Color(0xFF16A34A), // green
  33: Color(0xFFD97706), // yellow
  34: Color(0xFF2563EB), // blue
  35: Color(0xFF9333EA), // magenta
  36: Color(0xFF0891B2), // cyan
  37: Color(0xFFE5E7EB), // white-ish
};

const Map<int, Color> _brightFg = {
  90: Color(0xFF6B7280),
  91: Color(0xFFF87171),
  92: Color(0xFF4ADE80),
  93: Color(0xFFFBBF24),
  94: Color(0xFF60A5FA),
  95: Color(0xFFC084FC),
  96: Color(0xFF22D3EE),
  97: Color(0xFFF9FAFB),
};

/// Converts [input] (possibly containing ANSI escapes) into a TextSpan whose
/// children carry per-segment color/bold styling. Non-SGR escape sequences
/// and unknown codes degrade to plain text.
TextSpan ansiToSpan(String input, {Color? fallbackColor}) {
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var color = fallbackColor;
  var bold = false;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.bold : null,
        ),
      ),
    );
    buffer.clear();
  }

  final ansi = RegExp(r'\x1B\[([0-9;]*)m');
  var last = 0;
  for (final match in ansi.allMatches(input)) {
    buffer.write(input.substring(last, match.start));
    last = match.end;
    flush();

    final params = match.group(1)!.split(';');
    for (final raw in params) {
      final code = int.tryParse(raw) ?? 0;
      if (code == 0) {
        color = fallbackColor;
        bold = false;
      } else if (code == 1) {
        bold = true;
      } else if (_standardFg.containsKey(code)) {
        color = _standardFg[code];
      } else if (_brightFg.containsKey(code)) {
        color = _brightFg[code];
      }
      // 39 (default fg): keep current color.
    }
  }
  buffer.write(input.substring(last));
  flush();

  if (spans.isEmpty)
    return TextSpan(
      text: input,
      style: TextStyle(color: fallbackColor),
    );
  return TextSpan(children: spans);
}
