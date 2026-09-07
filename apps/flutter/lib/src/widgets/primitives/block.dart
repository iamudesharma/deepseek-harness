import 'package:flutter/material.dart';

import '../../platform/clipboard.dart';
import '../../theme/app_theme.dart';

/// Shared block-family constants — mirrors the React block geometry
/// (`CodeBlock.module.css --dsl-code-block-border-radius: 12px`,
/// `DiffBlock.module.css --dsl-diff-radius: 12px`,
/// `ReadBlock.module.css --dsl-read-radius: 12px`,
/// `SearchBlock.module.css --dsl-search-radius: 12px`,
/// `TerminalBlock.module.css --dsl-terminal-radius: 12px`,
/// `WebBlock.module.css --dsl-web-radius: 12px`).
///
/// All card primitives render as the same 12px radius surface on
/// `markdownCodeBlock` without an outer border — the hairline (`borderL1`)
/// is owned by the `ioCard` in `ToolRow.module.css` or by a consumer that
/// explicitly opts-in, so the primitive never draws its own `borderL2`.
/// Consumer-owned radius/border previously produced the 8 vs 12 mismatch.
const double kBlockRadius = DswTokens.radiusLg;

/// Unified head-tail cap — all block primitives cap at 16 lines and slice
/// `ceil(16/2)=8` head / `8` tail, matching
/// `DEFAULT_DIFF_MAX_LINES = 16`, `DEFAULT_READ_MAX_LINES = 16`,
/// `DEFAULT_SEARCH_MAX_LINES = 16`, `DEFAULT_TERMINAL_MAX_LINES = 16`.
const int kBlockCap = 16;

/// Shared 12px-radius card surface used by every block primitive.
///
/// Mirrors the React family: `background: var(--dsw-alias-markdown-code-block)`,
/// `border-radius: 12px`, `overflow: hidden/clip` so a banner's sticky
/// or scrolling body respects the corner. No outer border — the ioCard's
/// `borderL1` owns the hairline when the card lives inside a ToolRow.
class DsBlockFrame extends StatelessWidget {
  const DsBlockFrame({
    super.key,
    required this.child,
    this.aliases,
    this.withBorder = false,
  });

  final Widget child;
  final DswAliases? aliases;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases a =
        aliases ??
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: a.markdownCodeBlock,
        borderRadius: BorderRadius.circular(kBlockRadius),
        border: withBorder ? Border.all(color: a.borderL1) : null,
      ),
      child: child,
    );
  }
}

/// Unified copy affordance — top-right floating text button that writes the
/// block's copy text and shows the localized feedback `复制` → `复制成功`.
///
/// Matches `ReadBlock.tsx` / `DiffBlock.tsx` / `SearchBlock.tsx` /
/// `TerminalBlock.tsx` copy controls: `font: var(--dsw-font-xs-13)`,
/// `color: var(--dsw-alias-label-secondary)`, absolute top 8 right 12 anchored
/// to the card.
class BlockCopyButton extends StatefulWidget {
  const BlockCopyButton({super.key, required this.copyText, this.aliases});

  final String copyText;
  final DswAliases? aliases;

  @override
  State<BlockCopyButton> createState() => _BlockCopyButtonState();
}

class _BlockCopyButtonState extends State<BlockCopyButton> {
  bool _copied = false;

  Future<void> _onCopy() async {
    if (_copied) return;
    final ok = await ClipboardHelper.copy(widget.copyText);
    if (!ok || !mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases a =
        widget.aliases ??
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return TextButton(
      onPressed: _onCopy,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: a.labelSecondary,
        textStyle: const TextStyle(
          fontSize: DswTokens.fontSizeXs13,
          fontWeight: FontWeight.w400,
          fontFamily: 'SF Pro',
        ),
      ),
      child: Text(_copied ? '复制成功' : '复制'),
    );
  }
}

/// Unified expand affordance — the `… 其余 N 行` / `收起` toggle that caps a
/// block's body at `kBlockCap` lines.
///
/// Renders as a full-width left-aligned text button in the muted tertiary
/// tone, mirroring `ReadBlock.module.css: .expand` / `DiffBlock.module.css: .expand` /
/// `SearchBlock.module.css: .expand` / `TerminalBlock.module.css: .expand`.
class BlockExpandButton extends StatelessWidget {
  const BlockExpandButton({
    super.key,
    required this.hidden,
    required this.expanded,
    required this.onToggle,
    this.aliases,
  });

  final int hidden;
  final bool expanded;
  final VoidCallback onToggle;
  final DswAliases? aliases;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases a =
        aliases ??
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return TextButton(
      onPressed: onToggle,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
        foregroundColor: a.labelTertiary,
        textStyle: const TextStyle(
          fontSize: DswTokens.fontSizeXs13,
          fontWeight: FontWeight.w400,
          fontFamily: 'SF Pro',
        ),
      ),
      child: Text(expanded ? '收起' : '… 其余 $hidden 行'),
    );
  }
}

/// Head-tail cap arithmetic shared by the block primitives — Dart mirror of
/// `head-tail-cap.ts` so long results use consistent head and tail slices.
///
/// `headLines = ceil(maxLines/2)`, `tailLines = remainder`, `capped = hidden>0 && !expanded`.
class BlockHeadTailCap {
  const BlockHeadTailCap({
    required this.hidden,
    required this.capped,
    required this.headLines,
    required this.tailLines,
  });

  factory BlockHeadTailCap.compute(int total, int maxLines, bool expanded) {
    final hidden = total - maxLines;
    final headLines = (maxLines / 2).ceil();
    return BlockHeadTailCap(
      hidden: hidden,
      capped: hidden > 0 && !expanded,
      headLines: headLines,
      tailLines: maxLines - headLines,
    );
  }

  final int hidden;
  final bool capped;
  final int headLines;
  final int tailLines;
}
