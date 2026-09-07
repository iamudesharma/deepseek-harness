import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Geometry constants mirrored from `packages/client/ui-layout/src/client/columns.ts`.
///
/// These are contract-frozen values; they are not deployment tunables.
const double kSidebarDefault = 280;
const double kSidebarMin = 264;
const double kSidebarMax = 420;
const double kSidebarCollapsed = 56;
const double kSidebarAutoCollapse = 1024;
const double kDetailsDefault = 360;
const double kDetailsMin = 300;
const double kDetailsMax = 520;
const double kCenterMin = 640;

/// Clamp [px] into `[min, max]` rounding to nearest pixel.
double clampWidth(double px, double min, double max) {
  return px.clamp(min, max).roundToDouble();
}

/// Layout panel state: plain width preferences in px (0 = closed) plus the
/// narrow-viewport pair.
///
/// Mirrors `LayoutState` in `packages/client/ui-layout/src/client/stores.ts`.
///
/// * `sidebar` — width preference in px, 0 means closed. Default [kSidebarDefault].
/// * `details` — width preference in px, 0 means closed. Default **0**
///   (React stores.ts init `details: 0`; openDetails restores
///   [kDetailsDefault]. The Dart runtime has no details occupant yet, so the
///   track stays closed until a real DetailsPanel port lands).
/// * `narrow` — mirrors `AppFrame`'s breakpoint reading (viewport < [kSidebarAutoCollapse]).
/// * `narrowExpanded` — manual override that re-expands the auto-collapsed sidebar
///   over the squeezed center without rewriting the width preference.
class LayoutState {
  /// Sidebar width preference in px (0 = closed).
  final double sidebar;

  /// Details width preference in px (0 = closed).
  final double details;

  /// Whether the viewport is below [kSidebarAutoCollapse].
  final bool narrow;

  /// Manual override that re-expands a narrow auto-collapsed sidebar.
  final bool narrowExpanded;

  /// Creates a layout state. `details` boots closed (React stores.ts
  /// init `details: 0`).
  const LayoutState({
    this.sidebar = kSidebarDefault,
    this.details = 0,
    this.narrow = false,
    this.narrowExpanded = false,
  });

  /// Creates a copy with selected fields replaced.
  LayoutState copyWith({
    double? sidebar,
    double? details,
    bool? narrow,
    bool? narrowExpanded,
  }) {
    return LayoutState(
      sidebar: sidebar ?? this.sidebar,
      details: details ?? this.details,
      narrow: narrow ?? this.narrow,
      narrowExpanded: narrowExpanded ?? this.narrowExpanded,
    );
  }

  /// Whether the sidebar is visually collapsed.
  ///
  /// Mirrors `AppFrame.tsx`:
  /// ```ts
  /// const sidebarCollapsed = narrow ? !narrowExpanded : sidebar === 0;
  /// ```
  bool get sidebarCollapsed => narrow ? !narrowExpanded : sidebar == 0;

  /// Whether the details panel is visually collapsed (closed).
  bool get detailsCollapsed => details == 0;

  /// Whether the details panel is open.
  bool get detailsOpen => details != 0;

  /// Effective sidebar width used by the column solver.
  ///
  /// Collapsed resolves to 0 in state; the fixed rail ([kSidebarCollapsed])
  /// is applied by the solver/view layer. When not collapsed but preference is
  /// 0 (re-expand after narrow), the contract default is used.
  double get effectiveSidebar {
    if (sidebarCollapsed) return 0;
    if (sidebar == 0) return kSidebarDefault;
    return sidebar;
  }

  /// Effective details width used by the column solver.
  double get effectiveDetails => details;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutState &&
          runtimeType == other.runtimeType &&
          sidebar == other.sidebar &&
          details == other.details &&
          narrow == other.narrow &&
          narrowExpanded == other.narrowExpanded;

  @override
  int get hashCode => Object.hash(sidebar, details, narrow, narrowExpanded);

  @override
  String toString() =>
      'LayoutState(sidebar: $sidebar, details: $details, narrow: $narrow, narrowExpanded: $narrowExpanded)';
}

/// Controller for [LayoutState].
///
/// Factory is invocable via `ProviderContainer` for tests — no static
/// singleton, matches `createLayoutStore().create()` test pattern.
///
/// Actions mirror `createLayoutStore`:
/// drag writes clamp into the panel's contract range; open/close transitions
/// write 0 / the contract default. Below the auto-collapse breakpoint the
/// toggle flips [narrowExpanded] instead of the preference.
class LayoutController extends Notifier<LayoutState> {
  @override
  LayoutState build() => const LayoutState();

  /// Set sidebar width preference (clamped to [kSidebarMin]..[kSidebarMax]).
  ///
  /// Does not cross the open/closed line; use [toggleSidebar] / [setNarrow].
  void setSidebar(double px) {
    state = state.copyWith(sidebar: clampWidth(px, kSidebarMin, kSidebarMax));
  }

  /// Set details width preference (clamped to [kDetailsMin]..[kDetailsMax]).
  void setDetails(double px) {
    state = state.copyWith(details: clampWidth(px, kDetailsMin, kDetailsMax));
  }

  /// Mirror viewport breakpoint into [LayoutState.narrow].
  ///
  /// Crossing either direction drops [narrowExpanded] so the narrow default
  /// is auto-collapsed and the wide state is the width preference.
  void setNarrow(bool value) {
    if (state.narrow == value) return;
    state = state.copyWith(narrow: value, narrowExpanded: false);
  }

  /// Toggle sidebar.
  ///
  /// Narrow viewports flip [narrowExpanded] (preference survives untouched so
  /// re-widening restores layout). Wide viewports toggle preference 0 / default.
  void toggleSidebar() {
    if (state.narrow) {
      state = state.copyWith(narrowExpanded: !state.narrowExpanded);
    } else {
      state = state.copyWith(sidebar: state.sidebar == 0 ? kSidebarDefault : 0);
    }
  }

  /// Close details panel (preference becomes 0; drag width is forgotten).
  void closeDetails() {
    if (state.details == 0) return;
    state = state.copyWith(details: 0);
  }

  /// Open details panel (no-op when already open; restores [kDetailsDefault]).
  void openDetails() {
    if (state.details != 0) return;
    state = state.copyWith(details: kDetailsDefault);
  }
}

/// Global layout provider. Scoped via `ProviderScope` overrides to share
/// across registrations without a static singleton.
final layoutProvider = NotifierProvider<LayoutController, LayoutState>(
  LayoutController.new,
);
