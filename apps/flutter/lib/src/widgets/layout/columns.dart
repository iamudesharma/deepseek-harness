library;

/// Pure concession-chain column solver for the three-column AppFrame.
///
/// Mirrors `packages/client/ui-layout/src/client/columns.ts`.
/// Chain order is fixed by contract: keep center >= [kCenterMin] by shrinking
/// details, then auto-closing it (derived zero width — preferred widths are
/// never rewritten, so widening the window restores them). The sidebar never
/// concedes: its rendered width is always the drag preference (or the collapsed
/// rail), and center absorbs any remaining deficit as the last resort.
/// Inputs are plain width preferences (0 = closed); a closed sidebar resolves
/// to the fixed [kSidebarCollapsed] rail while closed details resolve to zero.
///
/// The [kSidebarAutoCollapse] breakpoint is consumed by [AppFrame], which
/// decides the effective sidebar preference before solving; the solver itself
/// stays breakpoint-free.

/// Resolved widths for one frame; center may drop below [kCenterMin] only
/// at the final fallback.
class Columns {
  /// Rendered sidebar width in px (collapsed rail when closed).
  final double sidebar;

  /// Rendered center width in px.
  final double center;

  /// Rendered details width in px (0 means visually closed but mounted).
  final double details;

  /// Creates column widths.
  const Columns({
    required this.sidebar,
    required this.center,
    required this.details,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Columns &&
          sidebar == other.sidebar &&
          center == other.center &&
          details == other.details;

  @override
  int get hashCode => Object.hash(sidebar, center, details);

  @override
  String toString() =>
      'Columns(sidebar: $sidebar, center: $center, details: $details)';
}

// Contract-frozen geometry: the three-column concession chain's fixed points.

/// Center column floor; only the final fallback may go below it.
const double kCenterMin = 640;

/// Sidebar drag clamp floor.
const double kSidebarMin = 264;

/// Sidebar drag clamp ceiling.
const double kSidebarMax = 420;

/// Sidebar width before any user drag.
const double kSidebarDefault = 280;

/// Closed-sidebar rail: a 24px icon column between 16px horizontal paddings.
const double kSidebarCollapsed = 56;

/// Viewport width below which the sidebar auto-collapses to the rail.
///
/// Web uses 1024 (`SIDEBAR_AUTO_COLLAPSE`); Flutter port uses 768 via
/// `breakpoints.dart:sidebarCollapse` per task spec. This constant is kept
/// at 768 for Flutter-side checks; the solver itself is breakpoint-free.
const double kSidebarAutoCollapse = 768;

/// Details drag clamp floor.
const double kDetailsMin = 300;

/// Details drag clamp ceiling.
const double kDetailsMax = 520;

/// Details width before any user drag.
const double kDetailsDefault = 360;

/// Clamp a panel width into its contract range.
///
/// @param px - requested width.
/// @param min - range lower bound.
/// @param max - range upper bound.
/// @returns the clamped width.
double clampWidth(double px, double min, double max) {
  return px.clamp(min, max).roundToDouble();
}

/// Solve the three column widths for one viewport frame. Pure: no hysteresis —
/// the output is a function of (viewport, preferences) only, so recovery on
/// re-widening is automatic. Preferences re-clamp here because they cross the
/// store boundary and callers may still supply stale ranges.
///
/// @param viewport - available frame width in px.
/// @param sidebar - sidebar width preference in px (0 = closed).
/// @param details - details width preference in px (0 = closed).
/// @returns resolved widths; details 0 means visually closed (never unmounted),
/// while a closed sidebar keeps its compact rail.
Columns computeColumns(double viewport, double sidebar, double details) {
  // The sidebar is fixed at its preference (or the rail) — it never concedes.
  final double s = sidebar == 0
      ? kSidebarCollapsed
      : clampWidth(sidebar, kSidebarMin, kSidebarMax);
  final double d0 = details == 0
      ? 0
      : clampWidth(details, kDetailsMin, kDetailsMax);

  // Step 1: everything fits at preferred widths.
  if (s + d0 + kCenterMin <= viewport) {
    return Columns(sidebar: s, center: viewport - s - d0, details: d0);
  }

  // Step 2: shrink details toward its minimum.
  final double d1 = d0 == 0
      ? 0
      : (kDetailsMin > viewport - s - kCenterMin
            ? kDetailsMin
            : viewport - s - kCenterMin);
  if (s + d1 + kCenterMin <= viewport) {
    return Columns(sidebar: s, center: kCenterMin, details: d1);
  }

  // Step 3: auto-close details (derived — preferences untouched); center
  // absorbs any remaining deficit (may drop below CENTER_MIN).
  return Columns(
    sidebar: s,
    center: (viewport - s).clamp(0, double.infinity).toDouble(),
    details: 0,
  );
}
