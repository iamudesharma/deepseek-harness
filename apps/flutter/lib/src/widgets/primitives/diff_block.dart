import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'block.dart';

/// Diff display block — Flutter port of `DiffBlock.tsx` + `DiffBlock.module.css`.
///
/// Shared geometry mirrors `CodeBlock`/`TerminalBlock`: `radius 12`, surface
/// `markdownCodeBlock`, no outer hairline (the `ioCard` owns `borderL1` when
/// the diff lives inside a ToolRow). Content keeps `pre` and scrolls
/// horizontally so indentation is preserved. Long diffs cap at `kBlockCap=16`
/// with the unified head-tail `ceil(16/2)` slice and a `… 其余 N 行` expander,
/// plus a floating `复制` control anchored top-right over the body — the same
/// `BlockCopyButton` + `BlockExpandButton` every block primitive shares, closing
/// the copy/expand divergence. No literal colors; all through [DswAliases].
class DsDiffBlock extends ConsumerStatefulWidget {
  const DsDiffBlock({
    super.key,
    required this.diff,
    this.splitView = false,
    this.filePath,
  });

  /// Raw unified diff text (e.g. output of `git diff`).
  final String diff;

  /// When true renders a two-column split view (added on the right,
  /// removed on the left where pairing is possible). Falls back to
  /// unified when hunk pairing is ambiguous.
  final bool splitView;

  /// Optional file path shown in the header bar.
  final String? filePath;

  @override
  ConsumerState<DsDiffBlock> createState() => _DsDiffBlockState();
}

