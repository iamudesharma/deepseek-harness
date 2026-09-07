/// The popupSelect overlay — Flutter port of
/// `packages/client/ui-commands/src/client/PopupSelectView.tsx`: renders the
/// session shell's state into the `conversation.input.overlay` anchor.
/// Closed shells render nothing; ready shells render the search field, the
/// filtered option rows, and (when gated) the confirmation card; pending and
/// failed states render their lifecycle rows. Selection routes back through
/// the controller's single-flight `select`.
///
/// Open shells mount through an [OverlayPortal] and track the composer card's
/// overlay-anchor strip with a [CompositedTransformTarget] on the anchor plus
/// a [CompositedTransformFollower] in the overlay (React `PopupSelectView`
/// floats over the transcript, bottom-anchored 4px above the card's top edge
/// and left-aligned to it). The follower keeps the surface glued to the
/// anchor through resize/scroll/reflow. A root-overlay mount keeps those
/// coordinates hit-testable in Flutter, which a negative-offset translation
/// inside the composer never is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../command_service.dart';
import '../popup_select.dart';

CommandUiService? _activatedService;

/// Binds the commandUi service the overlay resolves per session (plugin
/// activation; cleared on teardown).
void bindActivatedCommandUi(CommandUiService? service) {
  _activatedService = service;
}

/// Gap between the shell's bottom edge and the composer card's top edge
/// (React popup placement).
const double _kShellGap = 4;

/// Minimum usable dropdown height once the space above collapses.
const double _kMinShellHeight = 96;

/// Renders the active session's popupSelect shell. Production mounts resolve
/// the controller through the bound service + current session; tests pass
/// [controller] directly.
class PopupSelectOverlay extends ConsumerStatefulWidget {
  /// Creates the overlay.
  const PopupSelectOverlay({super.key, this.controller});

  /// Test injection: render this controller instead of resolving one.
  final PopupSelectController<SessionId>? controller;

  @override
  ConsumerState<PopupSelectOverlay> createState() => _PopupSelectOverlayState();
}

class _PopupSelectOverlayState extends ConsumerState<PopupSelectOverlay> {
  final GlobalKey _anchorKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// Last synced visibility, so the post-frame portal sync runs only on
  /// transitions instead of after every state notification.
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
  Widget build(BuildContext context) {
    final WidgetRef ref = this.ref;
    var popup = widget.controller;
    if (popup == null) {
      final service = _activatedService;
      final sessionId = ref.watch(currentSessionIdProvider)?.value;
      if (service == null || sessionId == null) {
        _syncPortal(false);
        return _anchor();
      }
      popup = service.popupOf(SessionId(sessionId));
    }
    return ValueListenableBuilder(
      valueListenable: popup.state,
      builder: (context, state, _) {
        _syncPortal(state.open);
        return OverlayPortal(
          key: ValueKey(popup),
          controller: _portal,
          overlayChildBuilder: (BuildContext overlayContext) =>
              _buildFloatingShell(overlayContext, popup!),
          // Zero-size measurement box riding the composer's overlay-anchor
          // strip (card top edge); the floating shell follows its rect live.
          child: _anchor(),
        );
      },
    );
  }

  /// The CompositedTransformTarget every open shell aligns to.
  Widget _anchor() {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(key: _anchorKey),
    );
  }

  /// The open shell, floated fully ABOVE the composer card's top edge,
  /// left-aligned to it (React `PopupSelectView` placement), height clamped
  /// to the space above the card. The follower repositions on every anchor
  /// move without a rebuild.
  Widget _buildFloatingShell(
    BuildContext overlayContext,
    PopupSelectController<SessionId> controller,
  ) {
    double maxHeight = 360;
    final RenderBox? box =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final Offset anchor = box.localToGlobal(Offset.zero);
      maxHeight = (anchor.dy - _kShellGap - 8).clamp(_kMinShellHeight, 360.0);
    }
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Outside tap dismisses plainly — React's document-level listener;
          // no consumption, no focus juggling.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.dismiss(),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -_kShellGap),
              showWhenUnlinked: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight,
                  maxWidth: 460,
                ),
                child: Container(
                  key: const ValueKey('popup-select'),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _ShellBody(controller: controller),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellBody extends StatelessWidget {
  const _ShellBody({required this.controller});

  final PopupSelectController<SessionId> controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.state,
      builder: (context, state, _) {
        // The risk gate replaces the picker while pending.
        if (state.confirming != null)
          return _ConfirmationCard(controller: controller);
        final rows = filterOptions(state.options, state.search);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                key: const ValueKey('popup-search'),
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: state.command == null ? null : '/${state.command}',
                  border: const OutlineInputBorder(),
                ),
                onChanged: controller.setSearch,
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: state.status == PopupStatus.pending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Loading…'),
                        ],
                      ),
                    )
                  : state.status == PopupStatus.failed
                  ? _FailedRow(controller: controller)
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (context, index) => _OptionRow(
                        controller: controller,
                        index: index,
                        option: rows[index],
                        active: index == state.active,
                      ),
                    ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  state.error!,
                  key: const ValueKey('popup-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.controller,
    required this.index,
    required this.option,
    required this.active,
  });

  final PopupSelectController<SessionId> controller;
  final int index;
  final SelectOption option;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => controller.select(index),
      onHover: (hovering) => hovering ? controller.highlight(index) : null,
      child: Container(
        color: active
            ? Theme.of(context).focusColor.withValues(alpha: 0.3)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(option.label, style: Theme.of(context).textTheme.bodyMedium),
            if (option.detail != null)
              Text(
                option.detail!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.controller});

  final PopupSelectController<SessionId> controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Options failed to load',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            key: const ValueKey('popup-retry'),
            onPressed: controller.retry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({required this.controller});

  final PopupSelectController<SessionId> controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final gate = state.confirming!.confirmation!;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gate.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                gate.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                children: [
                  Checkbox(
                    key: const ValueKey('popup-acknowledge'),
                    value: state.acknowledged,
                    onChanged: (v) => controller.acknowledge(v ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(gate.acknowledgeLabel)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: controller.cancelConfirmation,
                    child: Text(gate.cancelLabel),
                  ),
                  FilledButton(
                    key: const ValueKey('popup-confirm'),
                    onPressed: state.acknowledged ? controller.confirm : null,
                    child: Text(gate.confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
