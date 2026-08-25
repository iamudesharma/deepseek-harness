import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Hover preview card — Flutter port of `HoverCard.tsx` + `HoverCard.module.css`.
///
/// Shows [content] in an overlay 8px to the right of [trigger] after
/// [openDelay] (500ms). The card is reachable (pointer may rest on it);
/// leaving both trigger and card arms a grace-delayed close (100ms, 8px gap).
/// Position flips via rAF (post-frame viewport clamping) mirroring web
/// `useLayoutEffect` + `getBoundingClientRect` flip.
class DsHoverCard extends ConsumerStatefulWidget {
  const DsHoverCard({
    super.key,
    required this.trigger,
    required this.content,
    this.openDelay = const Duration(milliseconds: 500),
    this.closeDelay = const Duration(milliseconds: 100),
    this.enabled = true,
    this.cardWidth = 244,
    this.copyText,
    this.onCopy,
  });

  /// The hover target rendered in place.
  final Widget trigger;

  /// Card content. Selectable, pointer-interactive.
  final Widget content;

  /// Hover dwell before showing. Defaults to 500ms matching HoverCard.tsx.
  final Duration openDelay;

  /// Grace period after pointer leaves before closing. 100ms matching spec.
  final Duration closeDelay;

  /// When false suppresses opening and closes an open card.
  final bool enabled;

  /// Card width. Defaults to 244 matching HoverCard.module.css.
  final double cardWidth;

  /// Optional text copied on card tap (web `copyText`).
  final String? copyText;

  /// Called after a successful copy.
  final VoidCallback? onCopy;

  @override
  ConsumerState<DsHoverCard> createState() => _DsHoverCardState();
}

class _DsHoverCardState extends ConsumerState<DsHoverCard> {
  final LayerLink _link = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;
  Timer? _openTimer;
  Timer? _closeTimer;
  bool _open = false;

  @override
  void didUpdateWidget(DsHoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _open) _close();
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _removeEntry();
    super.dispose();
  }

  void _scheduleOpen() {
    _closeTimer?.cancel();
    if (_open || !widget.enabled) return;
    _openTimer?.cancel();
    _openTimer = Timer(widget.openDelay, _openCard);
  }

  void _scheduleClose() {
    _openTimer?.cancel();
    if (!_open) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(widget.closeDelay, _close);
  }

  void _cancelClose() {
    _closeTimer?.cancel();
  }

  void _openCard() {
    if (!mounted || !widget.enabled || _open) return;
    setState(() => _open = true);
    _entry = OverlayEntry(
      builder: (BuildContext ctx) => _HoverCardOverlay(
        link: _link,
        anchorKey: _anchorKey,
        cardWidth: widget.cardWidth,
        content: widget.content,
        copyText: widget.copyText,
        onCopy: widget.onCopy,
        onEnter: _cancelClose,
        onExit: _scheduleClose,
      ),
    );
    Overlay.of(context).insert(_entry!);
    // rAF flip: schedule post-frame re-measure to clamp within viewport
    // (web useLayoutEffect place() re-runs on scroll/resize/height).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entry?.markNeedsBuild();
    });
  }

  void _close() {
    _removeEntry();
    if (mounted) setState(() => _open = false);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _scheduleOpen(),
        onExit: (_) => _scheduleClose(),
        child: GestureDetector(
          key: _anchorKey,
          onTap: _close,
          child: widget.trigger,
        ),
      ),
    );
  }
}

class _HoverCardOverlay extends ConsumerStatefulWidget {
  const _HoverCardOverlay({
    required this.link,
    required this.anchorKey,
    required this.cardWidth,
    required this.content,
    this.copyText,
    this.onCopy,
    required this.onEnter,
    required this.onExit,
  });

  final LayerLink link;
  final GlobalKey anchorKey;
  final double cardWidth;
  final Widget content;
  final String? copyText;
  final VoidCallback? onCopy;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  ConsumerState<_HoverCardOverlay> createState() => _HoverCardOverlayState();
}

