import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_models.dart' show DraftAttachmentId;
import '../../theme/app_theme.dart';
import 'attachment_provider.dart';

/// Attachment screen — ComposerAttachments / MessageImages / Lightbox gallery.
///
/// Mirrors `ComposerAttachments` (rail + DropOverlay + Lightbox) +
/// `MessageImages` gallery. ConsumerWidget, Theme + DswTokens, empty/loading.
class AttachmentScreen extends ConsumerWidget {
  const AttachmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final List<ComposerAttachment> composer = ref.watch(
      composerAttachmentsProvider,
    );
    final AsyncValue<List<MessageImage>> imagesAsync = ref.watch(
      messageImagesProvider,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Attachments',
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          ComposerAttachmentsView(attachments: composer, aliases: aliases),
          const SizedBox(height: DswTokens.spaceLg),
          Text(
            'Message images',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          imagesAsync.when(
            data: (List<MessageImage> images) {
              if (images.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(DswTokens.spaceLg),
                  decoration: BoxDecoration(
                    color: aliases.bgOverlay,
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    border: Border.all(color: aliases.borderL1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 16,
                        color: aliases.labelCaption,
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      Text(
                        'No images',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          color: aliases.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return MessageImagesView(images: images, aliases: aliases);
            },
            loading: () => Padding(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: aliases.labelTertiary,
                      ),
                    ),
                    const SizedBox(height: DswTokens.spaceSm),
                    Text(
                      'Loading images…',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            error: (Object err, StackTrace st) => Padding(
              padding: const EdgeInsets.all(DswTokens.spaceMd),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: aliases.stateErrorPrimary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    err.toString(),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceSm),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(messageImagesProvider),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ComposerAttachments rail — draft image chips with remove + lightbox preview.
class ComposerAttachmentsView extends ConsumerWidget {
  const ComposerAttachmentsView({
    super.key,
    required this.attachments,
    required this.aliases,
  });
  final List<ComposerAttachment> attachments;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        decoration: BoxDecoration(
          color: aliases.bgLayer2,
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
          border: Border.all(color: aliases.borderL2),
        ),
        child: Column(
          children: [
            Icon(Icons.attach_file, size: 28, color: aliases.labelCaption),
            const SizedBox(height: DswTokens.spaceSm),
            Text(
              'No attachments',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                fontWeight: FontWeight.w500,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Drag images here or tap Add.',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelCaption,
              ),
            ),
            const SizedBox(height: DswTokens.spaceMd),
            OutlinedButton.icon(
              onPressed: () => _addMock(ref),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('Add image'),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Composer attachments',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${attachments.length} file${attachments.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: DswTokens.spaceMd),
          // DropOverlay stub — shows when dragging over this area (simplified).
          Wrap(
            spacing: DswTokens.spaceSm,
            runSpacing: DswTokens.spaceSm,
            children: [
              for (final a in attachments)
                _AttachmentChip(
                  attachment: a,
                  aliases: aliases,
                  onOpen: () => _openLightbox(context, a),
                  onRemove: () =>
                      ref.read(composerAttachmentsProvider.notifier).state =
                          attachments.where((x) => x.id != a.id).toList(),
                ),
            ],
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _addMock(ref),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add image'),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Text(
                'Drag & drop supported',
                style: TextStyle(fontSize: 11, color: aliases.labelCaption),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addMock(WidgetRef ref) {
    final List<ComposerAttachment> cur = ref.read(composerAttachmentsProvider);
    ref.read(composerAttachmentsProvider.notifier).state = [
      ...cur,
      ComposerAttachment(
        id: DraftAttachmentId('a${cur.length + 1}'),
        name: 'image_${cur.length + 1}.png',
      ),
    ];
  }

  void _openLightbox(BuildContext context, ComposerAttachment a) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) =>
          LightboxGallery(images: [a.name], initialIndex: 0, aliases: aliases),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.aliases,
    required this.onOpen,
    required this.onRemove,
  });
  final ComposerAttachment attachment;
  final DswAliases aliases;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceSm,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 14,
                    color: aliases.labelTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    attachment.name,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 12, color: aliases.labelTertiary),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

/// MessageImages gallery — thumbnail grid with Lightbox on tap.
class MessageImagesView extends StatelessWidget {
  const MessageImagesView({
    super.key,
    required this.images,
    required this.aliases,
  });
  final List<MessageImage> images;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DswTokens.spaceSm,
      runSpacing: DswTokens.spaceSm,
      children: [
        for (int i = 0; i < images.length; i++)
          _ImageThumb(
            image: images[i],
            images: images,
            index: i,
            aliases: aliases,
          ),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    required this.image,
    required this.images,
    required this.index,
    required this.aliases,
  });
  final MessageImage image;
  final List<MessageImage> images;
  final int index;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => LightboxGallery(
          images: images.map((e) => e.url).toList(),
          initialIndex: index,
          aliases: aliases,
        ),
      ),
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          border: Border.all(color: aliases.borderL1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, size: 24, color: aliases.labelCaption),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                image.alt ?? image.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: aliases.labelCaption),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightbox gallery — full-screen dialog with swipe/next/prev + close.
class LightboxGallery extends StatefulWidget {
  const LightboxGallery({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.aliases,
  });
  final List<String> images;
  final int initialIndex;
  final DswAliases aliases;

  @override
  State<LightboxGallery> createState() => _LightboxGalleryState();
}

class _LightboxGalleryState extends State<LightboxGallery> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: widget.aliases.bgMaskPhoto,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 320,
                  height: 200,
                  decoration: BoxDecoration(
                    color: widget.aliases.bgLayer2,
                    borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image,
                          size: 48,
                          color: widget.aliases.labelCaption,
                        ),
                        const SizedBox(height: DswTokens.spaceSm),
                        Text(
                          widget.images[_index],
                          style: TextStyle(
                            color: widget.aliases.labelSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_index + 1} / ${widget.images.length}',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: widget.aliases.labelCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: _index > 0
                          ? () => setState(() => _index -= 1)
                          : null,
                    ),
                    const SizedBox(width: DswTokens.spaceLg),
                    IconButton(
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                      onPressed: _index < widget.images.length - 1
                          ? () => setState(() => _index += 1)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
