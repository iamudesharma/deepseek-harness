/// Shared ANSI terminal-output parser for tool cards and terminal blocks.
///
/// Port of `packages/client/ui-primitives/src/ansi.ts` (React), which both
/// front ends must render identically: OSC and non-CSI escapes are stripped,
/// per-line cursor movements replay into a column buffer (carriage return,
/// backspace, erase-in-line, tab stops, wide-char spacer columns, zero-width
/// attachment), and SGR state folds into styled runs whose basic colors map
/// onto theme tokens. Sequences a flowing text card cannot show — alternate
/// screens, vertical cursor addressing, scroll regions, blink — are consumed
/// without effect, exactly as the React parser does.
library;

import 'package:flutter/material.dart';

import '../../theme/dsw_tokens.dart';

/// Theme tokens the 8/16 basic ANSI colors map onto. A foreground-only run
/// maps onto a token so text stays legible on either surface; a run that
/// paints its own background keeps the literal ANSI pair so the authored
/// contrast survives. Magenta and cyan have no token equivalent and fall
/// through to the literal ANSI palette, as do all 256-palette and truecolor
/// values.
class AnsiColors {
  /// Creates the palette from the active theme aliases.
  const AnsiColors({
    required this.labelPrimary,
    required this.labelTertiary,
    required this.stateErrorPrimary,
    required this.stateErrorSecondary,
    required this.stateSuccessPrimary,
    required this.stateSuccessSecondary,
    required this.stateWarnPrimary,
    required this.stateWarnSecondary,
    required this.stateBusinessPrimary,
  });

  /// Builds the palette the same way `ansi.ts` resolves `--dsw-alias-*`
  /// references: every basic color lands on the alias carrying the same
  /// semantic; bright blue lands on the static blue-400 token.
  factory AnsiColors.fromAliases(DswAliases aliases) => AnsiColors(
    labelPrimary: aliases.labelPrimary,
    labelTertiary: aliases.labelTertiary,
    stateErrorPrimary: aliases.stateErrorPrimary,
    stateErrorSecondary: aliases.stateErrorSecondary,
    stateSuccessPrimary: aliases.stateSuccessPrimary,
    stateSuccessSecondary: aliases.stateSuccessSecondary,
    stateWarnPrimary: aliases.stateWarnPrimary,
    stateWarnSecondary: aliases.stateWarnSecondary,
    stateBusinessPrimary: aliases.stateBusinessPrimary,
  );

  /// Black and white both resolve to the primary label color.
  final Color labelPrimary;

  /// Bright black takes the tertiary label color (the muted-gray role).
  final Color labelTertiary;
  final Color stateErrorPrimary;
  final Color stateErrorSecondary;
  final Color stateSuccessPrimary;
  final Color stateSuccessSecondary;
  final Color stateWarnPrimary;
  final Color stateWarnSecondary;
  final Color stateBusinessPrimary;

  /// Static blue-400 (`--dsw-static-blue-400`), theme-independent.
  static const Color blue400 = DswTokens.blue400;
}

/// One run of terminal text; `style` is null for text that carries no SGR
/// state and inherits the surrounding text style.
class AnsiSpan {
  /// Creates a span.
  const AnsiSpan(this.text, this.style);

  /// The run's plain text, free of escape sequences and newlines.
  final String text;

  /// Resolved text style, or null when the run needs no wrapper.
  final TextStyle? style;
}

/// The spans of one output line, in order.
typedef AnsiLine = List<AnsiSpan>;

/// OSC strings (window title, hyperlinks), with or without their terminator.
final RegExp _oscSequence = RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)?');

/// Escape sequences other than CSI: charset selection, single-shift, reset.
final RegExp _nonCsiEscape = RegExp(r'\x1B(?!\[)[\x20-\x2f]*[\x30-\x7e]?');

/// The CSI shape every scanner below splits on, so a sequence is one unit
/// whether it is folded for SGR or replayed for cursor movement.
final RegExp _csiSequence = RegExp(r'\x1B\[([\x30-\x3f]*)[\x20-\x2f]*([\x40-\x7e])');

/// Lines whose cursor movements have to be replayed: a carriage return, a
/// backspace, or an erase-in-line. The erase pattern matches the same CSI
/// shape the replay parses, so `\x1b[1;2K` cannot slip past this guard and
/// skip its own erase.
final RegExp _needsReplay = RegExp(r'\r|\x08|\x1B\[[\x30-\x3f]*[\x20-\x2f]*K');

