import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/projection_store.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart' show kConversationNamespace;
import 'stats_format.dart' show formatCompactTokens;

/// Context-occupancy meter — Flutter port of `ContextMeter`
/// (`ui-conversation/src/client/skeleton/ContextMeter.tsx`).
///
/// A 28px trigger beside the send button fed by the `contextPressure`
/// projection, with a click-open panel of the heuristic `contextBreakdown`
/// composition (system prompt, tools, conversation). Renders nothing until a
/// provider reports both pressure and a route capacity. The two vocabularies
/// — provider-exact `projectedTokens` vs heuristic breakdown — are never
/// reconciled, mirroring the React decision.
///
/// The panel renders as a dialog (the anchored popover's dismiss/outside-tap
/// contract maps to barrier dismiss); bar segments, legend rows, and copy
/// follow the React panel.
class ContextMeter extends ConsumerWidget {
  const ContextMeter({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(sessionProjectionStores(sessionId));
    final pressure = store.valueOf('contextPressure');
    final breakdown = store.valueOf('contextBreakdown');
    if (pressure is! Map) return const SizedBox.shrink();
    final pMap = pressure.cast<String, dynamic>();
    // React `contextOccupancy`: projectedTokens ?? pressureTokens over
    // contextWindow; null until numerator and capacity are known.
    final int? used =
        pMap['projectedTokens'] as int? ?? pMap['pressureTokens'] as int?;
    final int? window = pMap['contextWindow'] as int?;
    if (used == null || window == null || window == 0) {
      return const SizedBox.shrink();
    }
    final int percent = math.min(100, (used / window * 100).round());
    final theme = Theme.of(context);
    final aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kConversationNamespace);
    final reading = '$percent%';
    // The localized occupancy sentence splits around the reading so the
    // panel headline keeps the reading in its own tone while each locale
    // owns word order (`45% of context used` / `上下文已用 45%`,
    // React READING_SLOT).
    final template = t('context.aria');
    final mark = template.indexOf('{percent}');
    final headBefore = (mark < 0 ? '' : template.substring(0, mark)).trim();
    final headAfter =
        (mark < 0 ? template : template.substring(mark + '{percent}'.length))
            .trim();
    return _RingWithPanel(
      percent: percent,
      used: used,
      window: window,
      breakdown: breakdown is Map ? breakdown.cast<String, dynamic>() : null,
      aliases: aliases,
      ariaLabel: t('context.aria').replaceAll('{percent}', reading),
      headlineBefore: headBefore,
      headlineAfter: headAfter,
      figures: '~${formatCompactTokens(used)} / ${formatCompactTokens(window)}',
      systemLabel: t('context.system'),
      toolsLabel: t('context.tools'),
      messagesLabel: t('context.messages'),
    );
  }
}

class _RingWithPanel extends StatefulWidget {
  const _RingWithPanel({
    required this.percent,
    required this.used,
    required this.window,
    required this.breakdown,
    required this.aliases,
    required this.ariaLabel,
    required this.headlineBefore,
    required this.headlineAfter,
    required this.figures,
    required this.systemLabel,
    required this.toolsLabel,
    required this.messagesLabel,
  });
  final int percent;
  final int used;
  final int window;
  final Map<String, dynamic>? breakdown;
  final DswAliases aliases;
  final String ariaLabel;
  final String headlineBefore;
  final String headlineAfter;
  final String figures;
  final String systemLabel;
  final String toolsLabel;
  final String messagesLabel;

  @override
  State<_RingWithPanel> createState() => _RingWithPanelState();
}

