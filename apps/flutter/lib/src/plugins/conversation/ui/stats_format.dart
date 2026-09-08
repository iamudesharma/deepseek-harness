/// Compact token/latency formatters shared by the per-turn footers and the
/// session stats line — mirrors `token-format.ts` + `message-chrome.ts`.
/// Moved verbatim from `chat_view.dart` so both surfaces render identical
/// text without duplicating the rounding rules.
library;

/// Compact token count: `999`, `40.1K`, `1.2M`.
String formatCompactTokens(int value) {
  String scaled(double candidate) {
    if (candidate >= 100) return candidate.round().toString();
    final r = (candidate * 10).round() / 10;
    if (r == r.roundToDouble()) return r.round().toString();
    return r.toStringAsFixed(1);
  }

  if (value < 1000) return value.toString();
  if (value < 1000000) return '${scaled(value / 1000)}K';
  return '${scaled(value / 1000000)}M';
}

/// Exact token count with thousands separators: `79,412`.
String formatExactTokens(int value) {
  final digits = value.toString();
  final groups = <String>[];
  for (int end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, digits.length);
    groups.insert(0, digits.substring(start, end));
  }
  return groups.join(',');
}

int _roundedPercentUnits(
  int cacheReadTokens,
  int denominator,
  int decimalPlaces,
) {
  final unitsPerPercent = decimalPlaces == 0 ? 1 : 10;
  final scale = unitsPerPercent * 100;
  final doubledScale = scale * 2;
  final denominatorQuotient = denominator ~/ doubledScale;
  final denominatorRemainder = denominator % doubledScale;
  int lower = 0;
  int upper = scale;
  while (lower < upper) {
    final candidate = (lower + upper + 1) ~/ 2;
    final factor = candidate * 2 - 1;
    final threshold =
        factor * denominatorQuotient +
        ((factor * denominatorRemainder + doubledScale - 1) ~/ doubledScale);
    if (cacheReadTokens >= threshold) {
      lower = candidate;
    } else {
      upper = candidate - 1;
    }
  }
  return lower;
}

String _displayPercentUnits(int units, int decimalPlaces) {
  if (decimalPlaces == 0) return units.toString();
  final whole = units ~/ 10;
  final tenths = units % 10;
  return tenths == 0 ? whole.toString() : '$whole.$tenths';
}

/// Cache-hit share text (`67`, `99.9`, `100`) or null when [promptTokens]
/// is zero. Rounds below 100 unless the hit is complete.
String? formatCacheHitPercent(
  int cacheReadTokens,
  int promptTokens, [
  int decimalPlaces = 0,
]) {
  if (promptTokens == 0) return null;
  final missed = promptTokens - cacheReadTokens;
  if (missed == 0) return '100';
  final roundedUnits = _roundedPercentUnits(
    cacheReadTokens,
    promptTokens,
    decimalPlaces,
  );
  final fullHitUnits = decimalPlaces == 0 ? 100 : 1000;
  if (roundedUnits < fullHitUnits)
    return _displayPercentUnits(roundedUnits, decimalPlaces);
  int distinguishingPlaces = 1;
  int scaledDoubleGap = missed * 200;
  final denominatorTens = promptTokens ~/ 10;
  while (scaledDoubleGap <= denominatorTens) {
    scaledDoubleGap *= 10;
    distinguishingPlaces += 1;
  }
  final denominatorOnes = promptTokens % 10;
  int roundedLoss = 5;
  for (int loss = 1; loss < 5; loss += 1) {
    final factor = loss * 2 + 1;
    final threshold =
        factor * denominatorTens + (factor * denominatorOnes ~/ 10);
    if (scaledDoubleGap <= threshold) {
      roundedLoss = loss;
      break;
    }
  }
  return '99.${'9' * (distinguishingPlaces - 1)}${10 - roundedLoss}';
}

/// Throughput text: `61` at/above 10, else one decimal (`5.1`).
String formatTokensPerSecond(double tps) {
  final clamped = tps < 0 ? 0.0 : tps;
  if (clamped >= 10) return clamped.round().toString();
  final r = (clamped * 10).round() / 10;
  if (r == r.roundToDouble()) return r.round().toString();
  return r.toStringAsFixed(1);
}

/// Compact duration: `35.2s` under a minute, `2m42s` from there on.
String formatCompactDuration(int ms) {
  final s = ms / 1000;
  if (s < 60) {
    final r = (s * 10).round() / 10;
    final secStr = r == r.roundToDouble()
        ? r.round().toString()
        : r.toStringAsFixed(1);
    return '${secStr}s';
  }
  final whole = s.round();
  final minutes = whole ~/ 60;
  final seconds = whole % 60;
  return '${minutes}m${seconds}s';
}