/// A `\r` that only terminates a CRLF line end.
final RegExp _trailingCr = RegExp(r'\r+$');

/// C0 controls with no display meaning here. Tab, newline, backspace and ESC
/// survive: the first two for layout, backspace for the cursor replay, ESC
/// for the CSI split.
final RegExp _inertControl = RegExp(r'[\x00-\x07\x0B-\x1A\x1C-\x1F\x7F]');

/// Terminal tab stop width; a tab advances to the next multiple of this.
const int _tabWidth = 8;

/// Whether a code point occupies two terminal columns (CJK, fullwidth forms,
/// emoji presentation). Covers the ranges command output realistically
/// carries; text-presentation symbols such as U+2713 stay one column, which
/// keeps progress lines aligned exactly as a real terminal draws them.
bool _isWide(int code) {
  if (code < 0x1100) {
    return false;
  }
  return (code >= 0x1100 && code <= 0x115F) ||
      (code >= 0x2E80 && code <= 0x303E) ||
      (code >= 0x3041 && code <= 0x33FF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0xA000 && code <= 0xA4CF) ||
      (code >= 0xA960 && code <= 0xA97F) ||
      (code >= 0xAC00 && code <= 0xD7A3) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0xFE10 && code <= 0xFE19) ||
      (code >= 0xFE30 && code <= 0xFE6F) ||
      (code >= 0xFF01 && code <= 0xFF60) ||
      (code >= 0xFFE0 && code <= 0xFFE6) ||
      (code >= 0x1F300 && code <= 0x1F64F) ||
      (code >= 0x1F680 && code <= 0x1F6FF) ||
      (code >= 0x1F900 && code <= 0x1F9FF) ||
      (code >= 0x1FA00 && code <= 0x1FAFF) ||
      (code >= 0x20000 && code <= 0x2FFFD);
}

/// Whether a code point advances no column: combining marks, variation
/// selectors, and format characters from the ranges terminal output
/// realistically carries (a pragmatic subset of Unicode's Mn/Me/Cf
/// categories; Dart regular expressions have no script property classes).
bool _isZeroWidth(int code) {
  return (code >= 0x0300 && code <= 0x036F) ||
      (code >= 0x0483 && code <= 0x0489) ||
      (code >= 0x0591 && code <= 0x05BD) ||
      (code >= 0x0610 && code <= 0x061A) ||
      (code >= 0x064B && code <= 0x065F) ||
      code == 0x0670 ||
      (code >= 0x06D6 && code <= 0x06DC) ||
      (code >= 0x200B && code <= 0x200F) ||
      (code >= 0x202A && code <= 0x202E) ||
      (code >= 0x2060 && code <= 0x2064) ||
      (code >= 0x206A && code <= 0x206F) ||
      (code >= 0xFE00 && code <= 0xFE0F) ||
      (code >= 0xFE20 && code <= 0xFE2F) ||
      code == 0xFEFF ||
      (code >= 0xE0100 && code <= 0xE01EF);
}

/// A cell's graphic state, normalized. Held as fields rather than as the raw
/// sequence history because a terminal tracks current state, not a
/// transcript: accumulating sequences made each state boundary re-emit the
/// whole chain, and it also makes the attribute closers every chalk-based
/// tool writes — `39`, `49`, `22`, `23`, `24`, `27`, `29` — actually close
/// their attribute instead of appending to it.
class _SgrState {
  const _SgrState({this.fg = '', this.bg = '', this.attrs = const []});

  /// The default state: no color, no attributes.
  static const _SgrState none = _SgrState();

  final String fg;
  final String bg;

  /// Attribute parameters in force, e.g. `1` (bold) or `4` (underline).
  final List<String> attrs;

  /// Whether both states carry the same normalized graphic state, so a run
  /// boundary is only emitted on a change.
  bool sameAs(_SgrState other) {
    if (fg != other.fg || bg != other.bg || attrs.length != other.attrs.length) {
      return false;
    }
    for (var index = 0; index < attrs.length; index++) {
      if (attrs[index] != other.attrs[index]) {
        return false;
      }
    }
    return true;
  }
}

