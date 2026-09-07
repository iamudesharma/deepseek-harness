import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/open_external.dart';
import '../../theme/app_theme.dart';
import 'code_block.dart' show PreElementBuilder;
import 'inline_code.dart' show InlineCodeBuilder, handleMarkdownLinkTap;

/// Markdown + code + math wrapper mirroring ui-primitives markdown.
/// Sanitizes URLs like React `sanitizeUrl` (http/https/mailto only) and opens
/// external links via [openExternal] (browser `target="_blank"` semantics).
///
/// Inline `code` renders as a 6px pill (`markdown-inline-code` + `border-l1`,
/// mono 0.875em) with link-blue file/URL promotion; fenced blocks render
/// through [PreElementBuilder] with banner + copy + highlight.
class DsMarkdown extends ConsumerWidget {
  const DsMarkdown({super.key, required this.data, this.selectable = true});
  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final TextStyle textStyle = TextStyle(
      fontFamily: DswTokens.fontFamily,
      fontSize: 14,
      height: 1.6,
      color: aliases.labelPrimary,
    );
    return md.MarkdownBody(
      data: data,
      selectable: selectable,
      builders: {
        'pre': PreElementBuilder(),
        'code': InlineCodeBuilder(),
      },
      styleSheet: md.MarkdownStyleSheet(
        p: textStyle,
        a: TextStyle(
          color: aliases.stateBusinessPrimary,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
        code: TextStyle(
          fontFamily: DswTokens.fontFamilyCode,
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
          fontSize: 12.5,
          color: aliases.labelPrimary,
          backgroundColor: aliases.markdownInlineCode,
        ),
        h1: textStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        h2: textStyle.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
        h3: textStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        listBullet: TextStyle(color: aliases.labelSecondary),
        blockquote: TextStyle(
          color: aliases.labelSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
      onTapLink: (text, href, title) => handleMarkdownLinkTap(href),
    );
  }
}
