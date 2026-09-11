/// Session stats line below the composer — Flutter port of React
/// `StatsLine.tsx` (mounted on `conversation.composer.dock`).
///
/// Like React, every figure prefers the durable whole-log `sessionStats` /
/// `tokenUsage` projection values (fed into the per-session projection store
/// by `live_sync`), so paging and compaction cannot change them; an assembly
/// without those units falls back to the window-scoped fold wholesale (same
/// field names). The fold rides `TurnTailNode` (`runMs`, `ttftMs`,
/// `tokenUsage`), mirroring React's `deriveStats` fallback.
///
/// Layout matches the composer card bounds (`Padding(16,0,16,8)` + `Center`
/// + `maxWidth:780`) so the line sits directly under the card it belongs
/// to. Copy is locale-owned (`stats.*` in the `conversation` namespace).
/// Renders nothing while no group has data, like React.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart';
import '../../../core/session/projection_store.dart'
    show sessionProjectionStores;
import '../../../core/session/session_event_map.dart';
import '../../../features/conversation/message_provider.dart'
    show liveHistoryProvider;
import '../../../theme/app_theme.dart';
import '../locales.dart' show kConversationNamespace;
import '../nodes/conversation_nodes.dart';
import 'stats_format.dart';

/// Window-scoped display totals (mirrors React `WindowStats`).
class WindowStats {
  /// Creates the totals.
  const WindowStats({
    required this.turns,
    required this.steps,
    required this.llmMs,
    required this.toolMs,
    required this.ttftMs,
    required this.ttftSteps,
    required this.decodeMs,
    required this.decodeTokens,
  });

  /// Distinct turns in the loaded window.
  final int turns;

  /// Settled step groups in the loaded window.
  final int steps;

  /// Summed turn wall time (step/start → assistant/message equivalent).
  final int llmMs;

  /// Summed tool wall time; always 0 (tool durations live in the folder's
  /// private map, as documented at the fold).
  final int toolMs;

  /// Summed first-token latency over [ttftSteps].
  final int ttftMs;

  /// Steps carrying a recorded TTFT.
  final int ttftSteps;

  /// Summed decode wall time over steps that also report output tokens.
  final int decodeMs;

  /// Summed output tokens over the same decode-timed steps.
  final int decodeTokens;
}

/// Fold tail nodes and step groups into window-scoped display totals.
WindowStats deriveWindowStats(List<ConversationNode> nodes) {
  final tails = nodes.whereType<TurnTailNode>().toList();
  final groups = nodes.whereType<StepGroupNode>().toList();
  // Also collect open groups that may have been flattened? groups already cover settled + open before flattening
  final turnSet = <int>{};
  for (final t in tails) turnSet.add(t.turn);
  for (final g in groups) turnSet.add(g.turn);
  // Fallback: if no tails but groups present, turns already counted; if neither, 0
  final turns = turnSet.length;
  final steps = groups.length;
  int llmMs = 0;
  int ttftMs = 0;
  int ttftSteps = 0;
  int decodeMs = 0;
  int decodeTokens = 0;
  for (final t in tails) {
    if (t.runMs != null) llmMs += t.runMs!;
    if (t.ttftMs != null) {
      ttftMs += t.ttftMs!;
      ttftSteps += 1;
    }
    if (t.tokenUsage != null && t.runMs != null && t.ttftMs != null) {
      final dm = (t.runMs! - t.ttftMs!).clamp(0, 1 << 30);
      if (dm > 0) {
        decodeMs += dm;
        decodeTokens += t.tokenUsage!.outputTokens;
      }
    } else if (t.tokenUsage != null && t.tokenUsage!.outputTokens > 0) {
      // Fallback when runMs missing: estimate decode as end - firstToken
      if (t.ttftMs != null && t.runMs != null) {
        final dm = (t.runMs! - t.ttftMs!).clamp(0, 1 << 30);
        if (dm > 0) {
          decodeMs += dm;
          decodeTokens += t.tokenUsage!.outputTokens;
        }
      }
    }
  }
  const toolMs = 0;
  // Tool durations are tracked in the folder's private map; we cannot access it here,
  // so we leave toolMs at 0. The dock still renders counts/speeds/token groups.
  return WindowStats(
    turns: turns,
    steps: steps,
    llmMs: llmMs,
    toolMs: toolMs,
    ttftMs: ttftMs,
    ttftSteps: ttftSteps,
    decodeMs: decodeMs,
    decodeTokens: decodeTokens,
  );
}

