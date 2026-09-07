import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'input_trigger_provider.dart';

/// Inline trigger menu view — popup list anchored to the composer.
///
/// Mirrors web `PopupSelectView` / `TriggerMenu` in `ui-input-trigger`.
/// Owner-controlled via [items] + [selectedIndex]; renders a token-styled
/// card with hover/selected states. Pure build, no `ctx`.
class TriggerMenuView extends ConsumerWidget {
  /// Creates the trigger menu view.
  const TriggerMenuView({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.onHover,
    this.emptyLabel = 'No matches',
  });

  /// Filtered suggestions to show.
  final List<TriggerItem> items;

  /// Currently focused index — -1 means none.
  final int selectedIndex;

  /// Called when an item is chosen.
  final ValueChanged<TriggerItem> onSelect;

  /// Called on hover / keyboard focus move.
  final ValueChanged<int>? onHover;

  /// Label when [items] is empty.
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(DswTokens.spaceMd),
        decoration: BoxDecoration(
          color: aliases.specificMenu,
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
          border: Border.all(color: aliases.borderL2),
          boxShadow: DswTokens.shadowLv2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 16, color: aliases.labelCaption),
            const SizedBox(width: DswTokens.spaceSm),
            Text(
              emptyLabel,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(
        maxHeight: 280,
        maxWidth: 360,
        minWidth: 220,
      ),
      decoration: BoxDecoration(
        color: aliases.specificMenu,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderInverted),
        boxShadow: DswTokens.shadowLv2,
      ),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: DswTokens.transparent,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(DswTokens.spaceXs),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (BuildContext context, int index) {
            final TriggerItem item = items[index];
            final bool selected = index == selectedIndex;
            return _TriggerRow(
              item: item,
              selected: selected,
              aliases: aliases,
              onTap: () => onSelect(item),
              onHover: onHover == null ? null : () => onHover!(index),
            );
          },
        ),
      ),
    );
  }
}

class _TriggerRow extends StatefulWidget {
  const _TriggerRow({
    required this.item,
    required this.selected,
    required this.aliases,
    required this.onTap,
    this.onHover,
  });

  final TriggerItem item;
  final bool selected;
  final DswAliases aliases;
  final VoidCallback onTap;
  final VoidCallback? onHover;

  @override
  State<_TriggerRow> createState() => _TriggerRowState();
}

class _TriggerRowState extends State<_TriggerRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bool active = widget.selected || _hovering;
    final Color bg = active
        ? widget.aliases.interactiveBgHover
        : DswTokens.transparent;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        widget.onHover?.call();
      },
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          hoverColor: widget.aliases.interactiveBgHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceSm,
              vertical: DswTokens.spaceSm,
            ),
            child: Row(
              children: [
                Icon(
                  _iconFor(widget.item),
                  size: 14,
                  color: widget.aliases.labelTertiary,
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: FontWeight.w500,
                          color: widget.aliases.labelPrimary,
                        ),
                      ),
                      if (widget.item.description != null)
                        Text(
                          widget.item.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: widget.aliases.labelTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.selected)
                  Icon(
                    Icons.north_west,
                    size: 12,
                    color: widget.aliases.labelCaption,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(TriggerItem item) {
    final String label = item.label;
    if (label.startsWith('/')) return Icons.terminal;
    if (label.startsWith('@')) return Icons.description_outlined;
    if (label.startsWith('#')) return Icons.tag;
    return Icons.circle_outlined;
  }
}
