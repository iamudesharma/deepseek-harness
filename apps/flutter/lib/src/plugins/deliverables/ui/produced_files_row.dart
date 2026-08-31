/// Produced-files row — Flutter port of `ProducedFiles.tsx`.
///
/// The produced-file row a finished turn ends with: quiet label, openable
/// basename chips (full path as tooltip), remainder as `+ N`, and the
/// `Show in folder` action gated on the Host's `canOpenPath` capability.
/// Clicking one goes through the chat view's file opener — the Host's own
/// opener, on the Host machine.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../deliverables_mentions.dart' show basename;
import '../locales.dart';

/// At most six chips compete for the one-line summary; every other path
/// stays counted.
const int kProducedShownLimit = 6;

/// Renders one turn's produced files as openable chips.
class ProducedFilesRow extends StatelessWidget {
  /// Creates the row over selector-matched paths.
  const ProducedFilesRow({
    super.key,
    required this.paths,
    this.canOpenPath = false,
    this.onOpenFile,
  });

  /// Matched paths, tool order, already deduped.
  final List<String> paths;

  /// Whether the Host can open paths (loopback + `canOpenPath`).
  final bool canOpenPath;

  /// The chat view's file opener.
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final int shownCount = paths.length > kProducedShownLimit
        ? kProducedShownLimit
        : paths.length;
    final List<String> shown = paths.take(shownCount).toList();
    final int hidden = paths.length - shown.length;

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
          Text(
            kDeliverablesEn['produced.label']!,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              fontWeight: FontWeight.w600,
              color: aliases.labelCaption,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Wrap(
            spacing: DswTokens.spaceSm,
            runSpacing: DswTokens.spaceSm,
            children: [
              for (final path in shown)
                // The full path is the disambiguator when two turns produce
                // files that share a basename; the chip itself stays short.
                Tooltip(
                  message: path,
                  child: ActionChip(
                    label: Text(
                      basename(path),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    backgroundColor: aliases.bgOverlay,
                    side: BorderSide(color: aliases.borderL2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                    ),
                    onPressed: onOpenFile == null
                        ? null
                        : () => onOpenFile!(path),
                  ),
                ),
              if (hidden > 0)
                Chip(
                  label: Text(
                    _moreLabel(hidden),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                  backgroundColor: aliases.bgOverlay,
                  side: BorderSide(color: aliases.borderL2),
                ),
            ],
          ),
          if (hidden > 0 && canOpenPath && onOpenFile != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenFile!('.'),
                icon: Icon(
                  Icons.folder_open,
                  size: 14,
                  color: aliases.stateBusinessPrimary,
                ),
                label: Text(
                  kDeliverablesEn['produced.showInFolder']!,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.stateBusinessPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _moreLabel(int count) => count == 1
      ? kDeliverablesEn['produced.moreOne']!
      : '+ $count ${count == 1 ? 'file' : 'files'}';
}
