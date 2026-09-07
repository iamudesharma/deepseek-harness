/// Trigger detection pure core — Dart port of
/// `packages/client/ui-input-trigger/src/core/detect.ts` plus the shared
/// `@` grammar (`dsh-file-reference/grammar.ts:activeAtToken`). Scans backward
/// from the caret for a live trigger char under the guard tier and applies the
/// word-boundary rules. Zero Flutter.
library;

import 'menu_reducer.dart' show TokenSpan, TriggerHit;
import 'trigger_source.dart';

final RegExp _wordChar = RegExp(r'[0-9A-Za-z_]', unicode: true);
final RegExp _whitespace = RegExp(r'\s');

/// Active `@` token ending at the cursor (the shared file-reference grammar).
class ActiveAtToken {
  /// Creates a token.
  const ActiveAtToken({
    required this.prefix,
    required this.query,
    required this.quoted,
  });

  /// Complete token replaced when the user accepts a completion.
  final String prefix;

  /// Path query after `@` or `@"`.
  final String query;

  /// Whether the user opened a quoted path.
  final bool quoted;
}

/// Extract an `@path` or `@"path with spaces` token at [caretCol]. An `@`
/// inside another token, such as an email address, is not a completion trigger.
ActiveAtToken? activeAtToken(String line, int caretCol) {
  final before = line.substring(0, caretCol);
  final quoted = RegExp(
    r'(?:^|\s)(@"([^"]*))$',
    unicode: true,
  ).firstMatch(before);
  if (quoted != null && quoted.group(2) != null) {
    return ActiveAtToken(
      prefix: quoted.group(1)!,
      query: quoted.group(2)!,
      quoted: true,
    );
  }
  final plain = RegExp(r'(?:^|\s)(@(\S*))$').firstMatch(before);
  if (plain == null || plain.group(2) == null) return null;
  return ActiveAtToken(
    prefix: plain.group(1)!,
    query: plain.group(2)!,
    quoted: false,
  );
}

/// Word-boundary rule: a trigger char opens only at start-of-draft, after
/// whitespace (newlines included), or after punctuation. Two URL carve-outs
/// keep '/' dead inside URLs (both pinned by tests): '/' after a ':' that
/// itself follows a non-whitespace char (scheme separator, `https:/…`), and
/// '/' directly after another '/' (second slash of `//`).
bool boundaryOk(String draft, int index, TriggerChar char) {
  if (index == 0) return true;
  final prev = draft[index - 1];
  if (_whitespace.hasMatch(prev)) return true;
  if (_wordChar.hasMatch(prev)) return false;
  if (char == '/') {
    if (prev == '/') return false;
    if (prev == ':' && index >= 2 && !_whitespace.hasMatch(draft[index - 2])) {
      return false;
    }
  }
  return true;
}

/// Detect a trigger token at the caret. `@` first uses the shared grammar,
/// including an open quoted token that may span whitespace. Slash detection
/// scans left to the first whitespace; slashes failing the word boundary are
/// treated as ordinary token chars and the scan continues (URL slashes).
/// Guard tiers: plain = both chars live; claimed = `'/'` fully suppressed,
/// `'@'` live; frozen = none.
///
/// Returns the hit with `query` = trigger-to-caret slice and `span` =
/// `{start: triggerIndex, end: caret, draftRev: 0}` — the calling shell stamps
/// the real revision. Null when no trigger is live at the caret.
TriggerHit? detectTrigger(String draft, int caret, TriggerGuard guard) {
  if (guard.tier == TriggerGuardTier.frozen) return null;
  final at = activeAtToken(draft, caret);
  if (at != null) {
    final start = caret - at.prefix.length;
    return TriggerHit(
      trigger: '@',
      query: at.query,
      quoted: at.quoted,
      position: _positionOf(draft, start),
      span: TokenSpan(start: start, end: caret, draftRev: 0),
    );
  }
  for (var i = caret - 1; i >= 0; i--) {
    final ch = draft[i];
    if (_whitespace.hasMatch(ch)) return null;
    if (ch != '/') continue;
    if (guard.tier == TriggerGuardTier.claimed) continue;
    if (!boundaryOk(draft, i, ch)) continue;
    final query = draft.substring(i + 1, caret);
    if (query.contains('/')) continue;
    return TriggerHit(
      trigger: ch,
      query: query,
      quoted: false,
      position: _positionOf(draft, i),
      span: TokenSpan(start: i, end: caret, draftRev: 0),
    );
  }
  return null;
}

TriggerPosition _positionOf(String draft, int start) {
  for (var i = 0; i < draft.length; i++) {
    if (!_whitespace.hasMatch(draft[i])) {
      return i == start ? TriggerPosition.leading : TriggerPosition.inline;
    }
  }
  return TriggerPosition.inline;
}
