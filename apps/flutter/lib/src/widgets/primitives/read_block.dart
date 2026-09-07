import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'block.dart';

/// File-read display — Flutter port of `ReadBlock.tsx` + `ReadBlock.module.css`.
///
/// Header shows the file [path]; body shows [content] with a line-number
/// gutter and an optional highlighted range starting at [highlightStart].
/// Geometry mirrors the block family: `12px` radius on `markdownCodeBlock`
/// without the consumer-owned `8 + L2` mismatch. Capped at `kBlockCap=16`
/// with the unified `ceil(16/2)` head-tail slice and `… 其余 N 行` expander,
/// plus the floating `复制` control anchored top-right of the banner — the
/// same `DsBlockFrame` + `BlockCopyButton` + `BlockExpandButton` every
/// primitive shares.
class DsReadBlock extends ConsumerStatefulWidget {
  const DsReadBlock({
    super.key,
    required this.path,
    required this.content,
    this.highlightStart,
  });

  /// File path shown in the header.
  final String path;

  /// Full file content to display.
  final String content;

  /// 1-based start line of the highlighted range, if any.
  final int? highlightStart;

  @override
  ConsumerState<DsReadBlock> createState() => _DsReadBlockState();
}

class _DsReadBlockState extends ConsumerState<DsReadBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final List<String> lines = widget.content.split('\n');
    // Keep React parity: cap empty? show? head-tail arithmetic same as web.
    final BlockHeadTailCap cap = BlockHeadTailCap.compute(
      lines.length,
      kBlockCap,
      _expanded,
    );
    final List<String> visibleLines = cap.capped
        ? [
            ...lines.take(cap.headLines),
            ...lines.sublist(lines.length - cap.tailLines),
          ]
        : lines;
    final int hidden = cap.hidden;

    return DsBlockFrame(
      aliases: aliases,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header
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
                Icon(
                  Icons.description_outlined,
                  size: 14,
                  color: aliases.labelTertiary,
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Text(
                    widget.path,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      height:
                          DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                      fontFamily: DswTokens.fontFamilyCode,
                      fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                      color: aliases.labelSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DswTokens.spaceSm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: aliases.bgOverlay,
                    borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                  ),
                  child: Text(
                    '${lines.length} lines',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxxs11,
                      color: aliases.labelCaption,
                    ),
                  ),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                BlockCopyButton(copyText: widget.content, aliases: aliases),
              ],
            ),
          ),
          // Body
          Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < visibleLines.length; i++)
                    _lineRow(
                      lineNumber: cap.capped
                          ? (i < cap.headLines
                                ? i + 1
                                : lines.length -
                                      cap.tailLines +
                                      (i - cap.headLines) +
                                      1)
                          : i + 1,
                      text: visibleLines[i],
                      aliases: aliases,
                      highlighted:
                          widget.highlightStart != null &&
                          (i + 1) == widget.highlightStart,
                    ),
                  if (hidden > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(48, 4, 14, 8),
                      child: BlockExpandButton(
                        hidden: hidden,
                        expanded: _expanded,
                        onToggle: () => setState(() => _expanded = !_expanded),
                        aliases: aliases,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow({
    required int lineNumber,
    required String text,
    required DswAliases aliases,
    required bool highlighted,
  }) {
    final Color bg = highlighted
        ? aliases.stateBusinessTertiary.withValues(alpha: 0.6)
        : DswTokens.transparent;
    final Border? leftBorder = highlighted
        ? Border(
            left: BorderSide(color: aliases.stateBusinessPrimary, width: 2),
          )
        : null;

    return Container(
      decoration: BoxDecoration(color: bg, border: leftBorder),
      padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 40,
            child: Text(
              '$lineNumber',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                color: highlighted
                    ? aliases.stateBusinessPrimary
                    : aliases.labelCaption,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          SelectableText(
            text.isEmpty ? ' ' : text,
            style: TextStyle(
              fontSize: DswTokens.markdownCodeBlockSmallSize,
              height:
                  DswTokens.markdownCodeBlockSmallLineHeight /
                  DswTokens.markdownCodeBlockSmallSize,
              fontFamily: DswTokens.fontFamilyCode,
              fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
              color: aliases.labelPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
