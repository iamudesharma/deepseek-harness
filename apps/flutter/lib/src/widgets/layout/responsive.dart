import 'package:flutter/material.dart';

import '../../theme/breakpoints.dart';

/// Re-export breakpoints for call sites that import the responsive layer
/// rather than the raw token file. Keeps the import graph flat.
export '../../theme/breakpoints.dart';

/// Canonical responsive breakpoints for the Flutter shell.
///
/// `sidebarCollapse` (768) is the Flutter-side equivalent of web
/// `SIDEBAR_AUTO_COLLAPSE` (`packages/client/ui-layout` originally 1024,
/// unified to 768 for Flutter via `breakpoints.dart` per task). Layout
/// consumers should prefer the named constants over raw literals.
///
/// [ResponsiveScaffold] and [ResponsiveBuilder] branch on these values
/// via [LayoutBuilder] (frame width) falling back to [MediaQuery]
/// when constraints are unbounded.
class ResponsiveBreakpoints {
  /// Narrow viewport ceiling — below this the sidebar auto-collapses
  /// to the 56px rail and may be re-expanded as an overlay.
  static const double narrow = sidebarCollapse; // 768

  /// Medium breakpoint where generous gutters appear.
  static const double medium = 1024;

  /// Wide breakpoint for three-column comfort (center >= 640 + gutters).
  static const double wide = 1440;

  /// True when [width] is below [narrow].
  static bool isNarrowWidth(double width) => width < narrow;

  /// True when [width] is in [narrow, wide).
  static bool isMediumWidth(double width) => width >= narrow && width < wide;

  /// True when [width] is at least [wide].
  static bool isWideWidth(double width) => width >= wide;
}

/// Scaffold that switches between a narrow and a wide layout branch.
///
/// Uses [LayoutBuilder] for the frame width (mirrors `AppFrame`'s
/// `LayoutBuilder` usage — not `MediaQuery` for frame) with
/// `MediaQuery` fallback when constraints are unbounded (e.g. inside
/// an unbounded parent or test `MaterialApp`).
///
/// @param narrow – builder for `width < breakpoint` (overlay / stacked).
/// @param wide – builder for `width >= breakpoint` (side-by-side).
/// @param breakpoint – switch point in px, defaults to [sidebarCollapse]
/// (768).
/// @param child – optional shared child passed through when branch
/// contents are symmetric (unused).
class ResponsiveScaffold extends StatelessWidget {
  /// Creates the responsive scaffold.
  const ResponsiveScaffold({
    super.key,
    required this.narrow,
    required this.wide,
    this.breakpoint = sidebarCollapse,
  });

  /// Builder for the narrow branch (viewport width < [breakpoint]).
  final WidgetBuilder narrow;

  /// Builder for the wide branch (viewport width >= [breakpoint]).
  final WidgetBuilder wide;

  /// Width in px where the branch switches. Defaults to [sidebarCollapse].
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
        return isNarrow ? narrow(context) : wide(context);
      },
    );
  }
}

/// Builder that exposes the full breakpoint classification.
///
/// Unlike [ResponsiveScaffold] which is binary, this widget hands the
/// caller a [ResponsiveData] so call sites can distinguish narrow /
/// medium / wide and pick column counts, gutters, etc.
///
/// Example:
/// ```dart
/// ResponsiveBuilder(
///   builder: (context, data) {
///     if (data.isNarrow) return MobileLayout();
///     if (data.isMedium) return TabletLayout();
///     return DesktopLayout();
///   },
/// )
/// ```
class ResponsiveBuilder extends StatelessWidget {
  /// Creates the responsive builder.
  const ResponsiveBuilder({
    super.key,
    required this.builder,
    this.breakpoint = sidebarCollapse,
  });

  /// Callback with classification.
  final Widget Function(BuildContext context, ResponsiveData data) builder;

  /// Narrow switch point in px.
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final ResponsiveData data = ResponsiveData.fromWidth(
          viewport,
          breakpoint: breakpoint,
        );
        return builder(context, data);
      },
    );
  }
}

/// Snapshot of the current responsive classification.
///
/// Computed from the raw [width] and [breakpoint] so tests can
/// construct it directly without pumping widgets.
class ResponsiveData {
  /// Raw viewport width in px.
  final double width;

  /// Active breakpoint in px.
  final double breakpoint;

  /// Creates response data.
  const ResponsiveData({required this.width, required this.breakpoint});

  /// Derive from a raw width.
  factory ResponsiveData.fromWidth(
    double width, {
    double breakpoint = sidebarCollapse,
  }) {
    return ResponsiveData(width: width, breakpoint: breakpoint);
  }

  /// True when `width < breakpoint` (overlay / collapsed).
  bool get isNarrow => width < breakpoint;

  /// True when `width >= breakpoint` (three-column comfortable).
  bool get isWide => !isNarrow;

  /// Mirrors [ResponsiveBreakpoints.isMediumWidth] using [medium]/[wide].
  bool get isMedium =>
      width >= breakpoint && width < ResponsiveBreakpoints.wide;

  /// True when comfortably wide enough for full three-column layout.
  bool get isFullyWide => width >= ResponsiveBreakpoints.wide;

  @override
  String toString() =>
      'ResponsiveData(width: $width, breakpoint: $breakpoint, isNarrow: $isNarrow)';
}

/// Extension for convenience at call sites that already have a
/// [BuildContext] but not a [LayoutBuilder].
///
/// Mirrors `Responsive` in `breakpoints.dart` for migration ease but
/// also exposes the full [ResponsiveData]. Prefer `LayoutBuilder`
/// for frame decisions; use this extension for leaf-widget tweaks.
extension ResponsiveContext on BuildContext {
  /// Current viewport width (from [MediaQuery]).
  double get viewportWidth => MediaQuery.sizeOf(this).width;

  /// Responsive snapshot derived from [MediaQuery] width.
  ResponsiveData get responsive => ResponsiveData.fromWidth(viewportWidth);
}
