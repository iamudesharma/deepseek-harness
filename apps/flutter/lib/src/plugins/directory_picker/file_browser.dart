/// Repo file browser: directory navigation with file rows and preview.
///
/// Unlike the pick-oriented [DirectoryBrowser], this screen is for
/// inspecting a workspace tree: directories navigate, regular files open a
/// preview sheet. Listings request `{ includeFiles: true }`; the caller
/// supplies listing and file readers so tests drive it without a host.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../theme/app_theme.dart';
import 'directory_browser.dart';
import 'directory_picker_plugin.dart' show kDirectoryBrowserLocaleNs;
import 'file_preview.dart';

/// Lists one level with file rows.
typedef ListFilesLevel =
    Future<DirectoryListing> Function({required String path});

/// File browser screen over one workspace root.
class FileBrowserScreen extends ConsumerStatefulWidget {
  /// Creates the browser screen.
  const FileBrowserScreen({
    super.key,
    required this.rootPath,
    required this.listLevel,
    required this.readFile,
    this.title,
  });

  /// Workspace root path the browser starts at and cannot leave above.
  final String rootPath;

  /// Level lister with `{ includeFiles: true }`.
  final ListFilesLevel listLevel;

  /// Page reader for the preview sheet.
  final ReadFilePage readFile;

  /// Optional title override; defaults to the root's base name.
  final String? title;

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  late String _path;
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _path = widget.rootPath;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.listLevel(path: _path);
      if (!mounted) return;
      setState(() {
        _listing = listing;
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

  void _enter(DirectoryEntry entry) {
    setState(() => _path = entry.path);
    _load();
  }

  void _up() {
    final listing = _listing;
    if (listing == null || listing.crumbs.length < 2) return;
    final parent = listing.crumbs[listing.crumbs.length - 2].path;
    // Never navigate above the workspace root this screen opened at.
    if (!parent.startsWith(widget.rootPath)) return;
    setState(() => _path = parent);
    _load();
  }

  void _preview(DirectoryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => FilePreviewSheet(
          path: entry.path,
          readFile: widget.readFile,
        ),
      ),
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
    ref.bindLocale(kDirectoryBrowserLocaleNs);
    final String title =
        widget.title ?? _path.split(RegExp(r'[/\\]')).lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => _path,
        );
    final bool canUp =
        _listing != null &&
        _listing!.crumbs.length >= 2 &&
        _listing!.crumbs[_listing!.crumbs.length - 2].path.startsWith(
          widget.rootPath,
        );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, size: 18),
          onPressed: canUp ? _up : null,
        ),
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Show hidden files',
            icon: Icon(
              _showHidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
            onPressed: () =>
                setState(() => _showHidden = !_showHidden),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _load,
          ),
          const SizedBox(width: DswTokens.spaceSm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _BrowserError(
              message: _error!,
              aliases: aliases,
              onRetry: _load,
            )
          : _FileList(
              listing: _listing!,
              showHidden: _showHidden,
              aliases: aliases,
              onEnter: _enter,
              onPreview: _preview,
            ),
    );
  }
}

/// Browser failure with retry.
class _BrowserError extends StatelessWidget {
  /// Creates the error view.
  const _BrowserError({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.stateErrorPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Level rows: directories navigate, files preview.
class _FileList extends StatelessWidget {
  /// Creates the file list.
  const _FileList({
    required this.listing,
    required this.showHidden,
    required this.aliases,
    required this.onEnter,
    required this.onPreview,
  });

  /// The loaded level.
  final DirectoryListing listing;

  /// Whether hidden rows show.
  final bool showHidden;

  /// Theme aliases.
  final DswAliases aliases;

  /// Directory navigation callback.
  final ValueChanged<DirectoryEntry> onEnter;

  /// File preview callback.
  final ValueChanged<DirectoryEntry> onPreview;

  @override
  Widget build(BuildContext context) {
    final visible = listing.entries
        .where((e) => showHidden || !e.hidden)
        .toList(growable: false);
    if (visible.isEmpty) {
      return Center(
        child: Text(
          '(empty)',
          style: TextStyle(
            fontSize: DswTokens.fontSizeXs13,
            color: aliases.labelTertiary,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final entry = visible[i];
        final bool isFile = entry.isFile;
        return TextButton(
          onPressed: () => isFile ? onPreview(entry) : onEnter(entry),
          style: TextButton.styleFrom(
            foregroundColor: aliases.labelPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: [
              Icon(
                isFile ? Icons.description_outlined : Icons.folder_outlined,
                size: 16,
                color: aliases.labelSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: entry.hidden
                        ? aliases.labelTertiary
                        : aliases.labelPrimary,
                  ),
                ),
              ),
              if (isFile)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: aliases.labelTertiary,
                ),
            ],
          ),
        );
      },
    );
  }
}
