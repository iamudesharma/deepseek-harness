/// Attachment staging service — the Dart slice of `ComposerAttachments`'
/// draft state: the pending-image rail the composer seat will render once
/// its hole is declared. React keeps draft attachments in the conversation
/// composer's own store; until the Dart hub exposes
/// `conversation.input.attachments`, this service is the shared face other
/// surfaces (composer, send path) read and mutate.
library;

import 'package:flutter/foundation.dart';

import '../../features/attachment/attachment_provider.dart'
    show ComposerAttachment;

/// Service name the staging face is published under.
const String kAttachmentsServiceName = 'attachments';

/// Staged (draft) attachment list with change notification.
///
/// Deprecated — draft attachments are owned per-session by
/// `composerControllerProvider` (`ComposerAttachment` in
/// `features/conversation/composer_controller.dart`). This service is retained
/// only for the WS-surfaces plugin fixture's `host.service(kAttachmentsServiceName)`
/// assertion and will be removed once that fixture migrates to the session
/// provider. New code must use `composerControllerProvider(sessionId)`.
@Deprecated(
  'Use composerControllerProvider(sessionId) — see composer_controller.dart. '
  'This staging service will be removed after WS surfaces migrate.',
)
class AttachmentStagingService extends ChangeNotifier {
  final List<ComposerAttachment> _items = [];

  /// Current staged items (unmodifiable view).
  List<ComposerAttachment> get items => List.unmodifiable(_items);

  /// Stages one attachment; no-op when an item with the same id is staged.
  void add(ComposerAttachment attachment) {
    if (_items.any((item) => item.id == attachment.id)) return;
    _items.add(attachment);
    notifyListeners();
  }

  /// Removes one staged attachment by id.
  void remove(String id) {
    final length = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length != length) notifyListeners();
  }

  /// Clears the stage (post-send or dismissal).
  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