/// Aggregate per-turn token accounting across tails with the all-or-nothing
/// bucket rule (a bucket sums only when every tail reports it).
TurnTokenUsage? aggregateSessionTokenUsage(List<TurnTailNode> tails) {
  final withUsage = tails
      .where((t) => t.tokenUsage != null)
      .map((t) => t.tokenUsage!)
      .toList();
  if (withUsage.isEmpty) return null;
  int sumInput = 0;
  int sumOutput = 0;
  int sumTotal = 0;
  int? sumCacheRead;
  int? sumCacheWrite;
  int? sumReasoning;
  bool allCacheRead = withUsage.every((u) => u.cacheReadTokens != null);
  bool allCacheWrite = withUsage.every((u) => u.cacheWriteTokens != null);
  bool allReasoning = withUsage.every((u) => u.reasoningTokens != null);
  bool allRoutes = withUsage.every((u) => u.routes != null);
  final routeUniq = <String, TurnTokenUsageRoute>{};
  for (final u in withUsage) {
    sumInput += u.uncachedInputTokens;
    sumOutput += u.outputTokens;
    sumTotal += u.totalTokens;
    if (sumInput > 9007199254740991 ||
        sumOutput > 9007199254740991 ||
        sumTotal > 9007199254740991)
      return null;
  }
  if (allCacheRead) {
    sumCacheRead = withUsage.fold<int>(0, (s, u) => s + u.cacheReadTokens!);
    if (sumCacheRead > 9007199254740991) return null;
  }
  if (allCacheWrite) {
    sumCacheWrite = withUsage.fold<int>(0, (s, u) => s + u.cacheWriteTokens!);
    if (sumCacheWrite > 9007199254740991) return null;
  }
  if (allReasoning) {
    sumReasoning = withUsage.fold<int>(0, (s, u) => s + u.reasoningTokens!);
    if (sumReasoning > 9007199254740991) return null;
  }
  List<TurnTokenUsageRoute>? aggRoutes;
  if (allRoutes) {
    for (final u in withUsage) {
      for (final r in u.routes!) {
        routeUniq['${r.provider}\u0000${r.model}'] = r;
      }
    }
    aggRoutes = routeUniq.values.toList(growable: false);
  }
  return TurnTokenUsage(
    uncachedInputTokens: sumInput,
    outputTokens: sumOutput,
    totalTokens: sumTotal,
    cacheReadTokens: sumCacheRead,
    cacheWriteTokens: sumCacheWrite,
    reasoningTokens: sumReasoning,
    routes: aggRoutes,
  );
}

/// Whole-log display totals decoded from the `sessionStats` projection.
/// Field names mirror React `WindowStats` so the durable projection and the
/// window fallback swap wholesale.
class SessionStatsTotals {
  /// Creates the totals.
  const SessionStatsTotals({
    required this.turns,
    required this.steps,
    required this.llmMs,
    required this.toolMs,
    required this.ttftMs,
    required this.ttftSteps,
    required this.decodeMs,
    required this.decodeTokens,
  });

  /// Distinct turns with at least one closed step.
  final int turns;

  /// Closed steps.
  final int steps;

  /// Summed model wall time, ms.
  final int llmMs;

  /// Summed matched tool wall time, ms.
  final int toolMs;

  /// Summed first-token latency, ms.
  final int ttftMs;

  /// Steps carrying a recorded first token.
  final int ttftSteps;

  /// Summed decode wall time, ms.
  final int decodeMs;

  /// Summed output tokens over decode-timed steps.
  final int decodeTokens;

  /// Decodes a Host `sessionStats` projection value; null when absent or
  /// malformed (the caller falls back to the window fold).
  static SessionStatsTotals? tryFromJson(Object? value) {
    if (value is! Map) return null;
    int? n(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
    final turns = n(value['turns']);
    final steps = n(value['steps']);
    final llmMs = n(value['llmMs']);
    final toolMs = n(value['toolMs']);
    final ttftMs = n(value['ttftMs']);
    final ttftSteps = n(value['ttftSteps']);
    final decodeMs = n(value['decodeMs']);
    final decodeTokens = n(value['decodeTokens']);
    if (turns == null ||
        steps == null ||
        llmMs == null ||
        toolMs == null ||
        ttftMs == null ||
        ttftSteps == null ||
        decodeMs == null ||
        decodeTokens == null) {
      return null;
    }
    return SessionStatsTotals(
      turns: turns,
      steps: steps,
      llmMs: llmMs,
      toolMs: toolMs,
      ttftMs: ttftMs,
      ttftSteps: ttftSteps,
      decodeMs: decodeMs,
      decodeTokens: decodeTokens,
    );
  }
}

/// Durable cumulative provider usage decoded from the `tokenUsage`
/// projection. Mirrors `TokenUsageProjection`: four disjoint buckets
/// (reasoning already inside output). Cache buckets stay nullable so the
/// fallback fold's partial reporting keeps the line's billing gate intact.
class SessionTokenUsage {
  /// Creates the usage value.
  const SessionTokenUsage({
    required this.uncachedInputTokens,
    required this.outputTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
  });

  /// Uncached prompt tokens.
  final int uncachedInputTokens;

  /// Output tokens (reasoning included).
  final int outputTokens;

  /// Cache-read tokens, when reported.
  final int? cacheReadTokens;

  /// Cache-write tokens, when reported.
  final int? cacheWriteTokens;