/// Attribute closers, mapped to the opener parameters each one turns off.
const Map<String, List<String>> _attrClosers = {
  '22': ['1', '2'],
  '23': ['3'],
  '24': ['4'],
  '25': ['5', '6'],
  '27': ['7'],
  '28': ['8'],
  '29': ['9'],
};

/// Fold one SGR sequence's parameters into the state it produces.
_SgrState _foldSgr(_SgrState state, String params) {
  final codes = params.isEmpty ? ['0'] : params.split(';');
  var next = state;
  for (var index = 0; index < codes.length; index++) {
    final code = codes[index];
    if (code.isEmpty || code == '0') {
      next = _SgrState.none;
      continue;
    }
    // Extended color: `38;5;N` / `38;2;R;G;B` and the `48` background pair
    // consume their own arguments, so they are taken whole. Truncated
    // sequences at the end of a parameter string take what is there.
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
      final end = (index + span + 1).clamp(0, codes.length);
      final value = codes.sublist(index, end).join(';');
      next = code == '38'
          ? _SgrState(fg: value, bg: next.bg, attrs: next.attrs)
          : _SgrState(fg: next.fg, bg: value, attrs: next.attrs);
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
      next = _SgrState(fg: next.fg, bg: next.bg, attrs: [...next.attrs, code]);
    }
  }
  return next;
}

/// One replayed column: the state it was written with, and its character.
class _Cell {
  const _Cell(this.sgr, this.char, {this.spacer = false});

  final _SgrState sgr;
  final String char;

  /// The trailing half of a wide character's two-column pair.
  final bool spacer;
}

/// One run of replayed or scanned text with the SGR state it was written
/// under.
class _Run {
  _Run(this.text, this.sgr);
  String text;
  final _SgrState sgr;
}

void _setCell(List<_Cell?> columns, int index, _Cell cell) {
  while (columns.length <= index) {
    columns.add(null);
  }
  columns[index] = cell;
}

_Cell? _cellAt(List<_Cell?> columns, int index) =>
    index < columns.length ? columns[index] : null;

/// Whether the character a cell holds occupies two columns; only the lead
/// code point decides, because zero-width marks attach after the base.
bool _cellIsWide(_Cell? cell) {
  if (cell == null || cell.char.isEmpty) {
    return false;
  }
  return _isWide(cell.char.runes.first);
}

