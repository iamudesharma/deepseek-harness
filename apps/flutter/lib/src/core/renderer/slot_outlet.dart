/// Render machinery binding the slot ledger to Flutter, mirroring the role of
/// `packages/client/ui-renderer` on the React side: slot outlets resolve
/// winner entries into widgets, and version subscription is the uSES analog
/// that re-renders when the ledger mutates.
///
/// Components contributed through [SlotRegistry.register] are opaque objects
/// at the ledger level; this layer defines the concrete widget-builder shape
/// and casts. Business widgets receive everything through [SlotComponentProps]
/// — no registry or context reach-through, matching the React four-shares
/// discipline at its narrowest.
library;

import 'package:flutter/widgets.dart';

import 'package:dsh_flutter/src/core/slots/slot_registry.dart';

/// The concrete component shape a slot entry must carry to render.
typedef SlotWidgetBuilder = Widget Function(
  BuildContext context,
  SlotComponentProps props,
);

/// What an outlet hands a rendered entry: identity of the cell it won plus
/// the declaring options' display metadata.
@immutable
class SlotComponentProps {
  /// Creates the props for one rendered entry.
  const SlotComponentProps({
    required this.slotKey,
    this.cellKey,
    this.cellId,
    required this.priority,
    this.order,
    this.label,
  });

  /// The slot key being rendered.
  final String slotKey;

  /// Won cell key (keyed slots).
  final String? cellKey;

  /// Won cell id (list slots).
  final String? cellId;

  /// Winning priority.
  final int priority;

  /// List display order refinement.
  final int? order;

  /// Display label when the registration supplied one.
  final String? label;
}

Widget _defaultFallback(BuildContext context) => const SizedBox.shrink();

/// Renders every winning cell of one slot in shadowing order.
///
/// Undeclared or unoccupied slots render [fallback]; probing ahead of plugin
/// load order is therefore safe, mirroring `entries()` returning empty.
class SlotOutlet extends StatelessWidget {
  /// Creates an outlet for one slot key.
  const SlotOutlet({
    super.key,
    required this.registry,
    required this.slotKey,
    this.fallback,
    this.builder,
  });

  /// The composition ledger.
  final SlotRegistry registry;

  /// Slot key to render.
  final String slotKey;

  /// Shown while nothing occupies the slot.
  final WidgetBuilder? fallback;

  /// Optional wrapper around each rendered entry (chain/list decoration).
  final Widget Function(BuildContext context, Widget child, SlotEntry entry)?
  builder;

  @override
  Widget build(BuildContext context) {
    final winners = registry.winnersOfSlot(slotKey);
    if (winners.isEmpty) {
      return fallback?.call(context) ?? _defaultFallback(context);
    }
    // A single winning cell renders bare so slot occupants see exactly the
    // constraints their container provides (root must fill the viewport).
    if (winners.length == 1) {
      return _buildEntry(context, winners.single);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final entry in winners) _buildEntry(context, entry)],
    );
  }

  Widget _buildEntry(BuildContext context, SlotEntry entry) {
    assert(
      entry.component is SlotWidgetBuilder,
      'slot "$slotKey" entry from "${entry.options.registrant ?? '<unknown>'}" '
      'is not a SlotWidgetBuilder — the render layer cannot cast it',
    );
    final build = entry.component as SlotWidgetBuilder;
    final specKind = registry.specOf(slotKey)?.kind;
    final child = build(
      context,
      SlotComponentProps(
        slotKey: slotKey,
        cellKey: specKind == SlotKind.keyed ? entry.options.key : null,
        cellId: specKind == SlotKind.list ? entry.options.id : null,
        priority: entry.priority,
        order: entry.options.order,
      ),
    );
    return builder?.call(context, child, entry) ?? child;
  }
}

/// Rebuilds [builder] whenever any ledger mutation bumps [SlotRegistry.version].
///
/// This is the single subscription seat business code gets — the analog of the
/// renderer-bound `useSyncExternalStore` adapter; feature code never subscribes
/// manually.
class SlotVersionBuilder extends StatefulWidget {
  /// Creates a rebuild-on-ledger-change scope.
  const SlotVersionBuilder({
    super.key,
    required this.registry,
    required this.builder,
  });

  /// The composition ledger.
  final SlotRegistry registry;

  /// Built with the current version; re-invoked after each mutation.
  final Widget Function(BuildContext context, int version) builder;

  @override
  State<SlotVersionBuilder> createState() => _SlotVersionBuilderState();
}

class _SlotVersionBuilderState extends State<SlotVersionBuilder> {
  late Disposer _disposer;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _disposer = widget.registry.onChanged((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SlotVersionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.registry, widget.registry)) {
      _disposer();
      _subscribe();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.registry.version);
}
