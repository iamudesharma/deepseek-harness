import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/projection_store.dart';
import '../../../theme/app_theme.dart';

/// Minimal port of `ContextMeter` (`ui-conversation/src/client/skeleton/ContextMeter.tsx`).
///
/// Reads `contextPressure` + `contextBreakdown` projections via
/// `sessionProjectionStores` and renders the 14px occupancy ring with a
/// click-to-open panel (simplified: shows `~used / capacity` header and a
/// segmented bar). The two vocabularies — provider-exact `projectedTokens`
/// vs heuristic breakdown — are never reconciled, mirroring the React decision.
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
    final int? projected = pMap['projectedTokens'] as int? ?? pMap['pressureTokens'] as int?;
    final int? window = pMap['contextWindow'] as int?;
    if (projected == null || window == null || window == 0) {
      return const SizedBox.shrink();
    }
    final double ratio = (projected / window).clamp(0, 1).toDouble();
    final int percent = (ratio * 100).round();
    final theme = Theme.of(context);
    final aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    return _RingWithPanel(
      percent: percent,
      projected: projected,
      window: window,
      breakdown: breakdown is Map ? breakdown.cast<String, dynamic>() : null,
      aliases: aliases,
    );
  }
}

class _RingWithPanel extends StatefulWidget {
  const _RingWithPanel({
    required this.percent,
    required this.projected,
    required this.window,
    required this.breakdown,
    required this.aliases,
  });
  final int percent;
  final int projected;
  final int window;
  final Map<String, dynamic>? breakdown;
  final DswAliases aliases;
  @override
  State<_RingWithPanel> createState() => _RingWithPanelState();
}

class _RingWithPanelState extends State<_RingWithPanel> {
  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  void _showPanel() {
    final bd = widget.breakdown;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('~${_fmt(widget.projected)} / ${_fmt(widget.window)} (${widget.percent}%)'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Segmented bar (simplified: single color)
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: widget.aliases.borderL2,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widget.percent / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.aliases.stateBusinessPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (bd != null) ...[
                _row('~System', bd['systemTokens'] as int? ?? 0),
                _row('~Tools', bd['toolsTokens'] as int? ?? 0),
                _row('~Messages', bd['messageTokens'] as int? ?? 0),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _row(String label, int tokens) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: widget.aliases.labelTertiary)),
            Text('~${_fmt(tokens)}', style: TextStyle(fontSize: 12, color: widget.aliases.labelSecondary)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _showPanel,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                value: widget.percent / 100,
                strokeWidth: 2,
                backgroundColor: widget.aliases.borderL2,
                valueColor: AlwaysStoppedAnimation(widget.aliases.stateBusinessPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