/// Replay one line's cursor movements the way a terminal paints it, into a
/// column buffer. Carriage return and backspace only move the cursor —
/// neither erases anything — so what a reader sees is whatever each column
/// last had written to it: `100%\rOK` shows `OK0%` because the redraw is
/// shorter than the frame beneath it, and a trailing `abc\b` still shows
/// `abc` because nothing ever overwrote the `c`.
///
/// A CSI sequence occupies no column; it changes the state the next writes
/// are stamped with, which is how a terminal stores color per cell. Columns
/// come back as runs, merged wherever the state does not change.
/// Returns the runs plus the SGR state at the scan's end, which the next
/// line enters with (a newline does not reset it).
(List<_Run>, _SgrState) _replayLine(String line, _SgrState entrySgr) {
  final columns = <_Cell?>[];
  var cursor = 0;
  var sgr = entrySgr;
  var at = 0;

  // Clear a cell and, for a wide pair, its partner: a terminal erases both.
  void clear(int index, String fill) {
    final cell = _cellAt(columns, index);
    if (cell?.spacer == true && index > 0) {
      _setCell(columns, index - 1, _Cell(sgr, fill));
    } else if (cell != null &&
        _cellIsWide(cell) &&
        _cellAt(columns, index + 1)?.spacer == true) {
      _setCell(columns, index + 1, _Cell(sgr, fill));
    }
    _setCell(columns, index, _Cell(sgr, fill));
  }

  void consume(String chunk) {
    var i = 0;
    while (i < chunk.length) {
      final unit = chunk.codeUnitAt(i);
      int code;
      int len;
      if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < chunk.length) {
        final next = chunk.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          code = 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
          len = 2;
        } else {
          code = unit;
          len = 1;
        }
      } else {
        code = unit;
        len = 1;
      }
      final char = chunk.substring(i, i + len);
      i += len;
      if (code == 0x0D) {
        cursor = 0;
        continue;
      }
      if (code == 0x08) {
        if (cursor > 0) {
          cursor--;
        }
        continue;
      }
      if (code == 0x09) {
        // A tab advances to the next 8-column stop, leaving the cells it
        // skips as they were — which is how a redraw can leave a tabbed
        // column standing. Column alignment is the whole point of this card.
        final stop = cursor + _tabWidth - (cursor % _tabWidth);
        while (cursor < stop) {
          if (_cellAt(columns, cursor) == null) {
            _setCell(columns, cursor, _Cell(sgr, ' '));
          }
          cursor++;
        }
        continue;
      }
      if (code < 0x20 || code == 0x7F) {
        continue;
      }
      if (_isZeroWidth(code)) {
        // No column of its own: it attaches to the cell already written, so
        // a redraw that covers that cell covers the mark with it. With no
        // cell to attach to a terminal shows nothing rather than a lone
        // accent.
        if (cursor > 0) {
          final base = _cellAt(columns, cursor - 1);
          if (base != null) {
            columns[cursor - 1] = _Cell(base.sgr, base.char + char);
          }
        }
        continue;
      }
      // Writing over either half of a wide pair blanks the other half, since
      // a terminal cannot leave one cell of a two-cell glyph standing.
      clear(cursor, ' ');
      _setCell(columns, cursor, _Cell(sgr, char));
      cursor++;
      // A wide character occupies two columns; the trailing one is a spacer,
      // marked so that overwriting the lead cell leaves a blank behind
      // instead of closing the gap and shifting everything after it left.
      if (_isWide(code)) {
        _setCell(columns, cursor, _Cell(sgr, '', spacer: true));
        cursor++;
      }
    }
  }

  for (final match in _csiSequence.allMatches(line)) {
    consume(line.substring(at, match.start));
    at = match.end;
    final params = match.group(1) ?? '';
    final finalByte = match.group(2) ?? '';
    if (finalByte == 'K') {
      // Erase in line: the fixed companion of `\r` in every spinner and
      // progress bar. `1` blanks from the line start through the cursor
      // column (inclusive, per the CSI spec) rather than dropping those
      // cells, since the cursor does not move and a later write can still
      // land past them. Only the first parameter selects the mode; a
      // terminal ignores the rest (`1;2K` erases exactly as `1K`).
      final mode = params.split(';')[0];
      if (mode == '1') {
        for (var index = 0; index <= cursor; index++) {
          clear(index, ' ');
        }
      } else {
        final keep = mode == '2' ? 0 : cursor;
        if (columns.length > keep) {
          columns.removeRange(keep, columns.length);
        }
      }
      continue;
    }
    // Only SGR carries graphic state; every other final byte is a cursor or
    // erase action that must not affect a cell's style.
    if (finalByte != 'm') {
      continue;
    }
    sgr = _foldSgr(sgr, params);
  }
  consume(line.substring(at));

  final runs = <_Run>[];
  for (var index = 0; index < columns.length; index++) {
    final column = columns[index] ?? const _Cell(_SgrState.none, ' ');
    // A spacer still holds its column. While its lead cell survives, the
    // wide glyph spans both and the spacer emits nothing; once a later write
    // replaced that lead, the terminal blanks the spacer instead of closing
    // the gap, so emitting nothing would shift everything after it one
    // column left.
    final leadIntact = index > 0 && _cellIsWide(columns[index - 1]);
    final text = column.spacer && !leadIntact ? ' ' : column.char;
    if (text.isEmpty) {
      continue;
    }
    if (runs.isNotEmpty && runs.last.sgr.sameAs(column.sgr)) {
      runs.last.text += text;
    } else {
      runs.add(_Run(text, column.sgr));
    }
  }
  return (runs, sgr);
}

/// Split one line that needs no replay into SGR runs. The line carries no
/// carriage return (stripped) and no backspace (it would have triggered the
/// replay path); a tab stays literal text, and every other control is inert.
(List<_Run>, _SgrState) _scanLine(String line, _SgrState entrySgr) {
  final runs = <_Run>[];
  var sgr = entrySgr;
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    final text = buffer.toString();
    if (runs.isNotEmpty && runs.last.sgr.sameAs(sgr)) {
      runs.last.text += text;
    } else {
      runs.add(_Run(text, sgr));
    }
    buffer.clear();
  }

  var at = 0;
  for (final match in _csiSequence.allMatches(line)) {
    buffer.write(line.substring(at, match.start).replaceAll(_inertControl, ''));
    at = match.end;
    if (match.group(2) != 'm') {
      continue;
    }
    flush();
    sgr = _foldSgr(sgr, match.group(1) ?? '');
  }
  buffer.write(line.substring(at).replaceAll(_inertControl, ''));
  flush();
  return (runs, sgr);
}

