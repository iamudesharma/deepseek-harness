/// Trigger menu anchor for the composer-side seats — the MenuView slice this
/// workstream owns: renders the per-session controller's open menu (grouped
/// candidates) and routes taps back through [InputTriggerController.pick].
/// Closed menus render nothing, matching the React overlay contract.
///
/// Open content mounts through an [OverlayPortal] and tracks the composer
/// card's overlay-anchor strip with a [CompositedTransformTarget] on the
/// anchor plus a [CompositedTransformFollower] in the overlay — React floats
/// this menu over the transcript, bottom-anchored 4px above the card's top
/// edge and left-aligned to it (`MenuView.module.css .menu { position:
/// absolute; bottom: calc(100% + 4px); left: 0 }`). The follower keeps the
/// surface glued to the anchor through resize/scroll/reflow; only the
/// height clamp is measured once per open. A root-overlay mount keeps those
/// coordinates hit-testable in Flutter — content painted via negative-offset
/// translation outside the composer's boxes never receives taps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_provider.dart';
import '../input_trigger_controller.dart';
import '../input_trigger_service.dart';

/// Design cap on the menu list height (figma SLASH 39:26572 MenuDropdown,
/// mirrored from MenuView.tsx MAX_HEIGHT).
const double kInputMenuMaxHeight = 320;

/// Minimum usable dropdown height once the space above collapses.
const double _kMinMenuHeight = 96;

/// Gap between the menu's bottom edge and the composer card's top edge
/// (React `calc(100% + 4px)`).
const double _kMenuGap = 4;

/// Renders the active session's trigger menu from the bound registry.
class InputMenuAnchor extends ConsumerStatefulWidget {
  /// Creates the anchor.
  const InputMenuAnchor({super.key});

  @override
  ConsumerState<InputMenuAnchor> createState() => _InputMenuAnchorState();
}

class _InputMenuAnchorState extends ConsumerState<InputMenuAnchor> {
  final GlobalKey _anchorKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// Last synced visibility, so the post-frame portal sync runs only on
  /// transitions instead of after every menu notification.
  bool? _syncedVisible;

  void _syncPortal(bool visible) {
    if (_syncedVisible == visible) return;
    _syncedVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (visible && !_portal.isShowing) {
        _portal.show();
      } else if (!visible && _portal.isShowing) {
        _portal.hide();
      }
    });
  }

  @override
  void dispose() {
    _syncedVisible = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = activatedRegistry;
    final sessionId = ref.watch(currentSessionIdProvider)?.value;
    if (registry == null || sessionId == null) {
      _syncPortal(false);
      return _anchor();
    }
    final controller = registry.controllers[sessionId];
    if (controller == null || controller.isDisposed) {
      _syncPortal(false);
      return _anchor();
    }
    return ValueListenableBuilder(
      valueListenable: controller.menu,
      builder: (context, state, _) {
        _syncPortal(state.open && state.groups.isNotEmpty);
        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (BuildContext overlayContext) =>
              _buildFloatingMenu(overlayContext, controller),
          // Zero-size measurement box riding the composer's overlay-anchor
          // strip (card top edge); the floating menu follows its rect live.
          child: _anchor(),
        );
      },
    );
  }

  /// The CompositedTransformTarget every open menu aligns to — the composer
  /// card's top-left corner region (the overlay-anchor strip).
  Widget _anchor() {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(key: _anchorKey),
    );
  }

  /// The open candidate menu, floated fully ABOVE the composer card's top
  /// edge (React `bottom: calc(100% + 4px)`), left-aligned to it, height
  /// clamped to the space above the card. The follower repositions on every
  /// anchor move without a rebuild.
  Widget _buildFloatingMenu(
    BuildContext overlayContext,
    InputTriggerController controller,
  ) {
    // Height + width clamp: the design cap minus whatever viewport the
    // anchor leaves above itself (React useAnchoredMaxHeight clamps to the
    // space above the composer; the menu never flips below), and the width
    // cap never exceeds the card (`max-width: min(537px, 100%)`).
    double maxHeight = kInputMenuMaxHeight;
    double maxWidth = 537;
    final RenderBox? box =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final Offset anchor = box.localToGlobal(Offset.zero);
      final MediaQueryData media = MediaQuery.of(overlayContext);
      maxHeight = (anchor.dy - _kMenuGap - 8).clamp(
        _kMinMenuHeight,
        kInputMenuMaxHeight,
      );
      if (media.size.height < anchor.dy) maxHeight = _kMinMenuHeight;
      if (box.size.width > 0) maxWidth = math.min(537, box.size.width);
    }
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Outside tap dismisses plainly (the click's own target is not acted
          // on) — React's document-level pointerdown listener port.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller.dismiss,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -_kMenuGap),
              showWhenUnlinked: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight,
                  maxWidth: maxWidth,
                ),
                child: Container(
                  key: const ValueKey('input-menu-surface'),
                  decoration: BoxDecoration(
                    color: Theme.of(overlayContext)
                        .colorScheme
                        .surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(overlayContext).dividerColor
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: controller.menu,
                    builder: (context, state, _) {
                      if (!state.open || state.groups.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final group in state.groups)
                            if (group.status == 'ready') ...[
                              if (group.showGroupTitle)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    6,
                                    12,
                                    2,
                                  ),
                                  child: Text(
                                    group.source,
                                    style: Theme.of(overlayContext)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(overlayContext)
                                              .hintColor,
                                        ),
                                  ),
                                ),
                              for (var i = 0; i < group.items.length; i++)
                                _MenuRow(
                                  title: group.items[i].name,
                                  subtitle:
                                      group.items[i].description ??
                                      group.items[i].hint,
                                  selected:
                                      state.highlight != null &&
                                      state.highlight!.source == group.source &&
                                      state.highlight!.index == i,
                                  onTap: () => controller.pick(group.source, i),
                                ),
                            ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // GestureDetector, not InkWell: rows must not move the primary focus off
    // the textarea (React combobox pattern — focus never leaves the field).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: selected
              ? Theme.of(context).focusColor.withValues(alpha: 0.3)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
