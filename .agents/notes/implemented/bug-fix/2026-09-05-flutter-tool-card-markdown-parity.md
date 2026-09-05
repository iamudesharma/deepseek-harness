# Agent Note: Flutter tool rows derive React-parity summaries and markdown highlights code

Status: implemented

English | [中文](2026-09-05-flutter-tool-card-markdown-parity.zh.md)

## Problem

Flutter chat tool rows showed the tool name plus the first line of the raw
result string, so a `write` row printed the model-facing
`<path>/Volumes/…/CartDrawer.jsx</path>` envelope and an absolute path instead
of React's `Write · src/components/CartDrawer.jsx +88 −0`. No diff stat, no
per-tool summary, and no path relativization existed anywhere on the Flutter
side, while assistant markdown rendered through the discontinued
`flutter_markdown` package with a code block that documented itself as having
no syntax highlighting.

## Decision

Flutter owns the same client-derived presentation React owns: rows derive
from the wire tool name plus raw argument JSON plus durable result metadata,
never from result text.

- `apps/flutter/lib/src/plugins/tool/presentation/` carries the pure models:
  `tool_row_model.dart` (variant classification, title keys, args-derived
  summary, openable file path, error/interrupted state), `diff_model.dart`
  (intended args diff while running, applied `meta.diffs` hunks when settled,
  write-only args fallback, `+N −N` totals with React's trailing-newline
  rule), `terminal_model.dart` (foreground vs `run_in_background`,
  description-first summary, `[exit code: N]` / `[killed by signal: X]`
  parsing, workdir resolution), `todo_model.dart` (`N/M completed · active`
  plus parallel-active extra), `read_model.dart` (envelope + metadata
  narrowing), and `path_utils.dart` (`relativizeToCwd` plus the existing
  home abbreviation).
- `ToolCall` keeps the raw `arguments` JSON in `argsRaw` and the durable
  `meta`/`errorCode` off `tool/result`; `toolCallsFromHistory` decodes the
  canonical `arguments`-string shape (legacy map shapes still decode).
  `ToolNode` folds and preserves the same three facts through settlement,
  subcall projection, and the chat-view adapter.
- The chat rows (`keyed_tool_card.dart`), its no-registry fallback, and the
  legacy `ToolCallTree` rows render localized titles (`Write`, `Bash`,
  `Update to-do list`, `Think`), args-derived summaries
  (`description` for bash, todo counts, relative file paths), the `+N −N`
  suffix for write/edit, failure-first-line on errors, and a host open
  handoff for file summaries gated on `canOpenWorkspacePath`. The reasoning
  row titles itself `Think`/`思考` from locale.
- The trajectory ledger derives the same args summary for `tool/call` cells
  and flattens `tool/result` message blocks instead of previewing raw JSON.
- Markdown moves to the maintained `flutter_markdown_plus` (the official
  `replacedBy` of the discontinued `flutter_markdown`) with the existing
  `PreElementBuilder` ported unchanged; fenced code highlights through the
  maintained `syntax_highlight` TextMate grammars with a themed span tree,
  falling back to plain monospace text for unknown languages and while
  grammars load. Copy button, language label, link sanitization, and
  selectable prose are unchanged.
- Copy lives in the `conversation` namespace dictionaries (`tool.title.*`,
  `todo.*`, `message.think`) in both languages.

## Alternatives considered

**Parse the `<path>` result envelope for the write row.** Lost: the envelope
is model-facing text, not a contract; React reads the call arguments
(`file_path`) and the durable `meta.diffs`. Envelope parsing would bind the
row to output wording and break on creates.

**Adopt `markdown_widget` for highlighting.** Lost: unmaintained since April
2025 and pulls its own renderer plus stale `highlight 0.7.0`; the chosen pair
keeps the current renderer (a drop-in fork) and adds highlighting from a
2025-maintained package with VSCode-style themes.

**Adopt `gpt_markdown` as the whole renderer.** Lost: it replaces the
renderer, fonts, and math stack at once and would force a visual redesign;
the shipped change keeps `MarkdownBody` semantics and only adds spans inside
the existing code block.

**Hand-roll a Dart highlighter.** Lost: the repo prefers maintained
dependencies over hand-rolling when they delete owned code; a grammar fork
would add an unmaintained parser surface for zero product gain.

**Thread the legacy `HistoryEntry.view` through to rows.** Lost: the wire no
longer sends it since the client-derived-presentation decision; rows read
`meta`, and the legacy field stays decode-only.

## Consequences

Tool rows match React's collapsed lines (`Write · <relative path> +N −N`,
`Bash · <description>`, `Update to-do list · N/M completed · <item>`,
`Think ·`) with no raw envelope text and no absolute workspace prefixes. Code
fences highlight supported grammars in both themes and degrade to plain text
otherwise. The `retireOptimisticWithHistory` view helper missing from the
working tree is defined (any-match retirement), and the stale
`sendMessage` test fake carries the current `requestId` face. Deferred to
their owners: deleting dead `message_list.dart`, retiring `DsCodeBlock`'s
hardcoded copy, and re-verifying the `component.ui-tool.ToolCallTree`,
`screen.ui-tool`, `route.conversation.chat.node`, and `screen.trajectory`
tracker rows against the new rendering.

## Testing

- `test/unit/tool_presentation_test.dart`: 23 unit cases over row
  classification/summary/relativization, diff totals/intended/applied/
  fallback, terminal markers/background/summary, todo counts, read envelope
  and meta bounds, and wire decoding.
- `test/widgets/tool_row_test.dart`: 4 widget cases proving the collapsed
  row shows the relative path plus `+2 −0` with no `<path>` text, the bash
  description, the todo counts line, and the failure line.
- `test/widgets/code_block_test.dart`, `test/widgets/conversation_test.dart`,
  `test/plugins/conversation_render_test.dart`,
  `test/plugins/ws_chat/tool_plugin_test.dart` (updated to ProviderScope
  plus localized titles), and `test/conversation/chat_ui_adapter_test.dart`:
  80 tests green. `test/widgets/migrated_integration_test.dart` still fails
  to compile on the untouched in-flight `directory_browser.dart`
  `ResponsiveBreakpoints.responsiveValue` breakage.