class _DsDiffBlockState extends ConsumerState<DsDiffBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final ColorScheme scheme = theme.colorScheme;

    final List<_DiffLine> lines = _parse(widget.diff);
    final bool empty = lines.isEmpty;

    final BlockHeadTailCap cap = BlockHeadTailCap.compute(
      lines.length,
      kBlockCap,
      _expanded,
    );
    final List<_DiffLine> visibleLines = cap.capped
        ? [
            ...lines.take(cap.headLines),
            ...lines.sublist(lines.length - cap.tailLines),
          ]
        : lines;

    return DsBlockFrame(
      aliases: aliases,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header
          if (widget.filePath != null && widget.filePath!.isNotEmpty)
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
                    Icons.insert_drive_file_outlined,
                    size: 14,
                    color: aliases.labelTertiary,
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  Expanded(
                    child: Text(
                      widget.filePath!,
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
                  BlockCopyButton(copyText: widget.diff, aliases: aliases),
                  if (widget.splitView)
                    Container(
                      margin: const EdgeInsets.only(left: DswTokens.spaceSm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DswTokens.spaceSm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: aliases.bgOverlay,
                        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                      ),
                      child: Text(
                        'split',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxxs11,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: BlockCopyButton(copyText: widget.diff, aliases: aliases),
              ),
            ),
          if (empty)
            Padding(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Text(
                'No changes',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelCaption,
                ),
              ),
            )
          else if (widget.splitView)
            _SplitView(lines: visibleLines, aliases: aliases, scheme: scheme)
          else
            _UnifiedView(lines: visibleLines, aliases: aliases, scheme: scheme),
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
          // Footer — `└ +A -R · N file(s)` parity placeholder
          if (!empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                '└ +${lines.where((l) => l.kind == _DiffKind.add).length} -${lines.where((l) => l.kind == _DiffKind.remove).length} · 1 file',
                style: TextStyle(
                  fontSize: DswTokens.markdownCodeBlockSmallSize,
                  color: aliases.labelTertiary,
                  fontFamily: DswTokens.fontFamilyCode,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_DiffLine> _parse(String raw) {
    if (raw.trim().isEmpty) return const <_DiffLine>[];
    final List<String> rawLines = raw.split('\n');
    return rawLines.map((String l) {
      if (l.startsWith('+++') || l.startsWith('---')) {
        return _DiffLine(kind: _DiffKind.header, text: l);
      }
      if (l.startsWith('@@')) {
        return _DiffLine(kind: _DiffKind.hunk, text: l);
      }
      if (l.startsWith('+')) {
        return _DiffLine(kind: _DiffKind.add, text: l);
      }
      if (l.startsWith('-')) {
        return _DiffLine(kind: _DiffKind.remove, text: l);
      }
      return _DiffLine(kind: _DiffKind.context, text: l);
    }).toList();
  }
}

enum _DiffKind { add, remove, context, hunk, header }

class _DiffLine {
  const _DiffLine({required this.kind, required this.text});
  final _DiffKind kind;
  final String text;
}

class _UnifiedView extends StatelessWidget {
  const _UnifiedView({
    required this.lines,
    required this.aliases,
    required this.scheme,
  });

  final List<_DiffLine> lines;
  final DswAliases aliases;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < lines.length; i++) _lineRow(lines[i], i),
        ],
      ),
    );
  }

  Widget _lineRow(_DiffLine line, int index) {
    late final Color bg;
    late final Color fg;
    switch (line.kind) {
      case _DiffKind.add:
        bg = aliases.stateSuccessTertiary;
        fg = aliases.stateSuccessPrimary;
        break;
      case _DiffKind.remove:
        bg = aliases.stateErrorSecondary.withValues(alpha: 0.15);
        fg = aliases.stateErrorPrimary;
        break;
      case _DiffKind.hunk:
        bg = aliases.stateBusinessTertiary;
        fg = aliases.stateBusinessPrimary;
        break;
      case _DiffKind.header:
        bg = aliases.bgOverlay;
        fg = aliases.labelTertiary;
        break;
      case _DiffKind.context:
        bg = DswTokens.transparent;
        fg = aliases.labelPrimary;
        break;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                color: aliases.labelCaption,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          SelectableText(
            line.text.isEmpty ? ' ' : line.text,
            style: TextStyle(
              fontSize: DswTokens.markdownCodeBlockSmallSize,
              height:
                  DswTokens.markdownCodeBlockSmallLineHeight /
                  DswTokens.markdownCodeBlockSmallSize,
              fontFamily: DswTokens.fontFamilyCode,
              fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitView extends StatelessWidget {
  const _SplitView({
    required this.lines,
    required this.aliases,
    required this.scheme,
  });

  final List<_DiffLine> lines;
  final DswAliases aliases;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // Pair adjacent remove/add lines where possible; otherwise show
    // unpaired lines spanning the matching column.
    final List<_SplitRow> rows = <_SplitRow>[];
    int i = 0;
    while (i < lines.length) {
      final _DiffLine cur = lines[i];
      if (cur.kind == _DiffKind.remove &&
          i + 1 < lines.length &&
          lines[i + 1].kind == _DiffKind.add) {
        rows.add(_SplitRow(left: cur, right: lines[i + 1]));
        i += 2;
      } else if (cur.kind == _DiffKind.hunk || cur.kind == _DiffKind.header) {
        rows.add(_SplitRow(span: cur));
        i++;
      } else if (cur.kind == _DiffKind.remove) {
        rows.add(_SplitRow(left: cur));
        i++;
      } else if (cur.kind == _DiffKind.add) {
        rows.add(_SplitRow(right: cur));
        i++;
      } else {
        // context spans both
        rows.add(_SplitRow(span: cur));
        i++;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[for (final _SplitRow r in rows) _splitRow(r)],
      ),
    );
  }

  Widget _splitRow(_SplitRow row) {
    if (row.span != null) {
      final Color bg = row.span!.kind == _DiffKind.hunk
          ? aliases.stateBusinessTertiary
          : row.span!.kind == _DiffKind.header
          ? aliases.bgOverlay
          : DswTokens.transparent;
      final Color fg = row.span!.kind == _DiffKind.hunk
          ? aliases.stateBusinessPrimary
          : row.span!.kind == _DiffKind.header
          ? aliases.labelTertiary
          : aliases.labelPrimary;
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(
          horizontal: DswTokens.spaceSm,
          vertical: 1,
        ),
        child: Text(
          row.span!.text.isEmpty ? ' ' : row.span!.text,
          style: TextStyle(
            fontSize: DswTokens.markdownCodeBlockSmallSize,
            fontFamily: DswTokens.fontFamilyCode,
            fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
            color: fg,
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _cell(row.left, isLeft: true),
          Container(width: 1, color: aliases.borderL2),
          _cell(row.right, isLeft: false),
        ],
      ),
    );
  }

  Widget _cell(_DiffLine? line, {required bool isLeft}) {
    if (line == null) {
      return Container(width: 320, color: aliases.bgSkeleton);
    }
    final bool isAdd = line.kind == _DiffKind.add;
    final bool isRemove = line.kind == _DiffKind.remove;
    final Color bg = isAdd
        ? aliases.stateSuccessTertiary
        : isRemove
        ? aliases.stateErrorSecondary.withValues(alpha: 0.15)
        : DswTokens.transparent;
    final Color fg = isAdd
        ? aliases.stateSuccessPrimary
        : isRemove
        ? aliases.stateErrorPrimary
        : aliases.labelPrimary;
    return Container(
      width: 320,
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceSm,
        vertical: 1,
      ),
      child: Text(
        line.text.isEmpty ? ' ' : line.text,
        style: TextStyle(
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          fontFamily: DswTokens.fontFamilyCode,
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
          color: fg,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _SplitRow {
  const _SplitRow({this.left, this.right, this.span});
  final _DiffLine? left;
  final _DiffLine? right;
  final _DiffLine? span;
}