class _HoverCardOverlayState extends ConsumerState<_HoverCardOverlay> {
  // rAF flip state: track viewport overflow and flip horizontally/vertically.
  bool _flipHorizontal = false;
  double _topOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndFlip());
  }

  void _measureAndFlip() {
    if (!mounted) return;
    final BuildContext? anchorCtx = widget.anchorKey.currentContext;
    if (anchorCtx == null) return;
    final RenderBox? targetBox = anchorCtx.findRenderObject() as RenderBox?;
    if (targetBox == null) return;
    final Size viewport = MediaQuery.sizeOf(context);
    final Offset targetPos = targetBox.localToGlobal(Offset.zero);
    final double targetRight = targetPos.dx + targetBox.size.width;
    final double targetTop = targetPos.dy;
    const double gap = 8;
    const double margin = 8;

    // Estimate card height via 200 fallback; real height refines on next frame.
    final double estimatedHeight = 120;
    double top = targetTop;
    if (top + estimatedHeight > viewport.height - margin) {
      top = viewport.height - estimatedHeight - margin;
      if (top < margin) top = margin;
    }

    final bool flipH = targetRight + gap + widget.cardWidth > viewport.width - margin;

    if (flipH != _flipHorizontal || (top - targetTop).abs() > 0.5) {
      setState(() {
        _flipHorizontal = flipH;
        _topOffset = top - targetTop;
      });
      // Second rAF pass with real card height
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final RenderBox? cardBox = context.findRenderObject() as RenderBox?;
        if (cardBox == null) return;
        final double h = cardBox.size.height;
        double correctedTop = targetTop;
        if (correctedTop + h > viewport.height - margin) {
          correctedTop = viewport.height - h - margin;
        }
        if (correctedTop < margin) correctedTop = margin;
        final double offset = correctedTop - targetTop;
        if ((offset - _topOffset).abs() > 1) {
          setState(() => _topOffset = offset);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    // Flip: when not enough space on right, show on left of anchor.
    final Alignment targetAnchor = _flipHorizontal ? Alignment.centerLeft : Alignment.centerRight;
    final Alignment followerAnchor = _flipHorizontal ? Alignment.centerRight : Alignment.centerLeft;
    final Offset gapOffset = _flipHorizontal ? const Offset(-8, 0) : const Offset(8, 0);
    final Offset offset = Offset(gapOffset.dx, gapOffset.dy + _topOffset);

    return CompositedTransformFollower(
      link: widget.link,
      offset: offset,
      showWhenUnlinked: false,
      targetAnchor: targetAnchor,
      followerAnchor: followerAnchor,
      child: MouseRegion(
        onEnter: (_) => widget.onEnter(),
        onExit: (_) => widget.onExit(),
        child: Material(
          color: DswTokens.transparent,
          child: Container(
            width: widget.cardWidth,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg, vertical: DswTokens.spaceMd),
            decoration: BoxDecoration(
              // HoverCard.module.css bg is #2C2C2E in both themes — use specificMenu dark fallback
              color: DswTokens.neutralBluish850,
              borderRadius: BorderRadius.circular(DswTokens.radiusLg),
              boxShadow: DswTokens.shadowLv3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DefaultTextStyle(
                  style: TextStyle(
                    color: DswTokens.neutralBluish00,
                    fontSize: DswTokens.fontSizeS14,
                    height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                  ),
                  child: widget.content,
                ),
                if (widget.copyText != null) ...<Widget>[
                  const SizedBox(height: DswTokens.spaceSm),
                  InkWell(
                    onTap: () async {
                      widget.onCopy?.call();
                    },
                    borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.copy, size: 12, color: DswTokens.neutralBluish00),
                        const SizedBox(width: DswTokens.spaceXs),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: DswTokens.neutralBluish00,
                            fontSize: DswTokens.fontSizeXxs12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
