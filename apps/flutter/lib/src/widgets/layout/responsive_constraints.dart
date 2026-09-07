import 'package:flutter/material.dart';

import 'responsive.dart';

/// Applies different [BoxConstraints] based on viewport width.
///
/// Uses [LayoutBuilder] for frame width (mirrors `AppFrame` pattern)
/// with [MediaQuery] fallback when constraints are unbounded.
///
/// Example:
/// ```dart
/// ResponsiveConstraints(
///   narrow: const BoxConstraints(maxWidth: double.infinity),
///   medium: const BoxConstraints(maxWidth: 680),
///   wide: const BoxConstraints(maxWidth: 780),
///   child: MyWidget(),
/// )
/// ```
///
/// If a tier's constraints are `null`, the child's intrinsic constraints
/// are used for that breakpoint (no wrapping).
class ResponsiveConstraints extends StatelessWidget {
  /// Creates responsive constraints.
  const ResponsiveConstraints({
    super.key,
    required this.child,
    this.narrow,
    this.medium,
    this.wide,
  });

  /// The child widget.
  final Widget child;

  /// Constraints for narrow viewports (<768px).
  final BoxConstraints? narrow;

  /// Constraints for medium viewports (768–1024px).
  final BoxConstraints? medium;

  /// Constraints for wide viewports (≥1024px).
  final BoxConstraints? wide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        BoxConstraints? selected;
        if (viewport < ResponsiveBreakpoints.narrow) {
          selected = narrow;
        } else if (viewport < ResponsiveBreakpoints.medium) {
          selected = medium;
        } else {
          selected = wide;
        }

        if (selected == null) return child;
        return ConstrainedBox(constraints: selected, child: child);
      },
    );
  }
}

/// Applies different max widths based on viewport width.
///
/// Convenience wrapper around [ResponsiveConstraints] for the common
/// case of responsive max-width only.
///
/// Example:
/// ```dart
/// ResponsiveMaxWidth(
///   narrow: double.infinity,
///   medium: 680,
///   wide: 780,
///   child: MyWidget(),
/// )
/// ```
class ResponsiveMaxWidth extends StatelessWidget {
  /// Creates a responsive max width wrapper.
  const ResponsiveMaxWidth({
    super.key,
    required this.child,
    required this.narrow,
    required this.medium,
    required this.wide,
  });

  /// The child widget.
  final Widget child;

  /// Max width for narrow viewports (<768px).
  final double narrow;

  /// Max width for medium viewports (768–1024px).
  final double medium;

  /// Max width for wide viewports (≥1024px).
  final double wide;

  @override
  Widget build(BuildContext context) {
    return ResponsiveConstraints(
      narrow: BoxConstraints(maxWidth: narrow),
      medium: BoxConstraints(maxWidth: medium),
      wide: BoxConstraints(maxWidth: wide),
      child: child,
    );
  }
}
