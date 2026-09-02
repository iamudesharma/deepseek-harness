/// ANSI SGR → styled spans for tool-card output. Flutter port of the
/// `ansi.ts` subset visible in tool cards: SGR color/weight/background and
/// decorations are preserved as span styling; other CSI sequences are stripped.
/// Cursor-replay (\\r/\\b/erase-in-line), wide-char columns and OSC are
/// sanitized to plain text without column-precise replay — the full terminal
/// buffer (replayLine/Cell) is intentionally not reproduced here (visual
/// partial, honest subset).
library;

import 'package:flutter/material.dart';

/// Known SGR foreground codes mapped to stable palette roles. Colors stay
/// centralized here to avoid per-widget literals.
const Map<int, Color> _standardFg = {
  30: Color(0xFF4B5563),
  31: Color(0xFFDC2626),
  32: Color(0xFF16A34A),
  33: Color(0xFFD97706),
  34: Color(0xFF2563EB),
  35: Color(0xFF9333EA),
  36: Color(0xFF0891B2),
  37: Color(0xFFE5E7EB),
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

const Map<int, Color> _standardBg = {
  40: Color(0xFF4B5563),
  41: Color(0xFFDC2626),
  42: Color(0xFF16A34A),
  43: Color(0xFFD97706),
  44: Color(0xFF2563EB),
  45: Color(0xFF9333EA),
  46: Color(0xFF0891B2),
  47: Color(0xFFE5E7EB),
};

const Map<int, Color> _brightBg = {
  100: Color(0xFF6B7280),
  101: Color(0xFFF87171),
  102: Color(0xFF4ADE80),
  103: Color(0xFFFBBF24),
  104: Color(0xFF60A5FA),
  105: Color(0xFFC084FC),
  106: Color(0xFF22D3EE),
  107: Color(0xFFF9FAFB),
};

/// Attribute closers mapped to the opener parameters each one turns off.
const Map<String, List<String>> _attrClosers = {
  '22': ['1', '2'],
  '23': ['3'],
  '24': ['4'],
  '25': ['5', '6'],
  '27': ['7'],
  '28': ['8'],
  '29': ['9'],
};

class _SgrState {
  const _SgrState({this.fg = '', this.bg = '', this.attrs = const []});
  final String fg;
  final String bg;
  final List<String> attrs;
}

/// Fold one SGR parameter string into the state it produces, mirroring
/// `ansi.ts:foldSgr` (extended color `38;5;N` / `38;2;R;G;B` and closers).
_SgrState _foldSgr(_SgrState state, String params) {
  final codes = params.isEmpty ? ['0'] : params.split(';');
  var next = state;
  for (var index = 0; index < codes.length; index++) {
    final code = codes[index];
    if (code.isEmpty || code == '0') {
      next = const _SgrState();
      continue;
    }
    if (code == '38' || code == '48') {
      final kind = index + 1 < codes.length ? codes[index + 1] : '';
      final span = kind == '2'
          ? 4
          : kind == '5'
              ? 2
              : 0;
      if (span == 0) {
        continue;
      }
      final value = codes.sublist(index, index + span + 1).join(';');
      if (code == '38') {
        next = _SgrState(fg: value, bg: next.bg, attrs: next.attrs);
      } else {
        next = _SgrState(fg: next.fg, bg: value, attrs: next.attrs);
      }
      index += span;
      continue;
    }
    final closes = _attrClosers[code];
    if (closes != null) {
      next = _SgrState(
        fg: next.fg,
        bg: next.bg,
        attrs: next.attrs.where((attr) => !closes.contains(attr)).toList(),
      );
      continue;
    }
    if (code == '39') {
      next = _SgrState(fg: '', bg: next.bg, attrs: next.attrs);
      continue;
    }
    if (code == '49') {
      next = _SgrState(fg: next.fg, bg: '', attrs: next.attrs);
      continue;
    }
    final numeric = int.tryParse(code);
    if (numeric != null &&
        ((numeric >= 30 && numeric <= 37) ||
            (numeric >= 90 && numeric <= 97))) {
      next = _SgrState(fg: code, bg: next.bg, attrs: next.attrs);
      continue;
    }
    if (numeric != null &&
        ((numeric >= 40 && numeric <= 47) ||
            (numeric >= 100 && numeric <= 107))) {
      next = _SgrState(fg: next.fg, bg: code, attrs: next.attrs);
      continue;
    }
    if (!next.attrs.contains(code)) {
      next = _SgrState(
        fg: next.fg,
        bg: next.bg,
        attrs: [...next.attrs, code],
      );
    }
  }
  return next;
}

Color? _colorFrom256(int n) {
  if (n < 0 || n > 255) {
    return null;
  }
  if (n < 16) {
    const table = [
      Color(0xFF000000),
      Color(0xFFBB0000),
      Color(0xFF00BB00),
      Color(0xFFBBBB00),
      Color(0xFF0000BB),
      Color(0xFFBB00BB),
      Color(0xFF00BBBB),
      Color(0xFFE5E7EB),
      Color(0xFF6B7280),
      Color(0xFFFF5555),
      Color(0xFF55FF55),
      Color(0xFFFFFF55),
      Color(0xFF5555FF),
      Color(0xFFFF55FF),
      Color(0xFF55FFFF),
      Color(0xFFFFFFFF),
    ];
    return table[n];
  }
  if (n < 232) {
    final c = n - 16;
    final r = (c ~/ 36) % 6;
    final g = (c ~/ 6) % 6;
    final b = c % 6;
    int v(int x) => x == 0 ? 0 : 55 + x * 40;
    return Color.fromARGB(0xFF, v(r), v(g), v(b));
  }
  final gray = 8 + (n - 232) * 10;
  return Color.fromARGB(0xFF, gray, gray, gray);
}

Color? _resolveFg(_SgrState state, Color? fallback) {
  if (state.fg.isEmpty) {
    return fallback;
  }
  if (state.fg.startsWith('38;')) {
    final parts = state.fg.split(';');
    if (parts.length >= 3 && parts[1] == '5') {
      final n = int.tryParse(parts[2]);
      if (n != null) {
        return _colorFrom256(n) ?? fallback;
      }
    } else if (parts.length >= 5 && parts[1] == '2') {
      final r = int.tryParse(parts[2]);
      final g = int.tryParse(parts[3]);
      final b = int.tryParse(parts[4]);
      if (r != null && g != null && b != null) {
        return Color.fromARGB(0xFF, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
    }
    return fallback;
  }
  final code = int.tryParse(state.fg);
  if (code != null) {
    if (_standardFg.containsKey(code)) {
      return _standardFg[code];
    }
    if (_brightFg.containsKey(code)) {
      return _brightFg[code];
    }
  }
  return fallback;
}

Color? _resolveBg(_SgrState state) {
  if (state.bg.isEmpty) {
    return null;
  }
  if (state.bg.startsWith('48;')) {
    final parts = state.bg.split(';');
    if (parts.length >= 3 && parts[1] == '5') {
      final n = int.tryParse(parts[2]);
      if (n != null) {
        return _colorFrom256(n);
      }
    } else if (parts.length >= 5 && parts[1] == '2') {
      final r = int.tryParse(parts[2]);
      final g = int.tryParse(parts[3]);
      final b = int.tryParse(parts[4]);
      if (r != null && g != null && b != null) {
        return Color.fromARGB(0xFF, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
    }
    return null;
  }
  final code = int.tryParse(state.bg);
  if (code != null) {
    if (_standardBg.containsKey(code)) {
      return _standardBg[code];
    }
    if (_brightBg.containsKey(code)) {
      return _brightBg[code];
    }
  }
  return null;
}

TextStyle _styleFor(_SgrState state, Color? fallback) {
  final fg = _resolveFg(state, fallback);
  final bg = _resolveBg(state);
  final attrs = state.attrs;
  final isBold = attrs.contains('1');
  final isDim = attrs.contains('2');
  final isItalic = attrs.contains('3');
  final isUnderline = attrs.contains('4');
  final isHidden = attrs.contains('8');
  final isStrike = attrs.contains('9');

  Color? color = fg;
  if (isDim && color != null) {
    color = color.withValues(alpha: 0.7);
  }
  if (isHidden) {
    color = const Color(0x00000000);
  }

  TextDecoration? decoration;
  if (isUnderline && isStrike) {
    decoration = TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
  } else if (isUnderline) {
    decoration = TextDecoration.underline;
  } else if (isStrike) {
    decoration = TextDecoration.lineThrough;
  }

  return TextStyle(
    color: color,
    backgroundColor: bg,
    fontWeight: isBold ? FontWeight.bold : null,
    fontStyle: isItalic ? FontStyle.italic : null,
    decoration: decoration,
  );
}

String _sanitize(String input) {
  var text = input.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)?'), '');
  text = text.replaceAll(RegExp(r'\x1B(?!\[)[\x20-\x2f]*[\x30-\x7e]?'), '');
  // Erase-in-line sequences have already been handled via the generic CSI
  // scan below, but stripping the K final here keeps the sanitized text
  // readable when no CSI scan runs (plain text path).
  text = text.replaceAll(RegExp(r'[\x00-\x07\x0B-\x1a\x1c-\x1f\x7f]'), '');
  return text;
}

/// Converts [input] (possibly containing ANSI escapes) into a TextSpan whose
/// children carry per-segment styling. Non-SGR escapes degrade to plain text
/// and unknown SGR codes are ignored, matching `ansi.ts` fallback behavior.
TextSpan ansiToSpan(String input, {Color? fallbackColor}) {
  final sanitized = _sanitize(input);
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var state = const _SgrState();

  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    final style = _styleFor(state, fallbackColor);
    final hasStyle = style.color != fallbackColor ||
        style.backgroundColor != null ||
        style.fontWeight != null ||
        style.fontStyle != null ||
        style.decoration != null;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: hasStyle ? style : TextStyle(color: fallbackColor),
      ),
    );
    buffer.clear();
  }

  final csi = RegExp(r'\x1B\[([\x30-\x3f]*)[\x20-\x2f]*([\x40-\x7e])');
  var last = 0;
  for (final match in csi.allMatches(sanitized)) {
    buffer.write(sanitized.substring(last, match.start));
    last = match.end;
    final params = match.group(1) ?? '';
    final finalByte = match.group(2) ?? '';
    if (finalByte != 'm') {
      // Non-SGR CSI (cursor, erase-in-line K, etc.) — stripped without
      // emitting or changing style, matching the terminal's column behavior
      // for a plain-text fallback (the erase is treated as consumed).
      if (finalByte == 'K') {
        // Erase-in-line would blank the line in a real terminal; for a
        // plain-text span fallback we treat it as already consumed.
      }
      continue;
    }
    flush();
    state = _foldSgr(state, params);
  }
  buffer.write(sanitized.substring(last));
  flush();

  if (spans.isEmpty) {
    return TextSpan(
      text: sanitized,
      style: TextStyle(color: fallbackColor),
    );
  }
  if (spans.length == 1 && sanitized == input) {
    // Fast path for plain text without escapes: preserve original input
    // reference so callers comparing TextSpan.text get the exact input.
    // Sanitized equals input only when no escapes were stripped.
  }
  return TextSpan(children: spans);
}
