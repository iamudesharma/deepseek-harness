import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/open_external.dart';
import '../../theme/dsw_tokens.dart';

/// Markdown + code + math wrapper mirroring ui-primitives markdown.
/// Sanitizes URLs like React `sanitizeUrl` (http/https/mailto only) and opens
/// external links via [openExternal] (browser `target="_blank"` semantics).
class DsMarkdown extends ConsumerWidget {
  const DsMarkdown({super.key, required this.data, this.selectable = true});
  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontFamily: DswTokens.fontFamily,
      fontSize: 14,
      height: 1.6,
      color: colors.onSurface,
    );
    return md.MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: md.MarkdownStyleSheet(
        p: textStyle,
        a: TextStyle(
          color: colors.primary,
          decoration: TextDecoration.underline,
        ),
        code: TextStyle(
          fontFamily: DswTokens.fontFamilyCode,
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
          fontSize: 13,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        ),
      ),
      onTapLink: (text, href, title) {
        if (href == null) return;
        // Inline code that is exactly a URL is handled by MarkdownBody as a link
        // as well; sanitizeUrl guards javascript:/data: etc.
        final safe = sanitizeUrl(href);
        if (safe != null) {
          openExternal(safe);
        }
      },
    );
  }
}
