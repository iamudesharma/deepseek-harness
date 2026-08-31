import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'block.dart';

/// Code surface — Flutter port of `CodeBlock.tsx` + `CodeBlock.module.css`.
///
/// Renders a `markdownCodeBlock` surface at the block-family radius `12` with a
/// banner row (`language` + copy control) over the `pre` content. Chrome
/// matches deepsuite `@deepseek/md` code blocks; token colors stay on shiki
/// `--shiki-*` when highlighted. Geometry is owned by the primitive — the
/// consumer never supplies the radius/border, closing the `12 vs 8` pipeline
/// divergence. No literal colors; all through [DswAliases].
class DsCodeBlock extends ConsumerStatefulWidget {
  const DsCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.copyLabel = '复制',
    this.copiedLabel = '复制成功',
  });

  final String code;
  final String? language;
  final String copyLabel;
  final String copiedLabel;

  @override
  ConsumerState<DsCodeBlock> createState() => _DsCodeBlockState();
}

class _DsCodeBlockState extends ConsumerState<DsCodeBlock> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String trimmed = widget.code.endsWith('\n')
        ? widget.code.substring(0, widget.code.length - 1)
        : widget.code;
    return DsBlockFrame(
      aliases: aliases,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: aliases.markdownCodeBlockBanner),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      height: 18 / 12,
                      fontFamily: DswTokens.fontFamilyCode,
                      fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                      color: aliases.labelPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                BlockCopyButton(copyText: trimmed, aliases: aliases),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: aliases.markdownCodeBlock,
            child: SelectableText(
              trimmed,
              style: TextStyle(
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                fontSize: DswTokens.markdownCodeBlockSize,
                height:
                    DswTokens.markdownCodeBlockLineHeight /
                    DswTokens.markdownCodeBlockSize,
                color: aliases.labelPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
