/// Anchored dropdown menu — shared overlay primitive port of React's
/// `Menu` (`packages/client/ui-primitives/src/Menu.tsx`) portal mode.
///
/// Architecture (same as the `/` and `@` input-trigger menus):
/// trigger → [CompositedTransformTarget] → root-overlay [OverlayPortal] →
/// [CompositedTransformFollower] with viewport-aware placement.
///
/// Geometry mirrors React `Menu.place()` (`Menu.tsx:119-165`):
/// - start-aligned to the trigger rect, 4px gap;
/// - 12px viewport clearance on every side;
/// - flips above the trigger when the space below cannot fit the menu and
///   the space above is larger;
/// - the follower keeps the panel glued to the trigger through
///   scroll/resize/reflow without rebuilds;
/// - outside pointer-down and Escape close (document-level listeners port).
///
/// The trigger renders in place via [triggerBuilder]; the menu never uses
/// hardcoded screen coordinates — placement derives from the trigger's
/// [RenderBox] at open time.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// One selectable row.
class AnchoredMenuItem {
  const AnchoredMenuItem({
    required this.value,
    required this.label,
    this.description,
    this.selected = false,
    this.enabled = true,
  });

  /// Stable id passed back through [AnchoredMenu.onSelected].
  final String value;

  /// Visible row label (resolve through the active locale at render time).
  final String label;

  /// Optional secondary line under [label].
  final String? description;

  /// Trailing check marker.
  final bool selected;

  /// Disabled rows render dimmed and do not fire [AnchoredMenu.onSelected].
  final bool enabled;
}

/// Anchored dropdown menu. Owns open/close state; [triggerBuilder] receives
/// the current open flag so the trigger can reflect hover/open chrome.
class AnchoredMenu extends StatefulWidget {
  const AnchoredMenu({
    super.key,
    required this.items,
    required this.onSelected,
    required this.aliases,
    required this.triggerBuilder,
    this.maxWidth = 240,
    this.menuMaxHeight = 320,
  });

  /// Rows to render; identity is [AnchoredMenuItem.value].
  final List<AnchoredMenuItem> items;

  /// Fired for an enabled row tap; the menu closes first.
  final ValueChanged<String> onSelected;

  /// Theme aliases (no literal colors).
  final DswAliases aliases;

  /// Trigger chrome; receives the open flag.
  final Widget Function(BuildContext context, bool open) triggerBuilder;

  /// Menu width cap (React list min-width 218 / max 360; picker menus 240).
  final double maxWidth;

  /// Height cap before internal scrolling.
  final double menuMaxHeight;

  @override
  State<AnchoredMenu> createState() => _AnchoredMenuState();
}

class _AnchoredMenuState extends State<AnchoredMenu> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _triggerKey = GlobalKey();
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _portal.show();
      setState(() => _open = true);
    }
  }

  void _close() {
    if (!_open) return;
    _portal.hide();
    setState(() => _open = false);
  }

  void _select(AnchoredMenuItem item) {
    _close();
    widget.onSelected(item.value);
  }

  @override
  void dispose() {
    if (_portal.isShowing) _portal.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: _buildTrigger(),
      ),
    );
  }

  Widget _buildTrigger() {
    return InkWell(
      key: _triggerKey,
      onTap: _toggle,
      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
      child: widget.triggerBuilder(context, _open),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    const double gap = 4;
    const double margin = 12;
    // Flip decision from the live trigger rect (React Menu side handling):
    // when the space below cannot fit an estimated panel and the space above
    // is larger, open upward.
    bool flip = false;
    double maxHeight = widget.menuMaxHeight;
    final RenderBox? triggerBox =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (triggerBox != null && triggerBox.hasSize) {
      final Offset pos = triggerBox.localToGlobal(Offset.zero);
      final double vh = MediaQuery.of(overlayContext).size.height;
      final double bottomEdge = pos.dy + triggerBox.size.height;
      final double spaceBelow = vh - bottomEdge - margin - gap;
      final double spaceAbove = pos.dy - margin - gap;
      const double estimatedHeight = 200;
      if (spaceBelow < estimatedHeight && spaceAbove > spaceBelow) {
        flip = true;
      }
      maxHeight = (flip ? spaceAbove : spaceBelow).clamp(
        96.0,
        widget.menuMaxHeight,
      );
    }
    return Stack(
      children: [
        // Outside pointer dismisses plainly (React document pointerdown port).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: flip ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: flip ? Alignment.bottomLeft : Alignment.topLeft,
          offset: flip ? Offset(0, -gap) : const Offset(0, gap),
          showWhenUnlinked: false,
          child: Material(
            elevation: 8,
            color: widget.aliases.specificMenu,
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _close,
              },
              child: Focus(
                autofocus: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxHeight,
                    maxWidth: widget.maxWidth,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: widget.items.length,
                    itemBuilder: (BuildContext ctx, int index) {
                      final AnchoredMenuItem item = widget.items[index];
                      return InkWell(
                        onTap: item.enabled ? () => _select(item) : null,
                        child: Opacity(
                          opacity: item.enabled ? 1 : 0.45,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        item.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: DswTokens.fontSizeS14,
                                          fontWeight: item.selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: widget.aliases.labelPrimary,
                                        ),
                                      ),
                                      if (item.description != null)
                                        Text(
                                          item.description!,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: DswTokens.fontSizeXxs12,
                                            color: widget.aliases.labelTertiary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (item.selected)
                                  Icon(
                                    Icons.check,
                                    size: 14,
                                    color: widget.aliases.stateBusinessPrimary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