/// The 16-entry ANSI palette `anser` resolves the basic codes to; 256-palette
/// and truecolor values stay literal through the 256-color formula below.
const List<Color> _basicPalette = [
  Color(0xFF000000),
  Color(0xFFBB0000),
  Color(0xFF00BB00),
  Color(0xFFBBBB00),
  Color(0xFF0000BB),
  Color(0xFFBB00BB),
  Color(0xFF00BBBB),
  Color(0xFFBBBBBB),
  Color(0xFF555555),
  Color(0xFFFF5555),
  Color(0xFF00FF00),
  Color(0xFFFFFF55),
  Color(0xFF5555FF),
  Color(0xFFFF55FF),
  Color(0xFF55FFFF),
  Color(0xFFFFFFFF),
];

Color? _basicFg(int code, AnsiColors? colors, bool tokenAllowed) {
  final palette = tokenAllowed ? colors : null;
  return switch (code) {
    30 => palette?.labelPrimary ?? _basicPalette[0],
    37 => _basicPalette[7],
    90 => palette?.labelTertiary ?? _basicPalette[8],
    97 => palette?.labelPrimary ?? _basicPalette[15],
    31 => palette?.stateErrorPrimary ?? _basicPalette[1],
    32 => palette?.stateSuccessPrimary ?? _basicPalette[2],
    33 => palette?.stateWarnPrimary ?? _basicPalette[3],
    34 => palette?.stateBusinessPrimary ?? _basicPalette[4],
    91 => palette?.stateErrorSecondary ?? _basicPalette[9],
    92 => palette?.stateSuccessSecondary ?? _basicPalette[10],
    93 => palette?.stateWarnSecondary ?? _basicPalette[11],
    94 => palette != null ? AnsiColors.blue400 : _basicPalette[12],
    35 => _basicPalette[5],
    36 => _basicPalette[6],
    95 => _basicPalette[13],
    96 => _basicPalette[14],
    _ => null,
  };
}

Color? _basicBg(int code) {
  return switch (code) {
    >= 40 && <= 47 => _basicPalette[code - 40],
    >= 100 && <= 107 => _basicPalette[code - 100 + 8],
    _ => null,
  };
}

