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
  });

  /// Composition ledger (usually `activatedHub?.slots`).
  final SlotRegistry registry;

  /// Slot key to render.
  final String slotKey;

  /// Shown when nothing occupies the slot.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final winners = registry.winnersOfSlot(slotKey);
    if (winners.isEmpty) {
      return fallback ?? const SizedBox.shrink();
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
