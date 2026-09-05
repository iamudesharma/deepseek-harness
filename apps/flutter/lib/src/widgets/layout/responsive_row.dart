import 'package:flutter/material.dart';

import 'responsive.dart';

/// Stacks children vertically on narrow viewports, horizontally on wide.
///
/// Uses [LayoutBuilder] for frame width with [MediaQuery] fallback.
///
/// Example:
/// ```dart
/// ResponsiveRow(
///   spacing: 12,
///   children: [WidgetA(), WidgetB(), WidgetC()],
/// )
/// ```
///
/// On narrow viewports (<768px), children stack vertically with [spacing]
/// between them. On wide viewports, they flow horizontally.
class ResponsiveRow extends StatelessWidget {
  /// Creates a responsive row/column.
  const ResponsiveRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.mainAxisSize = MainAxisSize.min,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.verticalDirection = VerticalDirection.down,
    this.breakpoint = ResponsiveBreakpoints.narrow,
  });

  /// The child widgets.
  final List<Widget> children;

  /// Spacing between children.
  final double spacing;

  /// Main axis size for the wide (row) layout.
  final MainAxisSize mainAxisSize;

  /// Cross axis alignment.
  final CrossAxisAlignment crossAxisAlignment;

  /// Vertical direction for the narrow (column) layout.
  final VerticalDirection verticalDirection;

  /// Breakpoint at which the layout switches from column to row.
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final bool isNarrow = viewport < breakpoint;

        if (isNarrow) {
          return Column(
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            verticalDirection: verticalDirection,
            children: _withSpacing(children, spacing, isVertical: true),
          );
        }

        return Row(
          mainAxisSize: mainAxisSize,
          crossAxisAlignment: crossAxisAlignment,
          children: _withSpacing(children, spacing, isVertical: false),
        );
      },
    );
  }

  List<Widget> _withSpacing(
    List<Widget> children,
    double spacing, {
    required bool isVertical,
  }) {
    if (children.isEmpty) return children;
    final List<Widget> result = [];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          isVertical ? SizedBox(height: spacing) : SizedBox(width: spacing),
        );
      }
    }
    return result;
  }
}

/// Responsive wrap that adjusts the number of columns based on viewport.
///
/// Each child gets equal width within the row based on [columns].
///
/// Example:
/// ```dart
/// ResponsiveColumnWrap(
///   narrowColumns: 1,
///   mediumColumns: 2,
///   wideColumns: 3,
///   spacing: 12,
///   runSpacing: 12,
///   children: [CardA(), CardB(), CardC()],
/// )
/// ```
class ResponsiveColumnWrap extends StatelessWidget {
  /// Creates a responsive column wrap.
  const ResponsiveColumnWrap({
    super.key,
    required this.children,
    required this.narrowColumns,
    required this.mediumColumns,
    required this.wideColumns,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  /// The child widgets.
  final List<Widget> children;

  /// Number of columns for narrow viewports.
  final int narrowColumns;

  /// Number of columns for medium viewports.
  final int mediumColumns;

  /// Number of columns for wide viewports.
  final int wideColumns;

  /// Horizontal spacing between columns.
  final double spacing;

  /// Vertical spacing between rows.
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final int columns;
        if (viewport < ResponsiveBreakpoints.narrow) {
          columns = narrowColumns;
        } else if (viewport < ResponsiveBreakpoints.medium) {
          columns = mediumColumns;
        } else {
          columns = wideColumns;
        }

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map(
                (child) => SizedBox(
                  width: (viewport - spacing * (columns - 1)) / columns,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}
