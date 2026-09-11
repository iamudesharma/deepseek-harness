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
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_provider.dart';
import '../input_trigger_controller.dart';
import '../input_trigger_service.dart';
import '../locales.dart';
import '../menu_reducer.dart' show MenuState, menuClosed;
import '../trigger_source.dart' show InputTriggerCrumb, PickAction;

/// Design cap on the menu list height (figma SLASH 39:26572 MenuDropdown,
/// mirrored from MenuView.tsx MAX_HEIGHT).
const double kInputMenuMaxHeight = 320;

/// Minimum usable dropdown height once the space above collapses.
const double _kMinMenuHeight = 96;

/// Gap between the menu's bottom edge and the composer card's top edge
/// (React `calc(100% + 4px)`).
const double _kMenuGap = 4;

/// Keys of every mounted composer card — one per composer instance,
/// registered by the card's own state.
/// The outside-close barrier consults these at tap time instead of sharing a
/// single GlobalKey: two composers can co-mount (route transitions during
/// session switches), and a shared key throws `Multiple widgets used the
/// same GlobalKey` on every build while duplicated.
final Set<GlobalKey> _composerCardKeys = <GlobalKey>{};

/// Registers one composer card's key (card state initState).
void registerComposerCard(GlobalKey key) {
  _composerCardKeys.add(key);
}

/// Unregisters one composer card's key (card state dispose).
void unregisterComposerCard(GlobalKey key) {
  _composerCardKeys.remove(key);
}

