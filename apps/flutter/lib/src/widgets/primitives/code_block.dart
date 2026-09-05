import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as md;
import 'package:markdown/markdown.dart' as m;

import '../../platform/clipboard.dart';
import '../../theme/app_theme.dart';
import 'code_highlight.dart' as highlight;

/// Fenced code block — Flutter port of the settled arm of React
/// `CodeBlock.tsx` (`ui-primitives`): a block container with a header row
/// (grammar label + copy button) over syntax-highlighted monospace text.
///
/// Highlighting uses the maintained `syntax_highlight` TextMate grammars (the
/// pub equivalent of React's shiki): supported fences render themed spans,
/// unknown languages fall back to plain text in the code face. Grammars load
/// asynchronously from package assets, so the first frame is plain text and
/// rebuilds highlighted once ready.
class CodeBlock extends StatefulWidget {
  /// Creates a code block.
  const CodeBlock({super.key, required this.code, this.language});

  /// Verbatim source text (display trims one trailing newline like React).
  final String code;

  /// Fence info string, or null for an unlabeled block.
  final String? language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  bool _highlightReady = false;
  bool _highlightWanted = false;

  String get _display {
    final String code = widget.code;
    return code.endsWith('\n') ? code.substring(0, code.length - 1) : code;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool wanted = highlight.highlighterLanguageFor(widget.language) != null;
    _highlightWanted = wanted;
    if (!wanted) return;
    highlight.ensureCodeHighlightReady(dark: dark).then((ready) {
      if (!mounted) return;
      if (ready != _highlightReady) setState(() => _highlightReady = ready);
    });
  }

  @override
  void didUpdateWidget(covariant CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language || oldWidget.code != widget.code) {
      didChangeDependencies();
    }
  }

  Future<void> _copy() async {
    final bool ok = await ClipboardHelper.copy(_display);
    if (!mounted || !ok) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String? language = widget.language?.trim();
    final String langLabel =
        language != null && language.isNotEmpty ? language : 'code';
    return Container(
      key: const ValueKey('code-block'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aliases.borderL2),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: aliases.markdownCodeBlockBanner,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    langLabel,
                    style: TextStyle(
                      fontFamily: DswTokens.fontFamilyCode,
                      fontFamilyFallback:
                          DswTokens.fontFamilyCodeFallback,
                      fontSize: 12,
                      height: 18 / 12,
                      color: aliases.labelPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _CopyTextButton(
                  copied: _copied,
                  aliases: aliases,
                  onPressed: _copy,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: aliases.borderL2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _CodeBody(
              display: _display,
              language: language,
              highlightReady: _highlightReady && _highlightWanted,
              style: TextStyle(
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                fontSize: DswTokens.markdownCodeBlockSize,
                height: DswTokens.markdownCodeBlockLineHeight /
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

/// Banner copy control — text button like React `CodeBlock.tsx` (`Copy` /
/// `Copied`), not an icon-only button.
class _CopyTextButton extends StatelessWidget {
  const _CopyTextButton({
    required this.copied,
    required this.aliases,
    required this.onPressed,
  });
  final bool copied;
  final DswAliases aliases;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: const ValueKey('code-block-copy'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            copied ? Icons.check_rounded : Icons.copy_outlined,
            size: 13,
            color: aliases.labelSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            copied ? 'Copied' : 'Copy',
            style: TextStyle(
              fontSize: 12,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Code body: highlighted spans when grammars are ready, plain text otherwise.
class _CodeBody extends StatelessWidget {
  const _CodeBody({
    required this.display,
    required this.language,
    required this.highlightReady,
    required this.style,
  });

  final String display;
  final String? language;
  final bool highlightReady;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (highlightReady) {
      final bool dark = Theme.of(context).brightness == Brightness.dark;
      final span = highlight.highlightCodeSpan(
        display,
        language,
        dark: dark,
        baseStyle: style,
      );
      if (span != null) return SelectableText.rich(span);
    }
    return SelectableText(display, style: style);
  }
}

/// `MarkdownElementBuilder` for `pre`: replaces flutter_markdown's default
/// flat fenced-block rendering with [CodeBlock].
///
/// Reads the code from the element's text content and the grammar hint from
/// the inner `code` element's `language-*` class (how `package:markdown`
/// carries the fence info string). Pure rebuild from the element — no
/// per-instance highlight sessions — so growing streamed fences cannot
/// corrupt state.
class PreElementBuilder extends md.MarkdownElementBuilder {
  PreElementBuilder();

  @override
  Widget? visitText(m.Text text, TextStyle? preferredStyle) {
    // flutter_markdown flushes (and clears) the anonymous parent inline only
    // when it carries children; a null text child leaves it behind and trips
    // the end-of-build `_inlines.isEmpty` assert on fence-first documents.
    // The placeholder is discarded: `visitElementAfterWithContext` below
    // returns the real block, which replaces the default child wholesale.
    return const SizedBox.shrink();
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    m.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String text = element.textContent;
    String? language;
    for (final m.Node child in element.children ?? <m.Node>[]) {
      if (child is m.Element) {
        final String? className = child.attributes['class'];
        if (className != null) {
          for (final String token in className.split(' ')) {
            if (token.startsWith('language-') &&
                token.length > 'language-'.length) {
              language = token.substring('language-'.length);
            }
          }
        }
      }
    }
    return CodeBlock(code: text, language: language);
  }
}
