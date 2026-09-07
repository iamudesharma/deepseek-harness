import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Selectable row — Flutter port of `MenuItem` in `Menu.tsx`.
class DsMenuItem {
  const DsMenuItem({
    required this.id,
    required this.label,
    this.icon,
    this.disabled = false,
    this.danger = false,
    this.submenu,
  });

  /// Stable identifier passed to [DsMenu.onSelect].
  final String id;

  /// Visible label.
  final String label;

  /// Leading 16px icon. Color inherits `labelTertiary` / `stateErrorPrimary`.
  final Widget? icon;

  /// When true the row is not interactive (opacity 0.4).
  final bool disabled;

  /// Destructive row — error-colored text/icon and danger hover fill.
  final bool danger;

  /// Nested items opened to the right on hover/focus.
  final List<DsMenuItem>? submenu;

  bool get hasSubmenu => submenu != null && submenu!.isNotEmpty;
}

/// Non-interactive heading row — mirrors `MenuLabel`.
class DsMenuLabel {
  const DsMenuLabel({required this.id, required this.text});

  final String id;
  final String text;
}

/// Hairline separator — mirrors `MenuSeparator`.
class DsMenuSeparator {
  const DsMenuSeparator({required this.id});

  final String id;
}

/// Union entry for [DsMenu].
typedef DsMenuEntry = Object; // DsMenuItem | DsMenuLabel | DsMenuSeparator

/// Token-styled dropdown — Flutter port of `Menu.tsx` + `Menu.module.css`.
///
/// Owner-controlled via [open]. Uses [MenuAnchor] (overlay) so the list
/// escapes ancestor clipping without a manual portal. Submenus use
/// [SubmenuButton]. Pure build, no `ctx`.
class DsMenu extends ConsumerWidget {
  const DsMenu({
    super.key,
    required this.anchor,
    required this.items,
    required this.onSelect,
    required this.onClose,
    this.open = false,
    this.selectedId,
    this.selectedIds,
    this.align = DsMenuAlign.start,
    this.side = DsMenuSide.bottom,
    this.dense = false,
    this.compact = false,
    this.footer,
    this.controller,
  });

  /// Trigger widget (e.g. a button). Rendered in place.
  final Widget anchor;

  /// Rows, separators, and headings.
  final List<DsMenuEntry> items;

  /// Row selection callback. Not called for disabled rows or submenu parents
  /// that only open children.
  final ValueChanged<String> onSelect;

  /// Called on outside tap or Escape.
  final VoidCallback onClose;

  /// Whether the list is showing. Owner-controlled.
  final bool open;

  /// Row shown as selected (trailing check).
  final String? selectedId;

  /// Rows shown as selected when a menu contains independent option groups.
  final List<String>? selectedIds;

  /// Horizontal alignment against the anchor.
  final DsMenuAlign align;

  /// Open side. `right` is used for context menus anchored to a point.
  final DsMenuSide side;

  /// Reduce vertical row spacing.
  final bool dense;

  /// Use reduced typography and spacing (164px card).
  final bool compact;

  /// Rows pinned below the scroll region.
  final List<DsMenuEntry>? footer;

  /// Optional external [MenuController] for programmatic open/close.
  final MenuController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final MenuController menuController = controller ?? MenuController();

