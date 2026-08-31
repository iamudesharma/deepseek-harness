import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../platform/drag_drop.dart';
import 'drop_overlay.dart';

/// Document-level file-drop scope — the widget half of the
/// `ComposerAttachments` port.
///
/// Wraps a conversation surface so a file drag anywhere over it drives the
/// shared [DragDropController]: enter/leave pairs maintain the depth counter,
/// a drop runs the batch pre-check and forwards accepted files to
/// [onAddImages], and the [DropOverlay] renders while `dragActive`.
///
/// The overlay is decoration only ([DropOverlay] ignores pointers), so drag
/// targeting stays on the page below — matching React's document-level
/// listeners with `pointer-events: none` on the mask.
class DocumentDropScope extends StatefulWidget {
  /// Creates the scope.
  const DocumentDropScope({
    super.key,
    required this.controller,
    required this.onAddImages,
    required this.child,
    this.enabled = true,
  });

  /// Shared controller owning depth, gate, limits, and pre-check order.
  final DragDropController controller;

  /// Authoritative intake for accepted batches; returns a rejection message
  /// or `null`. Kept beside the controller (not inside it) so the composer
  /// owns conversion into draft attachments.
  final String? Function(List<DroppedFile> files) onAddImages;

  /// Wrapped surface.
  final Widget child;

  /// Whether document drops are enabled at all — the caller can bind this to
  /// a modal/front-layer signal. Combined with the `ModalRoute.isCurrent`
  /// check in `build` so a dialog or overlay on top disables drops.
  final bool enabled;

  @override
  State<DocumentDropScope> createState() => _DocumentDropScopeState();
}

class _DocumentDropScopeState extends State<DocumentDropScope> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(DocumentDropScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    // The caller owns the controller's lifecycle; this scope only listens.
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final DragDropController controller = widget.controller;
    // Modal/front-layer guard: a pushed Dialog/ModalRoute makes the underlying
    // scope's route non-current; drops must not be accepted while a modal is
    // on top (mirrors React disabling document listeners behind modals).
    final bool isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    final bool effectiveEnabled = widget.enabled && isTopRoute;
    // When disabled, show child only — no DropTarget listeners, no overlay.
    if (!effectiveEnabled) {
      // Reset any stale drag state while disabled so re-enabling starts clean.
      if (controller.dragActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) => controller.reset());
      }
      return widget.child;
    }
    return DropTarget(
      onDragEntered: (_) => controller.dragEntered(),
      onDragExited: (_) => controller.dragLeft(),
      onDragDone: (DropDoneDetails details) async {
        if (!effectiveEnabled) return;
        final List<DroppedFile> mapped = [];
        for (final file in details.files) {
          final int len = await file.length().catchError((_) => 0);
          Uint8List? bytes;
          try {
            bytes = await file.readAsBytes();
          } catch (_) {
            bytes = null;
          }
          mapped.add(
            DroppedFile(
              name: file.name,
              mimeType: file.mimeType ?? '',
              size: len,
              path: file.path,
              bytes: bytes,
            ),
          );
        }
        controller.dropped(mapped);
      },
      child: Stack(
        children: <Widget>[
          widget.child,
          if (controller.dragActive)
            Positioned.fill(
              child: DropOverlay(
                disabled: !controller.canAcceptDrop,
                limitsText: controller.limitsText,
              ),
            ),
        ],
      ),
    );
  }
}
