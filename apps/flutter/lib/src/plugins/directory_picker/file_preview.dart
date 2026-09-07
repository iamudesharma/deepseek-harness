/// Bounded file preview bottom sheet over `directoryPicker/readFile`.
///
/// Paged text view of one regular file: line-window pager, copy-page
/// action, and inline failure states. The sheet owns its page state; the
/// caller supplies the path and a reader so tests drive it without a host.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../platform/clipboard.dart';
import '../../theme/app_theme.dart';
import 'directory_browser.dart';
import 'directory_picker_plugin.dart' show kDirectoryBrowserLocaleNs;

/// Lines per preview page.
const int kFilePreviewPageLines = 100;

/// Reads one bounded file page; mirrors `WorkspacesService.readFile`.
typedef ReadFilePage =
    Future<Map<String, Object?>> Function({
      required String path,
      int? offset,
      int? count,
    });

/// Bottom sheet previewing one file with line-window paging.
class FilePreviewSheet extends ConsumerStatefulWidget {
  /// Creates the preview sheet.
  const FilePreviewSheet({
    super.key,
    required this.path,
    required this.readFile,
    this.namespace = kDirectoryBrowserLocaleNs,
  });

  /// Absolute host path of the file.
  final String path;

  /// Page reader (host `directoryPicker/readFile` or a test fake).
  final ReadFilePage readFile;

  /// Locale namespace for chrome copy.
  final String namespace;

  @override
  ConsumerState<FilePreviewSheet> createState() => _FilePreviewSheetState();
}

class _FilePreviewSheetState extends ConsumerState<FilePreviewSheet> {
  int _offset = 0;
  DirectoryFilePage? _page;
  bool _loading = true;
  String? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final map = await widget.readFile(
        path: widget.path,
        offset: _offset,
        count: kFilePreviewPageLines,
      );
      if (!mounted) return;
      setState(() {
        _page = DirectoryFilePage.fromJson(map.cast<String, dynamic>());
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _turn(int delta) {
    setState(() => _offset = (_offset + delta).clamp(0, 1 << 30));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(widget.namespace);
    final String name = widget.path.split(RegExp(r'[/\\]')).lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => widget.path,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t('preview.copy'),
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy_outlined,
                    size: 16,
                  ),
                  onPressed: _page == null
                      ? null
                      : () async {
                          await ClipboardHelper.copy(_page!.text);
                          if (mounted) {
                            setState(() => _copied = true);
                            Future<void>.delayed(
                              const Duration(seconds: 2),
                            ).then((_) {
                              if (mounted) {
                                setState(() => _copied = false);
                              }
                            });
                          }
                        },
                ),
                IconButton(
                  tooltip: t('preview.close'),
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Divider(height: 1, color: aliases.borderL2),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 380),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _PreviewError(
                        message: _error!,
                        aliases: aliases,
                        onRetry: _load,
                      )
                    : _PreviewBody(page: _page!, aliases: aliases),
              ),
            ),
            if (_page != null && _error == null)
              _PagerRow(
                page: _page!,
                offset: _offset,
                aliases: aliases,
                t: t,
                onPrev: _offset == 0
                    ? null
                    : () => _turn(-kFilePreviewPageLines),
                onNext: _page!.truncated
                    ? () => _turn(kFilePreviewPageLines)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Preview error with retry.
class _PreviewError extends StatelessWidget {
  /// Creates the error view.
  const _PreviewError({
    required this.message,
    required this.aliases,
    required this.onRetry,
  });

  /// The failure text.
  final String message;

  /// Theme aliases.
  final DswAliases aliases;

  /// Retry callback.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXs13,
              color: aliases.stateErrorPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Page body: monospace selectable text with an empty state.
class _PreviewBody extends StatelessWidget {
  /// Creates the body.
  const _PreviewBody({required this.page, required this.aliases});

  /// The loaded page.
  final DirectoryFilePage page;

  /// Theme aliases.
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    if (page.text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Text(
          '(empty)',
          style: TextStyle(
            fontSize: DswTokens.fontSizeXs13,
            color: aliases.labelTertiary,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      child: SelectableText(
        page.text,
        style: TextStyle(
          fontFamily: 'SF Mono',
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          color: aliases.labelPrimary,
        ),
      ),
    );
  }
}

/// Pager row: window position, prev/next, truncation note.
class _PagerRow extends StatelessWidget {
  /// Creates the pager row.
  const _PagerRow({
    required this.page,
    required this.offset,
    required this.aliases,
    required this.t,
    required this.onPrev,
    required this.onNext,
  });

  /// The loaded page.
  final DirectoryFilePage page;

  /// Current line offset.
  final int offset;

  /// Theme aliases.
  final DswAliases aliases;

  /// Picker translations.
  final Translate t;

  /// Previous-page callback, null on the first page.
  final VoidCallback? onPrev;

  /// Next-page callback, null when the file ends in this page.
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final int lines = page.text.isEmpty ? 0 : '\n'.allMatches(page.text).length + 1;
    final String position = page.totalLines != null
        ? t('preview.position.of')
            .replaceAll('{offset}', '${offset + 1}')
            .replaceAll('{end}', '${offset + lines}')
            .replaceAll('{total}', '${page.totalLines}')
        : t('preview.position.from')
            .replaceAll('{offset}', '${offset + 1}')
            .replaceAll('{count}', '$lines');
    return Padding(
      padding: const EdgeInsets.only(top: DswTokens.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              position,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.labelSecondary,
              ),
            ),
          ),
          IconButton(
            tooltip: t('preview.prev'),
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: onPrev,
          ),
          IconButton(
            tooltip: t('preview.next'),
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
