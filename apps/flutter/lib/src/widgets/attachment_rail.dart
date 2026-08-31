import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../features/conversation/composer_controller.dart'
    show ComposerAttachment;
import '../theme/app_theme.dart';
import 'attachment_image.dart';

/// Thumbnail rail — Flutter port of `AttachmentRail.tsx`.
///
/// Horizontal overflow with hidden scrollbar, paging arrows recomputed from
/// scroll geometry, wheel-to-horizontal conversion, and hover-revealed remove
/// control. The owner decides mounting — the rail renders only while items
/// exist.
class AttachmentRail extends StatefulWidget {
  /// Creates the rail.
  const AttachmentRail({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onRemove,
  });

  /// Resolved thumbnails in draft order.
  final List<ComposerAttachment> items;

  /// Single-click open of one item's original image.
  final ValueChanged<ComposerAttachment> onOpen;

  /// Remove one item from the draft (by id); `null` disables removal
  /// (e.g. while sending / locked — mirrors React's rail staying mounted while
  /// the composer is inert).
  final ValueChanged<ComposerAttachment>? onRemove;

  @override
  State<AttachmentRail> createState() => _AttachmentRailState();
}

class _AttachmentRailState extends State<AttachmentRail> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  int? _prevCount;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleGrowthAndEdges(),
    );
  }

  @override
  void didUpdateWidget(AttachmentRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleGrowthAndEdges(),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_updateEdges);
    _controller.dispose();
    super.dispose();
  }

  void _handleGrowthAndEdges() {
    if (!mounted) return;
    final bool grew = _prevCount != null && widget.items.length > _prevCount!;
    _prevCount = widget.items.length;
    if (grew && _controller.hasClients) {
      // Reveal newly added attachment at the rail's end — mirrors React's
      // `el.scrollLeft = el.scrollWidth - el.clientWidth` when grown.
      _controller.jumpTo(_controller.position.maxScrollExtent);
    }
    _updateEdges();
  }

  void _updateEdges() {
    if (!_controller.hasClients) return;
    final double position = _controller.offset;
    final double max = _controller.position.maxScrollExtent;
    // 1px slack: engines report fractional scroll positions at edges.
    final bool left = position > 1;
    final bool right = position < max - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _page(int direction) {
    if (!_controller.hasClients) return;
    final double viewport = _controller.position.viewportDimension;
    final double delta = (viewport - 64).clamp(200, double.infinity);
    final double target = (_controller.offset + direction * delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Trigger edge recompute when rail width changes (sidebar/panel resize).
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // Horizontal rail with hidden scrollbar.
            Listener(
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                  // Vertical wheel pans the rail horizontally and is consumed
                  // exclusively — matching React's non-passive wheel listener.
                  final double dy = event.scrollDelta.dy;
                  final double dx = event.scrollDelta.dx;
                  if (dy != 0) {
                    final double delta = dx != 0
                        ? dx
                        : dy.sign * dy.abs().clamp(0, 60);
                    final double target = (_controller.offset + delta).clamp(
                      0.0,
                      _controller.position.hasContentDimensions
                          ? _controller.position.maxScrollExtent
                          : 0.0,
                    );
                    _controller.jumpTo(target);
                  }
                }
              },
              child: SizedBox(
                height: 64,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final ComposerAttachment item = widget.items[index];
                      final ValueChanged<ComposerAttachment>? remover =
                          widget.onRemove;
                      return _RailItem(
                        attachment: item,
                        aliases: aliases,
                        onOpen: () => widget.onOpen(item),
                        onRemove: remover == null ? null : () => remover(item),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_canScrollLeft)
              Positioned(
                left: 4,
                top: 20,
                child: _ArrowButton(
                  icon: Icons.chevron_left,
                  aliases: aliases,
                  onPressed: () => _page(-1),
                  semantics: 'Scroll left',
                ),
              ),
            if (_canScrollRight)
              Positioned(
                right: 4,
                top: 20,
                child: _ArrowButton(
                  icon: Icons.chevron_right,
                  aliases: aliases,
                  onPressed: () => _page(1),
                  semantics: 'Scroll right',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.attachment,
    required this.aliases,
    required this.onOpen,
    this.onRemove,
  });

  final ComposerAttachment attachment;
  final DswAliases aliases;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ComposerAttachment a = widget.attachment;
    final DswAliases aliases = widget.aliases;

    // Determine thumbnail widget — prefer previewUrl image when available.
    // Web: `previewUrl` is a blob/data/http URL → `Image.network`.
    // Native: `previewUrl` is a file path → `Image.file` via conditional import seam.
    Widget thumb;
    if (a.previewUrl != null && a.previewUrl!.isNotEmpty) {
      final String url = a.previewUrl!;
      if (url.startsWith('http') ||
          url.startsWith('blob:') ||
          url.startsWith('data:')) {
        thumb = Image.network(
          url,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stackTrace,
          ) => _fallbackIcon(aliases),
        );
      } else if (url.startsWith('/') || url.startsWith('file://')) {
        final String filePath = url.startsWith('file://')
            ? url.substring(7)
            : url;
        thumb = buildNativeThumbnail(filePath, aliases);
      } else {
        thumb = _fallbackIcon(aliases);
      }
    } else if (a.mimeType != null && a.mimeType!.startsWith('image/')) {
      // Image-typed but no preview — show image icon placeholder (will be
      // replaced once preview generation moves async, matching React's
      // object URL that is immediately available).
      thumb = _fallbackIcon(aliases);
    } else {
      thumb = Icon(Icons.description, size: 24, color: aliases.labelCaption);
    }

    final bool showRemove = _hovered || MediaQuery.of(context).size.width < 600;
    // On coarse pointers (touch) the remove is always visible — match
    // React's `@media (pointer: coarse) { opacity: 1 }`.

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(color: aliases.borderL2),
                    borderRadius: BorderRadius.circular(16),
                    color: aliases.bgOverlay,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: thumb,
                  ),
                ),
              ),
            ),
            // Remove control inside the card, hover-revealed (opacity).
            // Hidden entirely when `onRemove` is null (locked/sending).
            if (widget.onRemove != null)
              Positioned(
                top: 4,
                right: 4,
                child: AnimatedOpacity(
                  opacity: showRemove ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Material(
                    color: aliases.labelPrimary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: widget.onRemove,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: aliases.bgLayer1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(DswAliases aliases) {
    return Container(
      width: 64,
      height: 64,
      color: aliases.bgOverlay,
      child: Icon(Icons.image_outlined, size: 22, color: aliases.labelCaption),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.aliases,
    required this.onPressed,
    required this.semantics,
  });

  final IconData icon;
  final DswAliases aliases;
  final VoidCallback onPressed;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: aliases.specificInputMajor,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: aliases.borderL2),
            ),
            child: Icon(icon, size: 16, color: aliases.labelSecondary),
          ),
        ),
      ),
    );
  }
}