  /// Decodes a Host `tokenUsage` projection value; null when absent.
  static SessionTokenUsage? tryFromJson(Object? value) {
    if (value is! Map) return null;
    int? n(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
    final uncached = n(value['uncachedInputTokens']);
    final output = n(value['outputTokens']);
    if (uncached == null || output == null) return null;
    return SessionTokenUsage(
      uncachedInputTokens: uncached,
      outputTokens: output,
      cacheReadTokens: n(value['cacheReadTokens']),
      cacheWriteTokens: n(value['cacheWriteTokens']),
    );
  }

  /// Sum of the prompt-side billing buckets (React `billedInputTokens`).
  int get billedInputTokens =>
      uncachedInputTokens +
      (cacheReadTokens ?? 0) +
      (cacheWriteTokens ?? 0);

  /// Gated on actual token activity (React `hasTokens`).
  bool get hasTokens => billedInputTokens > 0 || outputTokens > 0;

  /// Display-ready cache-hit share, or null with no billed input.
  String? cacheHitPercent() {
    if (cacheReadTokens == null) return null;
    return formatCacheHitPercent(cacheReadTokens!, billedInputTokens);
  }
}

/// Fill a `{name}` template (the `Translate` face takes bare keys only).
String _fill(String template, Map<String, String> values) {
  var out = template;
  values.forEach((key, value) {
    out = out.replaceAll('{$key}', value);
  });
  return out;
}

/// Session stats line for one session, mounted below the composer.
class SessionStatsLine extends ConsumerWidget {
  /// Creates the line.
  const SessionStatsLine({super.key, required this.sessionId});

  /// Owning session id.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // React `useProjection('sessionStats')` / `useProjection('tokenUsage')`:
    // every figure rides the durable whole-log projections so paging and
    // compaction cannot change them; an assembly without those units pays for
    // the window fold wholesale (same field names).
    final store = ref.watch(sessionProjectionStores(sessionId));
    final projected = SessionStatsTotals.tryFromJson(
      store.valueOf('sessionStats'),
    );
    final usage = SessionTokenUsage.tryFromJson(store.valueOf('tokenUsage'));

    SessionStatsTotals stats;
    SessionTokenUsage? tokens = usage;
    if (projected != null) {
      stats = projected;
    } else {
      final history = ref.watch(liveHistoryProvider(sessionId));
      final folder = ConversationNodeFolder();
      for (final entry in history) {
        folder.add(SessionEventEnvelope.fromJson(entry.event.toJson()));
      }
      final nodes = folder.snapshot().nodes;
      final window = deriveWindowStats(nodes);
      stats = SessionStatsTotals(
        turns: window.turns,
        steps: window.steps,
        llmMs: window.llmMs,
        toolMs: window.toolMs,
        ttftMs: window.ttftMs,
        ttftSteps: window.ttftSteps,
        decodeMs: window.decodeMs,
        decodeTokens: window.decodeTokens,
      );
      if (tokens == null) {
        final agg = aggregateSessionTokenUsage(
          nodes.whereType<TurnTailNode>().toList(),
        );
        if (agg != null) {
          tokens = SessionTokenUsage(
            uncachedInputTokens: agg.uncachedInputTokens,
            outputTokens: agg.outputTokens,
            cacheReadTokens: agg.cacheReadTokens,
            cacheWriteTokens: agg.cacheWriteTokens,
          );
        }
      }
    }

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kConversationNamespace);

    final groups = <String>[];
    if (stats.steps > 0) {
      groups.add(
        _fill(t('stats.counts'), {
          'turns': '${stats.turns}',
          'steps': '${stats.steps}',
        }),
      );
      final durations = <String>[];
      if (stats.llmMs > 0) {
        durations.add(
          _fill(t('stats.llm'), {
            'duration': formatCompactDuration(stats.llmMs),
          }),
        );
      }
      if (stats.toolMs > 0) {
        durations.add(
          _fill(t('stats.toolCall'), {
            'duration': formatCompactDuration(stats.toolMs),
          }),
        );
      }
      if (durations.isNotEmpty) groups.add(durations.join(' · '));
      final speeds = <String>[];
      if (stats.ttftSteps > 0) {
        final avg = (stats.ttftMs / stats.ttftSteps).round();
        speeds.add(
          _fill(t('stats.ttftAverage'), {
            'duration': formatCompactDuration(avg),
          }),
        );
      }
      if (stats.decodeMs > 0) {
        final tps = stats.decodeTokens / (stats.decodeMs / 1000);
        speeds.add(
          _fill(t('stats.tokensPerSecond'), {
            'throughput': formatTokensPerSecond(tps),
          }),
        );
      }
      if (speeds.isNotEmpty) groups.add(speeds.join(' · '));
    }
    if (tokens != null &&
        (tokens.billedInputTokens > 0 || tokens.outputTokens > 0)) {
      final cacheHit = tokens.cacheHitPercent();
      if (cacheHit != null) {
        groups.add(_fill(t('stats.cacheHit'), {'percent': cacheHit}));
      }
      groups.add(
        _fill(t('stats.tokens'), {
          'input': formatCompactTokens(tokens.billedInputTokens),
          'output': formatCompactTokens(tokens.outputTokens),
        }),
      );
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Text(
            groups.join(' | '),
            style: TextStyle(
              fontSize: 13,
              color: aliases.labelTertiary,
              height: 20 / 13,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
