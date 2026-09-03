/// Produced-files row — Flutter port of `ProducedFiles.tsx`.
///
/// The produced-file row a finished turn ends with: quiet label, openable
/// basename chips (full path as tooltip), remainder as `+ N`, and the
/// `Show in folder` action gated on the Host's `canOpenPath` capability.
/// Clicking one goes through the chat view's file opener — the Host's own
/// opener, on the Host machine.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../deliverables_mentions.dart' show basename;
import '../locales.dart';

/// At most six chips compete for the one-line summary; every other path
/// stays counted (React `SHOWN_LIMIT` parity).
const int kProducedShownLimit = 6;

/// Renders one turn's produced files as openable chips.
class ProducedFilesRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    // Product copy resolves through the deliverables dictionaries; the
    // revision watch inside bindLocale re-renders on a Language-row switch.
    final Translate t = ref.bindLocale(kDeliverablesNamespace);
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
            t('produced.label'),
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
                // Tooltip carries the title parity; Semantics carries the
                // `produced.open` accessible name React puts in aria-label.
                Semantics(
                  label: t(
                    'produced.open',
                  ).replaceAll('{name}', path),
                  button: true,
                  child: Tooltip(
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
                        borderRadius: BorderRadius.circular(
                          DswTokens.radiusFull,
                        ),
                      ),
                      onPressed: onOpenFile == null
                          ? null
                          : () => onOpenFile!(path),
                    ),
                  ),
                ),
              if (hidden > 0)
                Chip(
                  label: Text(
                    _moreLabel(t, hidden),
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
          // React renders the folder action when `paths.length > 1`, but its
          // CSS keeps it `display: none` until a `.more` remainder is visible
          // at the current container width (`:has(.more[data-shown])`). The
          // Flutter row wraps instead of overflow-hiding, so visible parity
          // is overflow-only: the action appears only when paths overflow
          // the six-chip cap and the Host opener is available.
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
                  t('produced.showInFolder'),
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

  static String _moreLabel(Translate t, int count) => count == 1
      ? t('produced.moreOne')
      : t('produced.more').replaceAll('{count}', '$count');
}
