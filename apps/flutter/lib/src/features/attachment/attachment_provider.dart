import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_models.dart' show DraftAttachmentId;
import '../conversation/composer_controller.dart' show ComposerAttachment;

/// Re-export the canonical [ComposerAttachment] model so callers can import
/// from either the attachment or conversation feature without duplicating the
/// type (single source: `composer_controller.dart`).
export '../conversation/composer_controller.dart' show ComposerAttachment;

class MessageImage {
  const MessageImage({required this.id, required this.url, this.alt});
  final String id;
  final String url;
  final String? alt;
}

@Deprecated(
  'Use composerControllerProvider(sessionId) — see composer_controller.dart. '
  'composerAttachmentsProvider is a legacy demo provider with fake data.',
)
final composerAttachmentsProvider = StateProvider<List<ComposerAttachment>>(
  (ref) => const [
    ComposerAttachment(id: DraftAttachmentId('a1'), name: 'screenshot.png', previewUrl: null),
    ComposerAttachment(id: DraftAttachmentId('a2'), name: 'diagram.jpg', previewUrl: null),
  ],
);

final messageImagesProvider = FutureProvider<List<MessageImage>>((ref) async {
  await Future.delayed(const Duration(milliseconds: 350));
  return const [
    MessageImage(
      id: 'm1',
      url: 'https://via.placeholder.com/300',
      alt: 'Placeholder 1',
    ),
    MessageImage(
      id: 'm2',
      url: 'https://via.placeholder.com/320',
      alt: 'Placeholder 2',
    ),
  ];
});
