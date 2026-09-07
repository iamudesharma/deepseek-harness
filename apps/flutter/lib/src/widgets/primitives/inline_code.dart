import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as md;
import 'package:markdown/markdown.dart' as m;

import '../../platform/clipboard.dart';
import '../../platform/open_external.dart';
import '../../theme/app_theme.dart';

/// Inline `code` pill — Flutter port of React `MarkdownText.module.css`
/// `:not(pre) > code` + file-mention / URL-promoted code.
///
/// React: mono 0.875em, bg `markdown-inline-code`, 0.5px `border-l1`,
/// radius 6px, padding 0 5px. URL-only tokens and resolver-known files keep
/// code chrome and gain link affordance + leading glyph.
class InlineCodeBuilder extends md.MarkdownElementBuilder {
  InlineCodeBuilder();

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    m.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Fenced blocks carry `language-*` on the inner code element — those
    // belong to [PreElementBuilder], not the inline pill.
    final String? cls = element.attributes['class'];
    if (cls != null && cls.contains('language-')) return null;
    final String value = element.textContent.replaceAll(RegExp(r'\r?\n|\r'), ' ');
    if (value.isEmpty) return const SizedBox.shrink();
    return _InlineCodePill(text: value);
  }
}

bool _isHttpUrl(String value) {
  final String v = value.trim();
  return (v.startsWith('http://') || v.startsWith('https://')) &&
      !v.contains(' ') &&
      v.length < 2048;
}

/// Heuristic file-path detector for code chrome. React resolves against a
/// real file vocabulary; Flutter has no such projection yet, so we style
/// path-shaped tokens as file mentions without claiming they open.
bool _looksLikeFile(String value) {
  final String v = value.trim();
  if (v.isEmpty || v.contains(' ') || v.contains('\n')) return false;
  if (v.length > 180) return false;
  if (v.startsWith('http://') || v.startsWith('https://')) return false;
  // src/App.jsx, ./index.html, vite.config.js, @scope/pkg/file.ts
  if (v.contains('/')) return v.contains('.');
  return RegExp(r'^[\w@.\-+]+\.[\w]{1,8}$').hasMatch(v);
}

class _InlineCodePill extends StatelessWidget {
  const _InlineCodePill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool isUrl = _isHttpUrl(text);
    final bool isFile = !isUrl && _looksLikeFile(text);
    final bool isLink = isUrl || isFile;
    final Color fg =
        isLink ? aliases.stateBusinessPrimary : aliases.labelPrimary;
    final Color bg = aliases.markdownInlineCode;
    final Color border = aliases.borderL1;

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isLink)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                isUrl ? Icons.link_rounded : Icons.code_rounded,
                size: 12,
                color: fg,
              ),
            ),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                fontSize: 12.5,
                height: 1.4,
                fontWeight:
                    isLink ? FontWeight.w500 : FontWeight.w400,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );

    if (isUrl) {
      return GestureDetector(
        onTap: () {
          final safe = sanitizeUrl(text.trim());
          if (safe != null) openExternal(safe);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: pill,
        ),
      );
    }
    if (isFile) {
      return GestureDetector(
        onTap: () => ClipboardHelper.copyWithFeedback(context, text),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Tooltip(message: 'Copy path: $text', child: pill),
        ),
      );
    }
    return pill;
  }
}

/// Inline-link tap helper shared by [DsMarkdown] and chat bodies.
void handleMarkdownLinkTap(String? href) {
  if (href == null) return;
  final safe = sanitizeUrl(href);
  if (safe != null) openExternal(safe);
}