/// Lightbox for draft image preview — Flutter port of `ImageLightbox.tsx`.
///
/// Shows the original image (via previewUrl when available) with close on
/// scrim tap / Escape handled by Dialog's barrier.
class AttachmentLightbox extends StatelessWidget {
  /// Creates the lightbox.
  const AttachmentLightbox({
    super.key,
    required this.attachment,
    required this.aliases,
  });

  /// Attachment to preview.
  final ComposerAttachment attachment;

  /// Theme aliases.
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final String? url = attachment.previewUrl ?? attachment.path;
    final Widget image;
    if (url != null &&
        url.isNotEmpty &&
        (url.startsWith('http') ||
            url.startsWith('blob:') ||
            url.startsWith('data:'))) {
      image = Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) => _placeholder(context),
      );
    } else if (url != null &&
        url.isNotEmpty &&
        (url.startsWith('/') || url.startsWith('file://'))) {
      final String filePath = url.startsWith('file://')
          ? url.substring(7)
          : url;
      image = buildNativeLightbox(filePath, aliases, attachment.name);
    } else {
      image = _placeholder(context);
    }

    return Dialog(
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
              child: image,
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close preview',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                attachment.name,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 320,
      height: 200,
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.image, size: 48, color: aliases.labelCaption),
          const SizedBox(height: 8),
          Text(
            attachment.name,
            style: TextStyle(color: aliases.labelSecondary),
          ),
        ],
      ),
    );
  }
}
