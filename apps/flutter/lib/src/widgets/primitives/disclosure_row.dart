import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';

/// Shared 24px disclosure chrome — Flutter port of `DisclosureRow.tsx` +
/// `DisclosureRow.module.css`.
///
/// Slots → Widget?: [leadingIcon] the 16px leading, [collapsedContent] inline
/// when collapsed (or when [keepContentWhenOpen]), [child] the expanded body.
/// Pure build, no `ctx`.
class DisclosureRow extends ConsumerStatefulWidget {
  const DisclosureRow({
    super.key,
    required this.icon,
    required this.title,
    required this.open,
    required this.expandable,
    required this.onToggle,
    this.expandOnRowClick = false,
    this.previewChevron,
    this.keepContentWhenOpen = false,
    this.collapsedContent,
    this.child,
    this.leadingSize = 16,
  });

  /// Leading 16px icon node.
  final Widget icon;

  /// Row title.
  final String title;

  /// Whether the disclosure is expanded.
  final bool open;

  /// Whether the row can be expanded at all.
  final bool expandable;

  /// Called to toggle [open].
  final VoidCallback onToggle;

  /// When true the entire row is the disclosure target (mirrors web
  /// `expandOnRowClick`).
  final bool expandOnRowClick;

  /// When true shows chevron on hover while collapsed. Defaults to
  /// [expandable] matching web `previewChevron = expandable`.
  final bool? previewChevron;

  /// Keeps [collapsedContent] visible while open.
  final bool keepContentWhenOpen;

  /// Inline content shown collapsed (and optionally while open).
  final Widget? collapsedContent;

  /// Expanded body, shown only when [open] is true.
  final Widget? child;

  /// Leading square size. Defaults to 16.
  final double leadingSize;

  @override
  ConsumerState<DisclosureRow> createState() => _DisclosureRowState();
}

class _DisclosureRowState extends ConsumerState<DisclosureRow> {
  bool _hovering = false;

  bool get _previewChevron => widget.previewChevron ?? widget.expandable;
  bool get _rowExpands => widget.expandable && widget.expandOnRowClick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool reduced = prefersReducedMotion(context);
    final Duration fast = reduced
        ? Duration.zero
        : DswTokens.transitionDurationFast;

    final bool showCollapsedContent =
        widget.collapsedContent != null &&
        (widget.keepContentWhenOpen || !widget.open);

    final Widget leading = _buildLeading(aliases, reduced: reduced, fast: fast);

    final Widget row = SizedBox(
      height: 24,
      child: Row(
        children: <Widget>[
          // Leading 16px square — button when expandable && !rowExpands
          if (widget.expandable && !_rowExpands)
            InkWell(
              onTap: widget.onToggle,
              borderRadius: BorderRadius.circular(DswTokens.radiusXs),
              child: SizedBox(
                width: widget.leadingSize,
                height: widget.leadingSize,
                child: Center(child: leading),
              ),
            )
          else
            SizedBox(
              width: widget.leadingSize,
              height: widget.leadingSize,
              child: Center(child: leading),
            ),
          const SizedBox(width: 6),
          // Title
          Text(
            widget.title,
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              height: 24 / DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
              fontFamily: 'SF Pro',
              fontFamilyFallback: DswTokens.fontFamilyFallback,
            ),
          ),
          if (showCollapsedContent) ...<Widget>[
            const SizedBox(width: DswTokens.spaceSm),
            Flexible(child: widget.collapsedContent!),
          ],
        ],
      ),
    );

    final Widget decoratedRow = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: _rowExpands ? SystemMouseCursors.click : MouseCursor.defer,
      child: _rowExpands
          ? InkWell(
              onTap: widget.onToggle,
              borderRadius: BorderRadius.circular(DswTokens.radiusXs),
              child: row,
            )
          : row,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        decoratedRow,
        if (widget.open && widget.child != null)
          AnimatedSize(
            duration: fast,
            curve: DswTokens.easeInOut,
            child: widget.child!,
          ),
      ],
    );
  }

  Widget _buildLeading(
    DswAliases aliases, {
    required bool reduced,
    required Duration fast,
  }) {
    // Open: chevron down with rotation animation.
    // Closed: icon idle + chevron hover preview.
    if (widget.open) {
      return AnimatedRotation(
        turns: 0, // down
        duration: fast,
        child: Icon(
          Icons.keyboard_arrow_down,
          size: 16,
          color: aliases.labelTertiary,
        ),
      );
    }

    if (_previewChevron) {
      // Cross-fade between idle icon and chevron on hover — mirrors
      // `DisclosureRow.module.css: opacity 100ms ease` with reduced-motion gate.
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedOpacity(
            opacity: _hovering ? 0 : 1,
            duration: fast,
            child: SizedBox(
              width: widget.leadingSize,
              height: widget.leadingSize,
              child: IconTheme(
                data: IconThemeData(size: 16, color: aliases.labelTertiary),
                child: widget.icon,
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _hovering ? 1 : 0,
            duration: fast,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: aliases.labelTertiary,
            ),
          ),
        ],
      );
    }

    return IconTheme(
      data: IconThemeData(size: 16, color: aliases.labelTertiary),
      child: widget.icon,
    );
  }
}
