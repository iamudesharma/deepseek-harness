/// Turn token usage disclosure — mirrors TurnUsageDisclosure.tsx + token-format.ts
///
/// Shows "Turn usage · 12.4K tok" collapsed row that expands to per-route
/// breakdown (uncached input, output, total, cacheRead/Write, reasoning, routes).
/// Derived only when loaded window includes turn/start and every attempt reports
/// safe exact usage; otherwise disclosure hidden (no partial total).
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/disclosure_row.dart';

class TurnTokenUsage {
  const TurnTokenUsage({
    required this.uncachedInputTokens,
    required this.outputTokens,
    required this.totalTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.reasoningTokens,
    this.routes,
  });

  final int uncachedInputTokens;
  final int outputTokens;
  final int totalTokens;
  final int? cacheReadTokens;
  final int? cacheWriteTokens;
  final int? reasoningTokens;
  final List<TurnTokenRoute>? routes;
}

class TurnTokenRoute {
  const TurnTokenRoute({required this.provider, required this.model});
  final String provider;
  final String model;
}

String _formatTokens(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

class TurnUsageDisclosure extends StatefulWidget {
  const TurnUsageDisclosure({super.key, required this.usage});

  final TurnTokenUsage usage;

  @override
  State<TurnUsageDisclosure> createState() => _TurnUsageDisclosureState();
}

class _TurnUsageDisclosureState extends State<TurnUsageDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final summary = 'Turn usage · ${_formatTokens(widget.usage.totalTokens)} tok';
    return DisclosureRow(
      icon: Icon(Icons.data_usage_rounded, size: 14, color: aliases.labelTertiary),
      title: summary,
      open: _open,
      expandable: true,
      expandOnRowClick: true,
      onToggle: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Uncached input', widget.usage.uncachedInputTokens, aliases),
            _row('Output', widget.usage.outputTokens, aliases),
            if (widget.usage.cacheReadTokens != null) _row('Cache read', widget.usage.cacheReadTokens!, aliases),
            if (widget.usage.cacheWriteTokens != null) _row('Cache write', widget.usage.cacheWriteTokens!, aliases),
            if (widget.usage.reasoningTokens != null) _row('Reasoning', widget.usage.reasoningTokens!, aliases),
            if (widget.usage.routes != null && widget.usage.routes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Routes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: aliases.labelTertiary)),
              for (final r in widget.usage.routes!) Text('${r.provider}/${r.model}', style: TextStyle(fontSize: 11, color: aliases.labelSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int value, DswAliases aliases) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: aliases.labelTertiary))),
          Text(_formatTokens(value), style: TextStyle(fontSize: 11, color: aliases.labelSecondary)),
        ],
      ),
    );
  }
}

/// Footer stats line — mirrors StatsLine.tsx
/// "7 turns · 7 steps | LLM 35.2s | TTFT avg 5.1s · 61 tok/s | Cache hit 67% | Input 79K tok · Output 275"
class StatsLine extends StatelessWidget {
  const StatsLine({
    super.key,
    required this.turns,
    required this.steps,
    this.llmSeconds,
    this.ttftAvg,
    this.tokensPerSec,
    this.cacheHitPct,
    this.inputTokens,
    this.outputTokens,
  });

  final int turns;
  final int steps;
  final double? llmSeconds;
  final double? ttftAvg;
  final double? tokensPerSec;
  final int? cacheHitPct;
  final int? inputTokens;
  final int? outputTokens;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final parts = <String>[
      '$turns turns · $steps steps',
      if (llmSeconds != null) 'LLM ${llmSeconds!.toStringAsFixed(1)}s',
      if (ttftAvg != null) 'TTFT avg ${ttftAvg!.toStringAsFixed(1)}s${tokensPerSec != null ? ' · ${tokensPerSec!.toStringAsFixed(0)} tok/s' : ''}',
      if (cacheHitPct != null) 'Cache hit $cacheHitPct%',
      if (inputTokens != null || outputTokens != null)
        'Input ${inputTokens != null ? _formatTokens(inputTokens!) : '-'} tok · Output ${outputTokens != null ? _formatTokens(outputTokens!) : '-'} tok',
    ];
    return Text(
      parts.join('  |  '),
      style: TextStyle(fontSize: 11, color: aliases.labelTertiary),
      overflow: TextOverflow.ellipsis,
    );
  }
}
