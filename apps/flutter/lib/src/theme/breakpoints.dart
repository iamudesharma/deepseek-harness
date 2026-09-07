import 'package:flutter/widgets.dart';

/// Mirrors the web `SIDEBAR_AUTO_COLLAPSE` / layout breakpoint (768px).
const double sidebarCollapse = 768.0;

/// Responsive helpers for Flutter layout.
extension Responsive on BuildContext {
  /// True when viewport width is narrow (below [sidebarCollapse]).
  bool get isNarrow => MediaQuery.sizeOf(this).width < sidebarCollapse;

  /// True when viewport width is at or above [sidebarCollapse].
  bool get isWide => !isNarrow;
}