    // Keep controller in sync with owner-controlled [open].
    // Post-frame so we don't call open/close during build.
    if (open != menuController.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (open) {
          if (!menuController.isOpen) menuController.open();
        } else {
          if (menuController.isOpen) menuController.close();
        }
      });
    }

    // Viewport-capped height — mirrors `Menu.module.css:.scrollable max-height calc(100vh - 24px)`.
    final double viewportMaxHeight = MediaQuery.of(context).size.height - 24;
    final MenuStyle menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(aliases.specificMenu),
      surfaceTintColor: const WidgetStatePropertyAll(DswTokens.transparent),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 7 : DswTokens.radiusLg),
          side: BorderSide(color: aliases.borderInverted),
        ),
      ),
      elevation: const WidgetStatePropertyAll(8),
      padding: WidgetStatePropertyAll(
        EdgeInsets.all(compact ? 2 : DswTokens.spaceXs),
      ),
      maximumSize: WidgetStatePropertyAll(
        Size(compact ? 164 : 360, viewportMaxHeight),
      ),
      minimumSize: WidgetStatePropertyAll(Size(compact ? 164 : 218, 0)),
      shadowColor: WidgetStatePropertyAll(theme.shadowColor),
    );

    // Scrollbar thumb per Menu.module.css --dsh-scrollbar-thumb L2
    final ThemeData themed = theme.copyWith(
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered))
            return aliases.scrollbarHoverL2;
          return aliases.scrollbarBgL2;
        }),
        trackColor: const WidgetStatePropertyAll(DswTokens.transparent),
        radius: const Radius.circular(DswTokens.radiusXs),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );

    return Theme(
      data: themed,
      child: MenuAnchor(
        controller: menuController,
        style: menuStyle,
        alignmentOffset: _alignmentOffset(),
        onClose: onClose,
        onOpen: () {},
        menuChildren: <Widget>[
          ...items.map((DsMenuEntry e) => _buildEntry(context, aliases, e)),
          if (footer != null && footer!.isNotEmpty) ...<Widget>[
            Divider(height: 9, thickness: 1, color: aliases.borderL2),
            ...footer!.map((DsMenuEntry e) => _buildEntry(context, aliases, e)),
          ],
        ],
        builder: (BuildContext ctx, MenuController ctrl, Widget? child) {
          return InkWell(
            onTap: () {
              if (ctrl.isOpen) {
                ctrl.close();
              } else {
                ctrl.open();
              }
            },
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            child: anchor,
          );
        },
      ),
    );
  }

  Offset _alignmentOffset() {
    // Mirrors Menu.tsx portal math simplified for MenuAnchor's alignmentOffset.
    // MenuAnchor positions below by default; we nudge 4px gap.
    switch (side) {
      case DsMenuSide.top:
        return const Offset(0, -4);
      case DsMenuSide.right:
        return const Offset(4, 0);
      case DsMenuSide.bottom:
        return const Offset(0, 4);
    }
  }

  Widget _buildEntry(
    BuildContext context,
    DswAliases aliases,
    DsMenuEntry entry,
  ) {
    if (entry is DsMenuSeparator) {
      return Divider(
        height: 9,
        thickness: 1,
        color: aliases.borderL1,
        indent: 2,
        endIndent: 2,
      );
    }
    if (entry is DsMenuLabel) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: compact ? 4 : 8,
        ),
        child: Text(
          entry.text,
          style: TextStyle(
            fontSize: compact ? 11 : DswTokens.fontSizeXxs12,
            height: (compact ? 16 : 16) / (compact ? 11 : 12),
            color: aliases.labelTertiary,
            fontFamily: 'SF Pro',
            fontFamilyFallback: DswTokens.fontFamilyFallback,
          ),
        ),
      );
    }
    if (entry is DsMenuItem) {
      final bool isSelected =
          entry.id == selectedId || (selectedIds?.contains(entry.id) ?? false);

      // Menu cell min-height: compact 26 / dense 34 / regular 40 — mirrors `Menu.module.css:40/34/26`.
      final double minHeight = compact
          ? 26
          : dense
          ? 34
          : 40;
      final double fontSize = compact
          ? DswTokens.fontSizeXxs12
          : DswTokens.fontSizeS14;
      final double lineHeight = compact
          ? DswTokens.lineHeightXxs12
          : DswTokens.lineHeightS14;

      // Submenu branch — use SubmenuButton
      if (entry.hasSubmenu) {
        return SubmenuButton(
          onHover: entry.disabled ? null : (_) {},
          menuChildren: entry.submenu!
              .map(
                (DsMenuItem sub) => _menuItemButton(
                  aliases,
                  sub,
                  minHeight,
                  fontSize,
                  lineHeight,
                ),
              )
              .toList(),
          style: _itemStyle(aliases, entry, compact, dense),
          child: _itemContent(
            aliases,
            entry,
            isSelected,
            compact,
            fontSize,
            lineHeight,
          ),
        );
      }

      return MenuItemButton(
        onPressed: entry.disabled
            ? null
            : () {
                onSelect(entry.id);
                onClose();
              },
        style: _itemStyle(aliases, entry, compact, dense),
        child: _itemContent(
          aliases,
          entry,
          isSelected,
          compact,
          fontSize,
          lineHeight,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _menuItemButton(
    DswAliases aliases,
    DsMenuItem item,
    double minHeight,
    double fontSize,
    double lineHeight,
  ) {
    final bool isSelected =
        item.id == selectedId || (selectedIds?.contains(item.id) ?? false);
    return MenuItemButton(
      onPressed: item.disabled
          ? null
          : () {
              onSelect(item.id);
              onClose();
            },
      style: _itemStyle(aliases, item, compact, dense),
      child: _itemContent(
        aliases,
        item,
        isSelected,
        compact,
        fontSize,
        lineHeight,
      ),
    );
  }

  ButtonStyle _itemStyle(
    DswAliases aliases,
    DsMenuItem item,
    bool isCompact,
    bool isDense,
  ) {
    final Color hoverBg = item.danger
        ? aliases.interactiveBgHoverDanger
        : aliases.interactiveBgHover;
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return hoverBg;
        }
        return DswTokens.transparent;
      }),
      foregroundColor: WidgetStatePropertyAll(
        item.danger ? aliases.stateErrorPrimary : aliases.labelPrimary,
      ),
      overlayColor: WidgetStatePropertyAll(hoverBg),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isCompact ? 5 : 10),
        ),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: isCompact ? 7 : 10,
          vertical: isCompact
              ? 3
              : isDense
              ? 5
              : 8,
        ),
      ),
      minimumSize: WidgetStatePropertyAll(
        Size(
          double.infinity,
          isCompact
              ? 26
              : isDense
              ? 34
              : 32,
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _itemContent(
    DswAliases aliases,
    DsMenuItem item,
    bool isSelected,
    bool isCompact,
    double fontSize,
    double lineHeight,
  ) {
    final Color iconColor = item.danger
        ? aliases.stateErrorPrimary
        : aliases.labelTertiary;
    final double iconSize = isCompact ? 14 : 16;

    return Row(
      children: <Widget>[
        if (item.icon != null) ...<Widget>[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: IconTheme(
              data: IconThemeData(color: iconColor, size: iconSize),
              child: DefaultTextStyle(
                style: TextStyle(color: iconColor),
                child: item.icon!,
              ),
            ),
          ),
          SizedBox(width: isCompact ? 6 : 8),
        ],
        Expanded(
          child: Text(
            item.label,
            style: TextStyle(
              fontSize: fontSize,
              height: lineHeight / fontSize,
              color: item.danger
                  ? aliases.stateErrorPrimary
                  : aliases.labelPrimary,
              fontFamily: 'SF Pro',
              fontFamilyFallback: DswTokens.fontFamilyFallback,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isSelected) ...<Widget>[
          SizedBox(width: isCompact ? 6 : 8),
          Icon(Icons.check, size: iconSize, color: aliases.labelPrimary),
        ] else if (item.hasSubmenu) ...<Widget>[
          SizedBox(width: isCompact ? 6 : 8),
          Icon(
            Icons.chevron_right,
            size: iconSize,
            color: aliases.labelTertiary,
          ),
        ],
      ],
    );
  }
}

/// Horizontal alignment — mirrors web `align`.
enum DsMenuAlign { start, end }

/// Open side — mirrors web `side`.
enum DsMenuSide { bottom, top, right }
