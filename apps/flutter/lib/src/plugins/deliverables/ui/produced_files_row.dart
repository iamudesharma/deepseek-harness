/// Produced-files row — Flutter port of `ProducedFiles.tsx`.
///
/// The produced-file summary a finished turn ends with: a quiet `Produced`
/// label and one nowrap lane of openable file links (full path as tooltip,
/// basename as the link text), a counted remainder when the lane cannot fit
/// everything, and the `Show in folder` action. React renders this as a
/// chromeless grid of plain link-colored text buttons — no card, no chips —
/// with container-query bands deciding how many links fit; the band
/// thresholds below are the same budgets the CSS bands encode.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/link_icon.dart';
import '../deliverables_mentions.dart' show basename;
import '../locales.dart';

/// Maximum number of file links rendered before the remainder counter
/// (React `SHOWN_LIMIT`).
const int kProducedShownLimit = 6;

/// Container-query band from `ProducedFiles.module.css`: each band budgets
/// 96px per file, 8px gaps, and 64px for the remainder.
/// @param laneWidth - the file lane's live width.
/// @returns how many of the six candidates fit at this width.
int producedShownBand(double laneWidth) {
  if (laneWidth > 687) return 6;
  if (laneWidth > 583) return 5;
  if (laneWidth > 479) return 4;
  if (laneWidth > 375) return 3;
  if (laneWidth > 271) return 2;
  return 1;
}

/// Renders one turn's produced files as openable plain-text links.
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

    // React `.root`: label and lane share one grid row, 8px column gap,
    // 16px above the row; the lane decides how many links fit.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('produced.label'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeXs13,
              height: 22 / 13,
              color: aliases.labelTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints lane) {
                final int band = producedShownBand(lane.maxWidth);
                final int cap = paths.length < kProducedShownLimit
                    ? paths.length
                    : kProducedShownLimit;
                final int shownCount = cap < band ? cap : band;
                final int hidden = paths.length - shownCount;
                // React `.lane`: 6px row gap between the links row and the
                // folder action.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        for (int i = 0; i < shownCount; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Flexible(
                            child: _ProducedFileLink(
                              path: paths[i],
                              openLabel: t(
                                'produced.open',
                              ).replaceAll('{name}', paths[i]),
                              onPressed: onOpenFile == null
                                  ? null
                                  : () => onOpenFile!(paths[i]),
                            ),
                          ),
                        ],
                        if (hidden > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            producedMoreLabel(t, hidden),
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXs13,
                              height: 22 / 13,
                              color: aliases.labelTertiary,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ],
                      ],
                    ),
                    // React `.lane:has(.more) > .showFolder`: the folder
                    // action appears only when a remainder is visible.
                    if (hidden > 0 && canOpenPath && onOpenFile != null) ...[
                      const SizedBox(height: 6),
                      _ShowFolderLink(
                        label: t('produced.showInFolder'),
                        onPressed: () => onOpenFile!('.'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pluralized remainder copy (React `moreLabel`).
String producedMoreLabel(Translate t, int count) => count == 1
    ? t('produced.moreOne')
    : t('produced.more').replaceAll('{count}', '$count');

/// One openable file link: category glyph plus basename, link-colored at
/// rest and dotted-underlined on hover (React `.file`).
class _ProducedFileLink extends StatefulWidget {
  const _ProducedFileLink({
    required this.path,
    required this.openLabel,
    required this.onPressed,
  });

  final String path;
  final String openLabel;
  final VoidCallback? onPressed;

  @override
  State<_ProducedFileLink> createState() => _ProducedFileLinkState();
}

class _ProducedFileLinkState extends State<_ProducedFileLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    // --dsw-alias-link maps to the business-primary blue in Flutter.
    final Color color = aliases.stateBusinessPrimary;
    final TextStyle style = TextStyle(
      fontSize: DswTokens.fontSizeXs13,
      height: 22 / 13,
      fontWeight: FontWeight.w500,
      color: color,
      decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: color,
    );
    return Semantics(
      label: widget.openLabel,
      button: true,
      child: Tooltip(
        message: widget.path,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(color: color, size: 14),
                  child: DsLinkIcon(kind: classifyLinkPath(widget.path)),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    basename(widget.path),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `Show in folder` action (React `.showFolder`): tertiary at rest, secondary
/// with an underline on hover.
class _ShowFolderLink extends StatefulWidget {
  const _ShowFolderLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_ShowFolderLink> createState() => _ShowFolderLinkState();
}

class _ShowFolderLinkState extends State<_ShowFolderLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Color color = _hovered
        ? aliases.labelSecondary
        : aliases.labelTertiary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: IconThemeData(color: color, size: 14),
                child: const DsLinkIcon(kind: LinkIconKind.folder),
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXs13,
                  height: 20 / 13,
                  color: color,
                  decoration: _hovered
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