/// Never-notifying menu store for frames without a live session controller —
/// keeps the portal element (and its controller pairing) mounted instead of
/// remounting it across registry/session gaps (see build).
final ValueNotifier<MenuState> _emptyMenu = ValueNotifier<MenuState>(
  menuClosed,
);

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
    final InputTriggerController? resolved = (registry == null ||
            sessionId == null)
        ? null
        : registry.controllers[sessionId];
    final InputTriggerController? controller =
        resolved != null && !resolved.isDisposed ? resolved : null;
    // The portal element NEVER unmounts/remounts across these branches (same
    // position, same controller): tearing it down orphans the controller
    // pairing (a later dispose nulls a successor element's claim) and the
    // next GlobalKey-driven card move trips OverlayPortal's attach
    // assertion (`_attachTarget == this` in activate()). Visibility rides
    // `_syncPortal` alone; the overlay builds nothing while closed.
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (BuildContext overlayContext) =>
          _buildFloatingMenu(overlayContext, controller),
      // Zero-size measurement box riding the composer's overlay-anchor
      // strip (card top edge); the floating menu follows its rect live.
      child: ValueListenableBuilder(
        valueListenable: controller?.menu ?? _emptyMenu,
        builder: (context, state, _) {
          _syncPortal(
            controller != null && state.open && state.groups.isNotEmpty,
          );
          return _anchor();
        },
      ),
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
    InputTriggerController? controller,
  ) {
    // No live controller (registry/session gap): the portal stays mounted
    // but empty — remounting it would orphan the controller pairing (see
    // build). Hidden anyway via _syncPortal(false).
    if (controller == null) return const SizedBox.shrink();
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
          // on) — React's document-level pointerdown listener port. The hole
          // refuses hits landing inside the composer card (textarea caret
          // moves, bottom bar, `+` launcher — React's `[data-composer-card]`
          // exemption), so those taps reach the card's own recognizers
          // instead of competing with this one in the arena: a full-screen
          // detector would always win and starve the `+` button beneath it.
          // The menu surface above wins its own taps first, so a row pick
          // still settles before this no-op dismiss.
          Positioned.fill(
            child: _CardHole(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (_) => controller.dismiss(),
              ),
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
                    // React `.menu` radius 20; item 10; crumb 6; keycap+drill 4.
                    borderRadius: BorderRadius.circular(20),
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
                      // Locale seat captured from the anchor's ref (this
                      // builder's context is the overlay subtree): unknown
                      // source names miss the dictionary and render raw,
                      // exactly like React's open-ended `t(group.source)`.
                      final Translate t = ref.bindLocale(kSlashMenuNamespace);
                      return ValueListenableBuilder(
                        valueListenable: controller.headers,
                        builder: (context, crumbs, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Breadcrumb headers sit outside the listbox (React:
                            // `nav.crumbs` above `div.viewport[role=listbox]` —
                            // a header is not an option).
                            for (final group in state.groups)
                              if (crumbs[group.source] != null)
                                _CrumbNav(
                                  crumbs: crumbs[group.source]!,
                                  crumbsAria: t('crumbs.aria'),
                                  overlayContext: overlayContext,
                                  onCrumb: (index) => controller.pickCrumb(
                                    group.source,
                                    index,
                                  ),
                                ),
                            Flexible(
                              child: Semantics(
                                // React `role=listbox` aria-label.
                                label: t('suggestions.aria'),
                                container: true,
                                child: ListView(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.all(4),
                                  children: [
                                    for (final group in state.groups)
                                      // A settled-empty group renders nothing
                                      // (React returns null for it); every
                                      // other group keeps its title plus either
                                      // the pending skeletons (no items yet) or
                                      // the rows — including stale rows
                                      // mid-refinement, fenced from picks by
                                      // the controller's ready check.
                                      if (group.status == 'ready' &&
                                          group.items.isEmpty)
                                        const SizedBox.shrink()
                                      else ...[
                                        if (group.showGroupTitle)
                                          _GroupTitle(
                                            text: t(group.source),
                                            overlayContext: overlayContext,
                                          ),
                                        if (group.status != 'ready' &&
                                            group.items.isEmpty) ...[
                                          const _SkeletonRow(
                                            widthFactor: 0.32,
                                          ),
                                          const _SkeletonRow(
                                            widthFactor: 0.48,
                                          ),
                                        ] else
                                          for (var i = 0;
                                              i < group.items.length;
                                              i++) ...[
                                            // Section break inside one group
                                            // (React `item.section !==
                                            // items[index-1]?.section`).
                                            if (group.items[i].section !=
                                                    null &&
                                                (i == 0 ||
                                                    group.items[i - 1]
                                                            .section !=
                                                        group.items[i]
                                                            .section))
                                              _SectionTitle(
                                                text: group.items[i].section!,
                                                overlayContext:
                                                    overlayContext,
                                              ),
                                            _MenuRow(
                                              title: group.items[i].name,
                                              // React shows description only;
                                              // `hint` is the claim ghost, not
                                              // a menu subtitle (service
                                              // filtering owns inline
                                              // visibility).
                                              subtitle: group
                                                  .items[i]
                                                  .description,
                                              icon: group.items[i].icon,
                                              drill:
                                                  group.items[i].drill ==
                                                  true,
                                              selected:
                                                  state.highlight != null &&
                                                  state.highlight!.source ==
                                                      group.source &&
                                                  state.highlight!.index ==
                                                      i,
                                              drillHint: t('drill.hint'),
                                              drillKey: t('drill.key'),
                                              drillAria: t('drill.aria'),
                                              overlayContext: overlayContext,
                                              onTap: () => controller.pick(
                                                group.source,
                                                i,
                                              ),
                                              onDrill: () => controller.pick(
                                                group.source,
                                                i,
                                                action: PickAction.drill,
                                              ),
                                              // mousemove, not mouseenter: real
                                              // pointer motion moves the shared
                                              // highlight (React MenuView) —
                                              // guarded so a resting pointer
                                              // never steals keyboard moves
                                              // back.
                                              onHover: () => controller.hover(
                                                group.source,
                                                i,
                                              ),
                                            ),
                                          ],
                                      ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
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

/// Whether a global position lands inside the composer card, resolved
/// through the shared card key. Unknown card (a surface that never tagged
/// one, or a detached tree) reports outside, so dismissal falls back to
/// close-on-any-tap there.
bool pointInComposerCard(Offset globalPosition) {
  for (final GlobalKey key in _composerCardKeys) {
    final RenderObject? cardObject = key.currentContext?.findRenderObject();
    if (cardObject is! RenderBox || !cardObject.hasSize) continue;
    late final Offset cardTopLeft;
    try {
      cardTopLeft = cardObject.localToGlobal(Offset.zero);
    } catch (_) {
      continue;
    }
    if (Rect.fromLTWH(
      cardTopLeft.dx,
      cardTopLeft.dy,
      cardObject.size.width,
      cardObject.size.height,
    ).contains(globalPosition)) {
      return true;
    }
  }
  return false;
}

/// Barrier segment that refuses hits inside the composer card: hit-testing
/// false keeps this subtree's recognizer out of the arena, so the card's
/// own buttons and field win their taps (a competing full-screen detector
/// would always win and starve them). Everything outside the card
/// hit-tests normally into the dismiss detector below.
class _CardHole extends SingleChildRenderObjectWidget {
  const _CardHole({required super.child});

  @override
  RenderCardHole createRenderObject(BuildContext context) => RenderCardHole();
}

/// Render proxy hiding the composer-card region from hit testing (see
/// [_CardHole]). Public (no underscore) for the signature override only;
/// constructed solely by [_CardHole].
class RenderCardHole extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    late final Offset globalPosition;
    try {
      globalPosition = localToGlobal(position);
    } catch (_) {
      return super.hitTest(result, position: position);
    }
    if (pointInComposerCard(globalPosition)) return false;
    return super.hitTest(result, position: position);
  }
}

/// In-group section break (React `.sectionTitle`: 12/18 w500 tertiary,
/// padding 6/10/2 — distinct from the group title above).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.overlayContext});

  /// Section label carried by the items themselves (never localized).
  final String text;

  /// Overlay context for theme lookup.
  final BuildContext overlayContext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Text(
        text,
        style: Theme.of(overlayContext).textTheme.labelSmall?.copyWith(
          fontSize: 12,
          height: 18 / 12,
          fontWeight: FontWeight.w500,
          color: Theme.of(overlayContext).hintColor,
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.text, required this.overlayContext});

  /// Localized source name (raw name when the dictionary misses it).
  final String text;

  /// Overlay context for theme lookup.
  final BuildContext overlayContext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Text(
        text,
        style: Theme.of(overlayContext).textTheme.labelSmall?.copyWith(
          color: Theme.of(overlayContext).hintColor,
        ),
      ),
    );
  }
}

/// One pending placeholder bar (React MenuView skeleton rows).
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.widthFactor});

  /// Bar width as a fraction of the row (React uses 32% / 48%).
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('input-menu-skeleton'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: Theme.of(context).hintColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
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
    required this.onHover,
    required this.onDrill,
    required this.drill,
    required this.drillHint,
    required this.drillKey,
    required this.drillAria,
    required this.overlayContext,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Parks the shared highlight on this row (React `onHover`).
  final VoidCallback onHover;

  /// Drills this row in place without settling it (React chevron mousedown).
  final VoidCallback onDrill;

  /// Whether the candidate offers the drill action (React `item.drill`).
  final bool drill;

  /// Localized drill hint/key/aria copy (React `drill.hint/key/aria`).
  final String drillHint;
  final String drillKey;
  final String drillAria;

  /// Overlay context for theme lookup.
  final BuildContext overlayContext;

  /// Reference domain glyph (`session` | `file` | `folder`, React
  /// `ReferenceIcon`); null renders no leading glyph, exactly like React's
  /// `item.icon === undefined` branch (`/` rows carry none).
  final String? icon;

  /// Closest Material glyph for one React `ReferenceIconKind`.
  static IconData? iconForKind(String? kind) => switch (kind) {
        'folder' => Icons.folder_outlined,
        'file' => Icons.insert_drive_file_outlined,
        'session' => Icons.history_outlined,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    // GestureDetector, not InkWell: rows must not move the primary focus off
    // the textarea (React combobox pattern — focus never leaves the field).
    final IconData? glyph = iconForKind(icon);
    // The trailing drill seat shows only while the drillable row holds the
    // shared highlight (React `.item.active .drillHint* { display }`).
    final bool showDrill = drill && selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // Guarded like React's `active ? undefined`: a resting pointer never
      // steals the highlight back from keyboard moves.
      onHover: selected ? null : (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // mousedown, not click: the textarea keeps focus (combobox pattern).
        onTapDown: (_) => onTap(),
        // React `.item`: single row, center-aligned, 8px gap, min-height 40,
        // padding 8/10, radius 10; name caps at 40% with ellipsis, the
        // description takes the rest (tertiary, ellipsis).
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(overlayContext).focusColor.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (glyph != null) ...[
                Icon(
                  glyph,
                  size: 16,
                  color: Theme.of(overlayContext).hintColor,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                flex: 4,
                child: Text(
                  title,
                  style: Theme.of(overlayContext).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: Text(
                    subtitle!,
                    style: Theme.of(
                      overlayContext,
                    ).textTheme.bodySmall?.copyWith(
                      color: Theme.of(overlayContext).hintColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (showDrill) ...[
                const SizedBox(width: 4),
                // Trailing seat: Tab keycap hint plus drill chevron (React
                // `.trailing`: inline-flex, 4px gap, margin-left auto).
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          drillHint,
                          style: TextStyle(
                            fontSize: 11,
                            height: 18 / 11,
                            color: Theme.of(overlayContext).hintColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            overlayContext,
                          ).focusColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          drillKey,
                          style: TextStyle(
                            fontSize: 11,
                            height: 18 / 11,
                            color: Theme.of(overlayContext).hintColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _DrillButton(
                        tooltip: drillAria,
                        overlayContext: overlayContext,
                        onDrill: onDrill,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Descent affordance: a quiet 20x20 chevron that brightens on its own hover
/// (React `.drill`: caption at rest, hover-bg + primary on hover, radius 4).
class _DrillButton extends StatefulWidget {
  const _DrillButton({
    required this.tooltip,
    required this.overlayContext,
    required this.onDrill,
  });

  final String tooltip;
  final BuildContext overlayContext;
  final VoidCallback onDrill;

  @override
  State<_DrillButton> createState() => _DrillButtonState();
}

class _DrillButtonState extends State<_DrillButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(widget.overlayContext);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // mousedown so the composer keeps focus, same as the row; the nested
        // arena win keeps the row's settling pick out of it (React
        // stopPropagation parity).
        onTapDown: (_) => widget.onDrill(),
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: Container(
            key: const ValueKey('input-menu-drill'),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hovering
                  ? theme.focusColor.withValues(alpha: 0.3)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.chevron_right,
              size: 14,
              color: _hovering
                  ? theme.colorScheme.onSurface
                  : theme.hintColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Breadcrumb header of a drilled source, pinned above the scrolling list
/// (React `nav.crumbs`: flex-wrap, 2px gap, padding 4/4/6, 0.5px l1 divider;
/// crumb radius 6, tertiary at rest, primary when current).
class _CrumbNav extends StatelessWidget {
  const _CrumbNav({
    required this.crumbs,
    required this.crumbsAria,
    required this.overlayContext,
    required this.onCrumb,
  });

  final List<InputTriggerCrumb> crumbs;
  final String crumbsAria;
  final BuildContext overlayContext;
  final void Function(int index) onCrumb;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(overlayContext);
    return Semantics(
      container: true,
      label: crumbsAria,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 0.5,
              color: theme.dividerColor.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              if (i > 0)
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: theme.hintColor,
                ),
              _CrumbButton(
                label: crumbs[i].label,
                current: crumbs[i].current,
                overlayContext: overlayContext,
                // mousedown, not click: the composer keeps focus, same as a
                // row (React `onMouseDown` parity).
                onTapDown: crumbs[i].current ? null : () => onCrumb(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CrumbButton extends StatefulWidget {
  const _CrumbButton({
    required this.label,
    required this.current,
    required this.overlayContext,
    required this.onTapDown,
  });

  final String label;
  final bool current;
  final BuildContext overlayContext;
  final VoidCallback? onTapDown;

  @override
  State<_CrumbButton> createState() => _CrumbButtonState();
}

class _CrumbButtonState extends State<_CrumbButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(widget.overlayContext);
    final bool interactive = !widget.current && widget.onTapDown != null;
    final Color text = widget.current
        ? theme.colorScheme.onSurface
        : _hovering
        ? theme.colorScheme.onSurface
        : theme.hintColor;
    return MouseRegion(
      cursor: interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: interactive ? (_) => setState(() => _hovering = true) : null,
      onExit: interactive ? (_) => setState(() => _hovering = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (_) => widget.onTapDown!() : null,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _hovering && interactive
                ? theme.focusColor.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              height: 18 / 12,
              color: text,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
