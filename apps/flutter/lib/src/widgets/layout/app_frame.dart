import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session/sessions_controller.dart';
import '../../features/layout/layout_controller.dart';
import '../../platform/window.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import 'columns.dart' as col;
import 'responsive.dart';

/// One drag handle: pointer capture, dx reports against the drag-start origin.
///
/// Mirrors `DragHandle` in `packages/client/ui-layout/src/client/AppFrame.tsx`:
/// pointer capture, left position, onStart/onDrag/onEnd with pointer capture
/// semantics. `side` keys the hover-reveal styling (`sidebar` vs `details`).
class DragHandle extends StatefulWidget {
  /// Creates a drag handle.
  const DragHandle({
    super.key,
    required this.side,
    required this.left,
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
  });

  /// Which column owns the handle (keys the hover styling).
  final String side; // 'sidebar' | 'details'

  /// Absolute left position in px (center of the handle).
  final double left;

  /// Called on pointer capture at drag start.
  final VoidCallback onStart;

  /// Called on drag with dx from origin (positive rightward).
  final ValueChanged<double> onDrag;

  /// Called on pointer release.
  final VoidCallback onEnd;

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle> {
  bool _dragging = false;
  double _origin = 0;
  bool _hovered = false;

  void _handleStart(DragStartDetails details) {
    _origin = details.globalPosition.dx;
    widget.onStart();
    setState(() => _dragging = true);
  }

  void _handleUpdate(DragUpdateDetails details) {
    final double dx = details.globalPosition.dx - _origin;
    widget.onDrag(dx);
  }

  void _handleEnd(DragEndDetails details) {
    setState(() => _dragging = false);
    widget.onEnd();
  }

  void _handleCancel() {
    if (_dragging) {
      setState(() => _dragging = false);
      widget.onEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 8px hit strip; outer Positioned is provided by AppFrame's Stack.
    // This widget is the strip content itself (no Positioned here).
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleStart,
        onHorizontalDragUpdate: _handleUpdate,
        onHorizontalDragEnd: _handleEnd,
        onHorizontalDragCancel: _handleCancel,
        dragStartBehavior: DragStartBehavior.down,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: Container(color: DswTokens.transparent)),
            if (widget.side == 'details')
              Center(
                child: AnimatedOpacity(
                  duration: _dragging
                      ? Duration.zero
                      : DswTokens.transitionDurationSlow,
                  opacity: (_hovered || _dragging) ? 1 : 0,
                  child: Container(
                    width: 12,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _hovered || _dragging
                          ? Theme.of(context)
                                    .extension<DswThemeExtension>()
                                    ?.aliases
                                    .buttonFloatingHover ??
                                DswTokens.neutralBluish00
                          : Theme.of(context)
                                    .extension<DswThemeExtension>()
                                    ?.aliases
                                    .buttonFloatingFill ??
                                DswTokens.neutralBluish00,
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                      boxShadow: DswTokens.shadowLv1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Three-column shell frame, registered as the root shell.
///
/// Mirrors `AppFrame` in `packages/client/ui-layout/src/client/AppFrame.tsx`:
/// owns the grid tracks (sidebar | center | details), the drag handles
/// (pointer capture + frame-throttled), the concession chain ([computeColumns]),
/// and the child-slot render decisions.
///
/// Uses [LayoutBuilder] for the frame box width (not [MediaQuery] for frame),
/// tracks viewport via [LayoutBuilder] constraints, and respects
/// `SIDEBAR_AUTO_COLLAPSE=768` via [sidebarCollapse] / [BuildContext.isNarrow]
/// (see [ResponsiveBreakpoints] + [responsive.dart]). Width persistence is
/// handled via [persistLayoutWidths] / [restoreLayoutWidths] through
/// `SharedPreferences` and `window_manager`'s `minimumSize` on macOS.
///
/// Details column keeps its subtree mounted when width 0 (never unmount on
/// close), matching the web `DetailsColumn` semantics. Sidebar width animates
/// with the deepsuite sider curve; animation pauses while dragging.
class AppFrame extends ConsumerStatefulWidget {
  /// Creates the app frame.
  const AppFrame({
    super.key,
    this.sidebar,
    this.conversation,
    this.details,
    this.overlay,
    this.child,
    this.navigationShell,
    this.conversationLayer,
  });

  /// Sidebar slot content. Receives live width/collapsed via [layoutProvider]
  /// (mirrors `renderSlot('sidebar', {collapsed, width})`).
  final Widget? sidebar;

  /// Center conversation slot content.
  final Widget? conversation;

  /// Details slot content (kept mounted when width 0).
  final Widget? details;

  /// Overlay slot content (floats over the whole app, like `shell.overlay`).
  final Widget? overlay;

  /// Alternative center child (used when [navigationShell] is provided the
  /// shell's indexed stack is the child).
  final Widget? child;

  /// Stateful navigation shell from `GoRouter`'s `StatefulShellRoute.indexedStack`.
  /// When non-null, rendered as the center occupant.
  final StatefulNavigationShell? navigationShell;

  /// Conversation hub contribution (`layout.center` slot outlet), mounted as
  /// a positioned layer over the center occupant. The contributor controls
  /// its own visibility by drawing nothing until a session view is active —
  /// one layout path, slot-composed.
  final Widget? conversationLayer;

  @override
  ConsumerState<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends ConsumerState<AppFrame> {
  bool _dragging = false;
  double _sidebarBase = 0;
  double _detailsBase = 0;
  col.Columns _colsRef = const col.Columns(
    sidebar: col.kSidebarCollapsed,
    center: 0,
    details: 0,
  );
  double _lastWideWidth = col.kSidebarDefault;
  bool _settled = true;
  bool? _prevCollapsed;
  Timer? _settleTimer;
  static const Duration _collapseSettle = Duration(milliseconds: 150);

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(layoutProvider);
    final layoutNotifier = ref.read(layoutProvider.notifier);

    // Listen for session changes to auto-close details (mirrors AppFrame
    // detailsSession guard and useLayoutEffect that calls closeDetails on
    // current switch).
    ref.listen<SessionsState>(sessionsProvider, (previous, next) {
      final prevId = previous?.current;
      final nextId = next.current;
      if (nextId != null && prevId != null && prevId != nextId) {
        final details = ref.read(layoutProvider).details;
        if (details != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ref.read(layoutProvider.notifier).closeDetails();
          });
        }
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewport =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final bool narrow = viewport < sidebarCollapse;
        if (layout.narrow != narrow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ref.read(layoutProvider.notifier).setNarrow(narrow);
          });
        }

        final bool sidebarCollapsed = narrow
            ? !layout.narrowExpanded
            : layout.sidebar == 0;
        // Settle handling mirrors SidebarRoot.tsx: wide stays mounted while collapse animates (150ms fade).
        if (_prevCollapsed != sidebarCollapsed) {
          if (sidebarCollapsed) {
            _settleTimer?.cancel();
            _settleTimer = Timer(_collapseSettle, () {
              if (mounted) setState(() => _settled = true);
            });
          } else {
            _settleTimer?.cancel();
            _settled = false;
          }
          _prevCollapsed = sidebarCollapsed;
        }
        final double sidebarPreference = sidebarCollapsed
            ? 0
            : layout.sidebar == 0
            ? col.kSidebarDefault
            : layout.sidebar;

        final double detailsPreference = layout.details;

        final col.Columns cols = col.computeColumns(
          viewport,
          sidebarPreference,
          detailsPreference,
        );
        _colsRef = cols;
        // Freeze last wide width while fading — sliding column clips it instead of reflowing.
        if (!sidebarCollapsed) _lastWideWidth = cols.sidebar;

        final bool detailsCollapsed = cols.details == 0;
        final Duration animDuration = _dragging || prefersReducedMotion(context)
            ? Duration.zero
            : DswTokens.transitionDurationSlow;
        const Curve animCurve = DswTokens.easeInOut;

        void onSidebarStart() {
          _sidebarBase = _colsRef.sidebar;
          setState(() => _dragging = true);
        }

        void onDetailsStart() {
          _detailsBase = _colsRef.details;
          setState(() => _dragging = true);
        }

        void onSidebarDrag(double dx) {
          layoutNotifier.setSidebar(_sidebarBase + dx);
        }

        void onDetailsDrag(double dx) {
          layoutNotifier.setDetails(_detailsBase - dx);
        }

        void onDragEnd() {
          if (mounted) setState(() => _dragging = false);
          // Persist layout widths for window restore (SharedPreferences;
          // window_manager minSize is set once in initWindow).
          final current = ref.read(layoutProvider);
          persistLayoutWidths(
            sidebar: current.sidebar,
            details: current.details,
          );
        }

        final Widget centerChild =
            widget.navigationShell ??
            widget.conversation ??
            widget.child ??
            const _PlaceholderConversation();

        final Widget sidebarChild =
            widget.sidebar ?? const _PlaceholderSidebar();
        final Widget detailsChild = widget.details ?? const SizedBox.shrink();
        final Widget? overlayChild = widget.overlay;
        final Widget? conversationLayer = widget.conversationLayer;

        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: animDuration,
                    curve: animCurve,
                    width: cols.sidebar,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .extension<DswThemeExtension>()
                          ?.aliases
                          .specificSidebarFill,
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: sidebarCollapsed && !_settled
                          ? _lastWideWidth
                          : cols.sidebar,
                      child: prefersReducedMotion(context)
                          ? sidebarChild
                          : AnimatedOpacity(
                              opacity: sidebarCollapsed && !_settled ? 0 : 1,
                              duration: sidebarCollapsed && !_settled
                                  ? _collapseSettle
                                  : DswTokens.transitionDurationSlow,
                              child: sidebarChild,
                            ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: conversationLayer == null
                          ? centerChild
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                centerChild,
                                Positioned.fill(child: conversationLayer),
                              ],
                            ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: animDuration,
                    curve: animCurve,
                    width: cols.details,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: detailsCollapsed
                          ? null
                          : Border(
                              left: BorderSide(
                                color: Theme.of(context).dividerColor,
                                width: 1,
                              ),
                            ),
                    ),
                    child: SizedBox(
                      width: cols.details,
                      child: detailsCollapsed
                          ? Visibility(
                              visible: false,
                              maintainState: true,
                              maintainAnimation: true,
                              child: detailsChild,
                            )
                          : detailsChild,
                    ),
                  ),
                ],
              ),
              if (overlayChild != null)
                Positioned.fill(
                  child: IgnorePointer(ignoring: false, child: overlayChild),
                ),
              if (!sidebarCollapsed)
                AnimatedPositioned(
                  duration: animDuration,
                  curve: animCurve,
                  left: cols.sidebar - 4,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: DragHandle(
                    side: 'sidebar',
                    left: cols.sidebar,
                    onStart: onSidebarStart,
                    onDrag: onSidebarDrag,
                    onEnd: onDragEnd,
                  ),
                ),
              if (cols.details > 0)
                AnimatedPositioned(
                  duration: animDuration,
                  curve: animCurve,
                  left: viewport - cols.details - 4,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: DragHandle(
                    side: 'details',
                    left: viewport - cols.details,
                    onStart: onDetailsStart,
                    onDrag: onDetailsDrag,
                    onEnd: onDragEnd,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaceholderSidebar extends StatelessWidget {
  const _PlaceholderSidebar();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Sidebar'));
  }
}

class _PlaceholderConversation extends StatelessWidget {
  const _PlaceholderConversation();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Conversation'));
  }
}
