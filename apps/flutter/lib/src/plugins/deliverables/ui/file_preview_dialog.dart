/// In-app file preview over `workspaceFiles/*` — the first page of a
/// produced file with Host-owned failure states.
///
/// React opens produced files in the right-sidebar text preview; Flutter has
/// no dock host yet, so the preview renders here as a dialog (narrow screens
/// get near-fullscreen insets). Content policy mirrors the Host: only
/// regular text files preview; directories, binaries, over-cap pages, and
/// denied paths render the failure line with retry instead of guessing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/rpc_envelope.dart';
import '../../../core/files/workspace_files_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_models.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart';

/// Shows [path] from [sessionId]'s workspace in a preview dialog.
/// @param context - build context for the dialog route.
/// @param ref - reader for the files client.
/// @param sessionId - session whose workspace authorizes the read.
/// @param path - absolute path in the filesystem's execution world.
/// @param onOpenHost - host-native opener fallback for non-previewable
/// paths (directories); null hides the fallback action.
Future<void> showFilePreviewDialog(
  BuildContext context,
  WidgetRef ref, {
  required SessionId sessionId,
  required String path,
  Future<void> Function()? onOpenHost,
}) {
  final files = ref.read(workspaceFilesClientProvider);
  return showDialog<void>(
    context: context,
    builder: (context) => FilePreviewDialog(
      files: files,
      sessionId: sessionId,
      path: path,
      onOpenHost: onOpenHost,
    ),
  );
}

/// One file preview: stat gate, first text page, failure line with retry.
class FilePreviewDialog extends ConsumerStatefulWidget {
  /// Creates the preview dialog.
  const FilePreviewDialog({
    super.key,
    required this.files,
    required this.sessionId,
    required this.path,
    this.onOpenHost,
    this.initialLine,
  });

  /// Typed workspace files client.
  final WorkspaceFilesClient files;

  /// Session whose workspace authorizes the read.
  final SessionId sessionId;

  /// Absolute path to preview.
  final String path;

  /// Host-native opener fallback for non-previewable paths.
  final Future<void> Function()? onOpenHost;

  /// First line to preview (1-based, from a read call's arguments);
  /// defaults to the file start.
  final int? initialLine;

  @override
  ConsumerState<FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends ConsumerState<FilePreviewDialog> {
  late Future<WorkspaceFileText> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<WorkspaceFileText> _load() async {
    final stat = await widget.files.stat(widget.sessionId, widget.path);
    final initialLine = widget.initialLine;
    return widget.files.read(
      widget.sessionId,
      stat.absolutePath,
      offset: initialLine != null && initialLine >= 1 ? initialLine : 1,
    );
  }

  String _failureCopy(Translate t, Object error) {
    final code = error is WorkspaceFileException ? error.code : null;
    return switch (code) {
      RpcErrorCode.workspaceFileNotFound => t('preview.notFound'),
      RpcErrorCode.workspaceFileTooLarge => t('preview.tooLarge'),
      RpcErrorCode.workspaceFileNotText ||
      RpcErrorCode.workspaceFileNotRegularFile ||
      RpcErrorCode.workspaceFileNotDirectory =>
        t('preview.notText'),
      RpcErrorCode.workspaceFileOutsideWorkspace => t('preview.denied'),
      _ => t('preview.failed'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kDeliverablesNamespace);
    final double width = MediaQuery.widthOf(context);
    return Dialog(
      insetPadding: EdgeInsets.all(width < 600 ? 8 : 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('preview.title'),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w600,
                        color: aliases.labelPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: t('preview.close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                widget.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                  fontFamily: DswTokens.fontFamilyCode,
                ),
              ),
              const SizedBox(height: DswTokens.spaceSm),
              Flexible(
                child: FutureBuilder<WorkspaceFileText>(
                  future: _loadFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    if (snapshot.hasError) {
                      final code = snapshot.error is WorkspaceFileException
                          ? (snapshot.error as WorkspaceFileException).code
                          : null;
                      final hostFallback =
                          widget.onOpenHost != null &&
                              (code ==
                                      RpcErrorCode
                                          .workspaceFileNotRegularFile ||
                                  code ==
                                      RpcErrorCode.workspaceFileNotDirectory);
                      return _FailureView(
                        message: _failureCopy(t, snapshot.error!),
                        retryLabel: t('preview.retry'),
                        aliases: aliases,
                        onRetry: () {
                          setState(() {
                            _loadFuture = _load();
                          });
                        },
                        hostLabel: hostFallback
                            ? t('produced.showInFolder')
                            : null,
                        onOpenHost: hostFallback
                            ? () async {
                                Navigator.of(context).pop();
                                await widget.onOpenHost!();
                              }
                            : null,
                      );
                    }
                    // ignore: avoid-non-null-assertion — hasError false + done.
                    final page = snapshot.data!;
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            page.text,
                            style: TextStyle(
                              fontFamily: DswTokens.fontFamilyCode,
                              fontSize: 12.5,
                              color: aliases.labelPrimary,
                            ),
                          ),
                          if (!page.eof) ...[
                            const SizedBox(height: DswTokens.spaceSm),
                            Text(
                              t('preview.truncated').replaceAll(
                                '{lines}',
                                '${page.lines}',
                              ),
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeXxs12,
                                color: aliases.labelSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Failure line with retry (React text-preview `failure-line` parity).
class _FailureView extends StatelessWidget {
  /// Creates the failure view.
  const _FailureView({
    required this.message,
    required this.retryLabel,
    required this.aliases,
    required this.onRetry,
    this.hostLabel,
    this.onOpenHost,
  });

  /// Localized failure reason.
  final String message;

  /// Localized retry label.
  final String retryLabel;

  /// Theme aliases.
  final DswAliases aliases;

  /// Retry callback.
  final VoidCallback onRetry;

  /// Localized host-opener label; null hides the fallback action.
  final String? hostLabel;

  /// Host-native opener fallback; null hides the fallback action.
  final VoidCallback? onOpenHost;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
              if (hostLabel != null && onOpenHost != null)
                TextButton(onPressed: onOpenHost, child: Text(hostLabel!)),
            ],
          ),
        ],
      ),
    );
  }
}