class _RingWithPanelState extends State<_RingWithPanel> {
  void _showPanel() {
    final bd = widget.breakdown;
    final int total = bd == null
        ? 0
        : (bd['systemTokens'] as int? ?? 0) +
              (bd['toolsTokens'] as int? ?? 0) +
              (bd['messageTokens'] as int? ?? 0);
    // The bar's overall length stays the provider-exact percent; the
    // heuristic breakdown only proportions its colored parts. Zero-width
    // parts are dropped (React segments filter).
    final segments = bd == null || total == 0
        ? [
            _Segment(
              width: widget.percent.toDouble(),
              color: widget.aliases.labelTertiary,
            ),
          ]
        : [
            _Segment(
              width: widget.percent * (bd['systemTokens'] as int? ?? 0) / total,
              color: DswTokens.neutralBluish400,
            ),
            _Segment(
              width: widget.percent * (bd['toolsTokens'] as int? ?? 0) / total,
              color: DswTokens.meterToolsViolet,
            ),
            _Segment(
              width:
                  widget.percent * (bd['messageTokens'] as int? ?? 0) / total,
              color: DswTokens.blue450,
            ),
          ].where((s) => s.width > 0).toList();
    // The headline brackets the reading; a locale side left empty drops out
    // (React `.headline:empty`).
    final heads = [
      widget.headlineBefore,
      widget.headlineAfter,
    ].where((p) => p.isNotEmpty).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.aliases.specificMenu,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
          side: BorderSide(color: widget.aliases.borderL1),
        ),
        content: SizedBox(
          width: 264 - 48,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (heads.isNotEmpty) ...[
                    // Flexible + ellipsis: production copy always fits;
                    // pathological fonts (test Ahem) ellipsize instead of
                    // overflowing the fixed 264px panel.
                    Flexible(
                      child: Text(
                        heads.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          height: 20 / 12,
                          color: widget.aliases.labelTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '${widget.percent}%',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      height: 20 / 12,
                      fontWeight: FontWeight.w500,
                      color: widget.aliases.labelPrimary,
                    ),
                  ),
                  if (heads.length > 1) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        heads[1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          height: 20 / 12,
                          color: widget.aliases.labelTertiary,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Flexible(
                    child: Text(
                      widget.figures,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        height: 20 / 12,
                        fontWeight: FontWeight.w500,
                        color: widget.aliases.labelPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Segmented bar: 4px track, 1px gaps, min 2px segments.
              SizedBox(
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    children: [
                      for (int i = 0; i < segments.length; i++) ...[
                        if (i > 0) const SizedBox(width: 1),
                        Flexible(
                          flex: (segments[i].width * 100).round().clamp(
                            1,
                            10000,
                          ),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 2),
                            decoration: BoxDecoration(
                              color: segments[i].color,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (bd != null) ...[
                const SizedBox(height: 12),
                _LegendRow(
                  swatch: DswTokens.neutralBluish400,
                  label: widget.systemLabel,
                  value:
                      '~${formatCompactTokens(bd['systemTokens'] as int? ?? 0)}',
                  aliases: widget.aliases,
                ),
                _LegendRow(
                  swatch: DswTokens.meterToolsViolet,
                  label: widget.toolsLabel,
                  value:
                      '~${formatCompactTokens(bd['toolsTokens'] as int? ?? 0)}',
                  aliases: widget.aliases,
                ),
                _LegendRow(
                  swatch: DswTokens.blue450,
                  label: widget.messagesLabel,
                  value:
                      '~${formatCompactTokens(bd['messageTokens'] as int? ?? 0)}',
                  aliases: widget.aliases,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // React `.trigger`: 28px circle hit target, transparent, hover tint.
    return Tooltip(
      message: widget.ariaLabel,
      preferBelow: false,
      child: Semantics(
        button: true,
        label: widget.ariaLabel,
        child: InkWell(
          onTap: _showPanel,
          borderRadius: BorderRadius.circular(999),
          hoverColor: widget.aliases.interactiveBgHover,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CustomPaint(
                  painter: _MeterRingPainter(
                    fraction: widget.percent / 100,
                    track: widget.aliases.borderL3,
                    fill: widget.aliases.labelTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment {
  const _Segment({required this.width, required this.color});
  final double width;
  final Color color;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.swatch,
    required this.label,
    required this.value,
    required this.aliases,
  });
  final Color swatch;
  final String label;
  final String value;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: 20 / 12,
                color: aliases.labelSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              height: 20 / 12,
              color: aliases.labelPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 14px occupancy ring: L3 track + tertiary fill arc from the top with round
/// caps (React `.track` / `.fill`, r=5.5, 2px stroke).
class _MeterRingPainter extends CustomPainter {
  _MeterRingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });
  final double fraction;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MeterRingPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}
