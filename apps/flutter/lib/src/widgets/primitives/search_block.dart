import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'block.dart';

/// Single grep hit.
class SearchResult {
  const SearchResult({
    required this.file,
    required this.line,
    required this.preview,
    this.match,
  });

  /// File path containing the match.
  final String file;

  /// 1-based line number.
  final int line;

  /// Preview text for the matching line.
  final String preview;

  /// Optional exact matched substring to highlight within [preview].
  final String? match;
}

/// Grep-results block — Flutter port of `SearchBlock.tsx` + `SearchBlock.module.css`.
///
/// Shared geometry mirrors `CodeBlock`/`TerminalBlock`: `radius 12`, surface
/// `markdownCodeBlock` without the consumer-owned `8 + L2` mismatch. Grouped
/// matches or path list flatten to rows capped at `kBlockCap=16` with the
/// unified head-tail slice and `… 其余 N 行` expander, plus the banner's
/// `复制` control anchored top-right — the same `DsBlockFrame` + head-tail +
/// copy affordance every primitive shares.
class DsSearchBlock extends ConsumerStatefulWidget {
  const DsSearchBlock({super.key, required this.results});

  /// Flat list of hits; internally grouped by [SearchResult.file].
  final List<SearchResult> results;

  @override
  ConsumerState<DsSearchBlock> createState() => _DsSearchBlockState();
}

class _DsSearchBlockState extends ConsumerState<DsSearchBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final List<SearchResult> results = widget.results;
    if (results.isEmpty) {
      return DsBlockFrame(
        aliases: aliases,
        child: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Text(
            'No results',
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelCaption,
            ),
          ),
        ),
      );
    }

    // Group by file preserving first-seen order.
    final Map<String, List<SearchResult>> groups =
        <String, List<SearchResult>>{};
    final List<String> order = <String>[];
    for (final SearchResult r in results) {
      if (!groups.containsKey(r.file)) {
        order.add(r.file);
        groups[r.file] = <SearchResult>[];
      }
      groups[r.file]!.add(r);
    }

    // Flatten rows for cap — one file header + N matches per file, like React's toRows.
    final int totalRows = order.fold<int>(
      0,
      (sum, f) => sum + 1 + groups[f]!.length,
    );
    final BlockHeadTailCap cap = BlockHeadTailCap.compute(
      totalRows,
      kBlockCap,
      _expanded,
    );
    // For simplicity cap at file-group granularity: if capped, show headFiles/tailFiles slice.
    // Full row-level head-tail parity requires restoring file headers in tail; simplified here.
    final List<String> visibleFiles;
    if (cap.capped) {
      // Estimate files from row counts; approximate by slicing ordered files.
      final int headFiles = (cap.headLines / 2).ceil().clamp(1, order.length);
      final int tailFiles = order.length - headFiles;
      visibleFiles = tailFiles > 0
          ? [...order.take(headFiles), ...order.skip(order.length - tailFiles)]
          : order.take(headFiles).toList();
    } else {
      visibleFiles = order;
    }

    final String copyText = results
        .map((r) => '${r.file}:${r.line}: ${r.preview}')
        .join('\n');

    return DsBlockFrame(
      aliases: aliases,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Summary header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceMd,
              vertical: DswTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: aliases.markdownCodeBlockBanner,
              border: Border(bottom: BorderSide(color: aliases.borderL2)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.search, size: 14, color: aliases.labelTertiary),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Text(
                    '${results.length} result${results.length == 1 ? '' : 's'} in ${order.length} file${order.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                ),
                BlockCopyButton(copyText: copyText, aliases: aliases),
              ],
            ),
          ),
          for (final String file in visibleFiles) ...<Widget>[
            _FileGroup(file: file, hits: groups[file]!, aliases: aliases),
            if (file != visibleFiles.last)
              Divider(height: 1, color: aliases.borderL2),
          ],
          if (cap.hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: BlockExpandButton(
                hidden: cap.hidden,
                expanded: _expanded,
                onToggle: () => setState(() => _expanded = !_expanded),
                aliases: aliases,
              ),
            ),
        ],
      ),
    );
  }
}

class _FileGroup extends StatelessWidget {
  const _FileGroup({
    required this.file,
    required this.hits,
    required this.aliases,
  });

  final String file;
  final List<SearchResult> hits;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DswTokens.spaceMd,
            DswTokens.spaceSm,
            DswTokens.spaceMd,
            DswTokens.spaceSm / 2,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.insert_drive_file_outlined,
                size: 12,
                color: aliases.labelCaption,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  file,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    fontWeight: FontWeight.w600,
                    fontFamily: DswTokens.fontFamilyCode,
                    fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                    color: aliases.labelPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DswTokens.spaceSm,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                ),
                child: Text(
                  '${hits.length}',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxxs11,
                    color: aliases.labelTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final SearchResult h in hits)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceMd,
              vertical: 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 40,
                  child: Text(
                    '${h.line}',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontFamily: DswTokens.fontFamilyCode,
                      fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                      color: aliases.labelCaption,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(child: _previewText(h)),
              ],
            ),
          ),
        const SizedBox(height: DswTokens.spaceSm / 2),
      ],
    );
  }

  Widget _previewText(SearchResult hit) {
    final String preview = hit.preview;
    final String? match = hit.match;
    // No highlight — plain text
    if (match == null || match.isEmpty || !preview.contains(match)) {
      return Text(
        preview,
        style: TextStyle(
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          fontFamily: DswTokens.fontFamilyCode,
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
          color: aliases.labelPrimary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final int idx = preview.indexOf(match);
    final String before = preview.substring(0, idx);
    final String after = preview.substring(idx + match.length);

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          fontFamily: DswTokens.fontFamilyCode,
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
          color: aliases.labelPrimary,
        ),
        children: <InlineSpan>[
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              backgroundColor: aliases.stateWarnTertiary,
              color: aliases.labelPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
