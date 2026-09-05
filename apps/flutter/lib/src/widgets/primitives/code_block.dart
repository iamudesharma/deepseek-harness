import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:markdown/markdown.dart' as m;

import '../../platform/clipboard.dart';
import '../../theme/dsw_tokens.dart';

/// Fenced code block — Flutter port of the settled arm of React
/// `CodeBlock.tsx` (`ui-primitives`): a block container with a header row
/// (grammar label + copy button) over verbatim monospace text.
///
/// Deliberately narrower than React: no syntax highlighting (plain text in
/// the code face) and no viewport-lazy grammar loading. Inline code is out
/// of scope and keeps `MarkdownStyleSheet.code`.
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

  String get _display {
    final String code = widget.code;
    return code.endsWith('\n') ? code.substring(0, code.length - 1) : code;
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
    final ColorScheme colors = theme.colorScheme;
    final String? language = widget.language?.trim();
    return Container(
      key: const ValueKey('code-block'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    language != null && language.isNotEmpty ? language : 'code',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('code-block-copy'),
                tooltip: 'Copy',
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_outlined,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
                onPressed: _copy,
                style: IconButton.styleFrom(
                  minimumSize: const Size(28, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ],
          ),
          Divider(height: 1, color: colors.outlineVariant),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SelectableText(
              _display,
              style: TextStyle(
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                fontSize: 13,
                height: 1.5,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
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
