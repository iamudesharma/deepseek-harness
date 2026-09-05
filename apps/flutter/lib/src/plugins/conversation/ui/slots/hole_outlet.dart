/// HoleOutlet: renders the winning entries of one declared slot key through
/// the hub ledger — the composition primitive hub widgets use instead of
/// importing dependent features directly.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/renderer/slot_outlet.dart' show SlotComponentProps;
import '../../../../core/slots/slot_registry.dart';

/// Renders winners of [slotKey]; renders nothing while undeclared/empty.
class HoleOutlet extends StatelessWidget {
  /// Creates an outlet bound to the hub ledger.
  const HoleOutlet({
    super.key,
    required this.registry,
    required this.slotKey,
    this.fallback,
    this.direction = Axis.vertical,
    this.spacing = 0,
  });

  /// Composition ledger (usually `activatedHub?.slots`).
  final SlotRegistry registry;

  /// Slot key to render.
  final String slotKey;

  /// Shown when nothing occupies the slot.
  final Widget? fallback;

  /// Layout direction for multiple winners. Header rows use
  /// [Axis.horizontal] so list-hole actions sit side-by-side instead of
  /// stacking vertically and overflowing the 44px header (React header
  /// utilities are a horizontal row).
  final Axis direction;

  /// Gap between winners along [direction].
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final winners = registry.winnersOfSlot(slotKey);
    if (winners.isEmpty) {
      return fallback ?? const SizedBox.shrink();
    }
    if (direction == Axis.horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < winners.length; i++) ...[
            if (i > 0 && spacing > 0) SizedBox(width: spacing),
            Flexible(
              fit: FlexFit.loose,
              child: _build(context, winners[i]),
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final entry in winners) _build(context, entry)],
    );
  }

  Widget _build(BuildContext context, SlotEntry entry) {
    assert(
      entry.component is HoleRenderer,
      'slot "$slotKey" entry is not a HoleRenderer',
    );
    return (entry.component as HoleRenderer)(
      context,
      SlotComponentProps(
        slotKey: slotKey,
        priority: entry.priority,
        order: entry.options.order,
        label: entry.options.registrant,
      ),
    );
  }
}

/// The concrete component shape a hole contribution must carry — the same
/// two-argument builder every slot registration carries.
typedef HoleRenderer = Widget Function(
  BuildContext context,
  SlotComponentProps props,
);
