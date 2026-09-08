/// Session stats line below the composer — Flutter port of React
/// `StatsLine.tsx` (mounted on `conversation.composer.dock`).
///
/// The window fold (`deriveWindowStats`) and token aggregation
/// (`aggregateSessionTokenUsage`) moved verbatim from `chat_view.dart`,
/// where they were computed but never mounted; the per-turn evidence rides
/// `TurnTailNode` (`runMs`, `ttftMs`, `tokenUsage`), mirroring React's
/// fallback fold for assemblies without the durable `sessionStats`
/// projection (which Flutter does not serve — the window fold IS the
/// implementation here, exactly the case React's fallback covers).
///
/// Layout matches the composer card bounds (`Padding(16,0,16,8)` + `Center`
/// + `maxWidth:780`) so the line sits directly under the card it belongs
/// to. Copy is locale-owned (`stats.*` in the `conversation` namespace).
/// Renders nothing while no group has data, like React.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart';
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
    final history = ref.watch(liveHistoryProvider(sessionId));
    final folder = ConversationNodeFolder();
    for (final entry in history) {
      folder.add(SessionEventEnvelope.fromJson(entry.event.toJson()));
    }
    final nodes = folder.snapshot().nodes;
    final stats = deriveWindowStats(nodes);
    final usage = aggregateSessionTokenUsage(
      nodes.whereType<TurnTailNode>().toList(),
    );

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
    if (usage != null &&
        (usage.billedInputTokens > 0 || usage.outputTokens > 0)) {
      final cacheHit = usage.cacheReadTokens == null
          ? null
          : formatCacheHitPercent(
              usage.cacheReadTokens!,
              usage.billedInputTokens,
            );
      if (cacheHit != null) {
        groups.add(_fill(t('stats.cacheHit'), {'percent': cacheHit}));
      }
      groups.add(
        _fill(t('stats.tokens'), {
          'input': formatCompactTokens(usage.billedInputTokens),
          'output': formatCompactTokens(usage.outputTokens),
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