Color? _colorFrom256(int n) {
  if (n < 0 || n > 255) {
    return null;
  }
  if (n < 16) {
    return _basicPalette[n];
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

/// Resolve an extended-color parameter string (`38;5;N` / `38;2;R;G;B`) or a
/// plain SGR color code to its literal color; malformed values inherit.
Color? _extendedColor(String value) {
  final parts = value.split(';');
  if (parts.length >= 3 && parts[1] == '5') {
    return _colorFrom256(int.tryParse(parts[2]) ?? -1);
  }
  if (parts.length >= 5 && parts[1] == '2') {
    final r = int.tryParse(parts[2]);
    final g = int.tryParse(parts[3]);
    final b = int.tryParse(parts[4]);
    if (r != null && g != null && b != null) {
      return Color.fromARGB(
        0xFF,
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
      );
    }
  }
  return null;
}

Color? _resolveFg(String code, AnsiColors? colors, bool tokenAllowed) {
  if (code.isEmpty) {
    return null;
  }
  if (code.startsWith('38;')) {
    return _extendedColor(code);
  }
  final n = int.tryParse(code);
  if (n == null) {
    return null;
  }
  return _basicFg(n, colors, tokenAllowed);
}

Color? _resolveBg(String code) {
  if (code.isEmpty) {
    return null;
  }
  if (code.startsWith('48;')) {
    return _extendedColor(code);
  }
  final n = int.tryParse(code);
  if (n == null) {
    return null;
  }
  return _basicBg(n);
}

/// Resolve one run's colors and decorations. `blink` is deliberately absent
/// — animated text is not reproduced. Reverse is consumed by swapping the
/// run's foreground and background, as the reference parser does. Underline
/// and strikethrough share one decoration slot, so in a run declaring both,
/// the later declaration wins.
TextStyle? _resolveRun(_SgrState state, AnsiColors? colors, Color? defaultColor) {
  final attrs = state.attrs;
  final reverse = attrs.contains('7');
  // Resolve the colors from their own codes first; reverse then swaps the
  // resolved pair, as the reference parser does. The token rule reads the
  // original background: a run that paints its own background keeps the
  // literal ANSI pair so the authored contrast survives; a foreground-only
  // run maps onto a theme token, which adapts to light and dark surfaces.
  Color? foreground = _resolveFg(state.fg, colors, state.bg.isEmpty);
  Color? background = _resolveBg(state.bg);
  if (reverse) {
    final swapped = foreground;
    foreground = background;
    background = swapped;
  }
  final isBold = attrs.contains('1');
  final isItalic = attrs.contains('3');
  final isDim = attrs.contains('2');
  final isHidden = attrs.contains('8');

  if (isDim) {
    // A dim run fades its own color; with none, it fades the color it
    // would have inherited.
    if (foreground != null) {
      foreground = foreground.withValues(alpha: 0.7);
    } else if (defaultColor != null) {
      foreground = defaultColor.withValues(alpha: 0.7);
    }
  }

  if (isHidden) {
    // Visibility hidden: the glyphs vanish, background included.
    return const TextStyle(color: Color(0x00000000));
  }

  TextDecoration? decoration;
  for (final attr in attrs) {
    if (attr == '4') {
      decoration = TextDecoration.underline;
    } else if (attr == '9') {
      decoration = TextDecoration.lineThrough;
    }
  }

  if (foreground == null &&
      background == null &&
      decoration == null &&
      !isBold &&
      !isItalic) {
    return null;
  }
  return TextStyle(
    color: foreground,
    backgroundColor: background,
    fontWeight: isBold ? FontWeight.bold : null,
    fontStyle: isItalic ? FontStyle.italic : null,
    decoration: decoration,
  );
}

/// Parse command output into styled spans grouped by line.
///
/// A `\r` that only terminates a CRLF line end is dropped first, so those
/// lines keep their text instead of being redrawn onto themselves. SGR state
/// threads across lines: a newline does not reset it, so a run opened before
/// a redraw still colors the lines after it.
///
/// - [text]: raw output, which may contain ANSI escape sequences.
/// - [colors]: theme tokens the basic colors map onto; null keeps the literal
///   ANSI palette.
/// - [defaultColor]: the color unstyled text inherits, used to fade a dim run
///   that sets no color of its own.
/// Returns one entry per output line (always at least one, possibly empty).
List<AnsiLine> parseAnsiLines(
  String text, {
  AnsiColors? colors,
  Color? defaultColor,
}) {
  final escaped = text
      .replaceAll(_oscSequence, '')
      .replaceAll(_nonCsiEscape, '');
  final lines = <AnsiLine>[];
  var sgr = _SgrState.none;
  for (final raw in escaped.split('\n')) {
    final line = raw.replaceAll(_trailingCr, '');
    final (runs, exit) = _needsReplay.hasMatch(line)
        ? _replayLine(line, sgr)
        : _scanLine(line, sgr);
    sgr = exit;
    lines.add([
      for (final run in runs)
        AnsiSpan(run.text, _resolveRun(run.sgr, colors, defaultColor)),
    ]);
  }
  return lines;
}

/// Parse [input] into one [TextSpan] tree with the lines joined by newline
/// characters, for callers that render a whole output block in one
/// selectable span. Empty input yields an empty-text span.
TextSpan ansiToSpan(
  String input, {
  AnsiColors? colors,
  Color? defaultColor,
}) {
  final lines = parseAnsiLines(input, colors: colors, defaultColor: defaultColor);
  final parts = <(String, TextStyle?)>[];
  void add(String text, TextStyle? style) {
    if (parts.isNotEmpty) {
      final (lastText, lastStyle) = parts.last;
      if (lastStyle == style) {
        parts[parts.length - 1] = ('$lastText$text', style);
        return;
      }
    }
    parts.add((text, style));
  }

  for (var index = 0; index < lines.length; index++) {
    for (final span in lines[index]) {
      add(span.text, span.style);
    }
    if (index != lines.length - 1) {
      if (parts.isEmpty) {
        parts.add(('\n', null));
      } else {
        final (text, style) = parts.last;
        parts[parts.length - 1] = ('$text\n', style);
      }
    }
  }
  if (parts.isEmpty) {
    return const TextSpan(text: '');
  }
  return TextSpan(
    children: [
      for (final (text, style) in parts) TextSpan(text: text, style: style),
    ],
  );
}
