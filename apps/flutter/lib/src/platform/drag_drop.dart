import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Byte-size display shared by the drop overlay's limits line and intake
/// rejections — single source (re-exported by `attachment_limits.dart`).
String imageSizeText(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${bytes}B';
}

/// One file delivered by a document-level drop, platform-normalized.
///
/// Web delivers `DataTransfer.files` entries (name/type/size, no path);
/// macOS delivers `desktop_drop` `XFile`s (name/path/size, mime derived
/// from the extension). Both collapse to this shape — the intake path
/// never sees a platform type.
class DroppedFile {
  /// Creates a dropped-file record.
  const DroppedFile({
    required this.name,
    required this.mimeType,
    required this.size,
    this.path,
    this.bytes,
  });

  /// File name as delivered by the platform.
  final String name;

  /// Mime type (`image/png`); empty string when the platform cannot tell.
  final String mimeType;

  /// Size in bytes.
  final int size;

  /// Local path (macOS) or blob reference (web); `null` when unavailable.
  final String? path;

  /// Raw bytes when available (file_picker `bytes` or `XFile.readAsBytes`).
  ///
  /// Present for web picks and for desktop drops when the drop handler read
  /// the file. `null` means the bytes must be read lazily from [path] at
  /// submit time (native) — the ComposerAttachment seam handles that fallback.
  final Uint8List? bytes;
}

/// Host-declared image intake limits — the Dart slice of the
/// `imageLimits` projection key (`apiproxy` sessions contract).
///
/// `null` limits mean the host has not declared any: the pre-check then
/// defers entirely to the authoritative intake, exactly like React's
/// `imageLimits === undefined` branch.
class ImageLimits {
  /// Creates declared limits.
  const ImageLimits({
    required this.mediaTypes,
    required this.maxImagesPerMessage,
    required this.maxImageBytes,
    required this.maxMessageImageBytes,
  });

  /// Accepted mime types; a batch containing any other type is rejected.
  final List<String> mediaTypes;

  /// Maximum staged images per message (existing drafts count).
  final int maxImagesPerMessage;

  /// Maximum size of one image in bytes.
  final int maxImageBytes;

  /// Maximum combined size of one message's images in bytes.
  final int maxMessageImageBytes;
}

/// Document-level drag-drop controller — Dart port of the listeners in
/// `packages/client/ui-attachment/src/client/ComposerAttachments.tsx`.
///
/// Owns the drag-depth counter, the accept gate, and the batch pre-check
/// order (format → count → per-file size → total size). The widget layer
/// (`DocumentDropScope`) feeds platform events in; this class decides
/// overlay visibility and whether a batch reaches [onAddImages].
class DragDropController extends ChangeNotifier {
  /// Creates the controller.
  DragDropController({required this.onAddImages, this.onRejected});

  /// Authoritative intake — receives only batches that passed the gate and
  /// the pre-check. Returns a rejection message, or `null` when accepted.
  final String? Function(List<DroppedFile> files) onAddImages;

  /// Called with the display-ready rejection message when a batch is
  /// refused (gate closed or pre-check failed).
  final void Function(String message)? onRejected;

  int _depth = 0;
  bool _canAcceptDrop = false;
  ImageLimits? _limits;

  /// Whether a file drag is currently over the page (overlay visible).
  bool get dragActive => _depth > 0;

  /// Whether drops are accepted right now (drives overlay enabled state).
  bool get canAcceptDrop => _canAcceptDrop;

  /// Declared limits for the overlay's limits line; `null` hides it.
  ImageLimits? get limits => _limits;

  /// Updates the accept gate — `!locked && !machineBusy && intake available`
  /// in React (`InputBar.tsx`). Also updates declared limits.
  void configure({required bool canAcceptDrop, ImageLimits? limits}) {
    _canAcceptDrop = canAcceptDrop;
    _limits = limits;
    notifyListeners();
  }

  /// `dragenter` — counts one nested region entry.
  void dragEntered() {
    _depth += 1;
    notifyListeners();
  }

  /// `dragleave` — clamped decrement; the counter never goes negative.
  void dragLeft() {
    _depth = _depth > 0 ? _depth - 1 : 0;
    notifyListeners();
  }

  /// `dragend` / drop completion — full reset regardless of depth.
  void reset() {
    if (_depth == 0) return;
    _depth = 0;
    notifyListeners();
  }

  /// `drop` — resets the counter, then runs the batch pre-check in React's
  /// order and forwards accepted batches to [onAddImages].
  ///
  /// Format precedes limits: a batch with a non-accepted type announces the
  /// format problem even when it would also exceed a limit — the
  /// authoritative intake owns that rejection text.
  void dropped(List<DroppedFile> files) {
    reset();
    if (!_canAcceptDrop || files.isEmpty) return;
    final ImageLimits? limits = _limits;
    if (limits != null) {
      final bool formatBad = files.any(
        (file) => !limits.mediaTypes.contains(file.mimeType),
      );
      if (formatBad) {
        // Defer to the authoritative intake, mirroring React's
        // `return addImages(files)` early branch.
        _forward(files);
        return;
      }
      // Count is checked against existing drafts by the intake owner; the
      // controller only sees the incoming batch, so the count and total
      // checks receive the current staged count through [stagedCount].
      final String? rejection = _preCheck(files, limits);
      if (rejection != null) {
        onRejected?.call(rejection);
        return;
      }
    }
    _forward(files);
  }

  /// Current staged draft count, needed for the per-message count limit.
  int stagedCount = 0;

  /// Current staged total bytes — mirrors React's
  /// `attachments.reduce(sum)+files.reduce(sum)` check.
  int stagedTotalBytes = 0;

  String? _preCheck(List<DroppedFile> files, ImageLimits limits) {
    if (stagedCount + files.length > limits.maxImagesPerMessage) {
      return 'You can attach up to ${limits.maxImagesPerMessage} images per message';
    }
    if (files.any((file) => file.size > limits.maxImageBytes)) {
      return 'Each image must be smaller than ${_sizeText(limits.maxImageBytes)}';
    }
    final int incoming = files.fold<int>(0, (sum, file) => sum + file.size);
    if (stagedTotalBytes + incoming > limits.maxMessageImageBytes) {
      return 'Images for one message must total less than ${_sizeText(limits.maxMessageImageBytes)}';
    }
    return null;
  }

  void _forward(List<DroppedFile> files) {
    final String? rejected = onAddImages(files);
    if (rejected != null) onRejected?.call(rejected);
  }

  /// Byte-size display used by the limits line and rejections.
  ///
  /// Single source for `imageSizeText` — the `plugins/attachment` helper re-exports
  /// this to avoid duplicated `KB/MB` logic.
  static String _sizeText(int bytes) => imageSizeText(bytes);

  /// Display-ready limits for the drop invitation (React `dropLimits`).
  String? get limitsText {
    final ImageLimits? limits = _limits;
    if (limits == null) return null;
    return 'Up to ${limits.maxImagesPerMessage} images, '
        'each under ${imageSizeText(limits.maxImageBytes)}';
  }
}
