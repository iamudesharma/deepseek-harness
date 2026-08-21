# Dependency Inventory

Audited 2026-08-21 from `packages/client/*/package.json` runtime dependencies. Decision order per the dependency-mapping skill: maintained pub package > adapter > custom > not-applicable.

## Key package dependencies and Flutter decisions

| npm dependency | Used by | Purpose | Flutter decision |
|---|---|---|---|
| `react`, `react-dom` | ui-primitives (peer surface) | renderer | not-applicable — Flutter replaces React |
| `shiki`, `@shikijs/langs` | ui-primitives | syntax highlighting | adapter — highlight via Flutter `highlight`/`flutter_highlight` or server-side tokens; keep visual parity target |
| `katex` | ui-primitives | math rendering | adapter — `flutter_math_fork` (KaTeX-compatible TeX renderer) |
| `mdast-*`, `micromark-*` | ui-primitives | markdown parse pipeline | custom — port parse/incremental semantics onto a Dart markdown AST (`markdown` pkg) preserving GFM+math extensions; incremental streaming parser is owned code |
| `anser` | ui-primitives | ANSI → styled text | maintained pub: `ansi_up`-equivalent via custom minimal ANSI parser (small, owned) or `dart_ansi`; decide at implementation, parity-tested against TerminalBlock goldens |
| `clsx` | ui-conversation, ui-tool | class join | not-applicable — Dart string join |
| `immer`, `zustand` | runtime | immutable updates + store | maintained pub: `riverpod` + `freezed`/built-in copyWith replace both; state-shape parity via replay tests |
| `@deepseek-ai/schemastery` | connection, ui-conversation | schema validation | adapter — typed Dart models + manual validation at wire boundary (contracts are closed unions) |
| `ws` | connection | WebSocket server half (node) | not-applicable — client uses `web_socket_channel` |

## Flutter-side additions (pub)

Already in `apps/flutter/pubspec.yaml`: `flutter_riverpod`, `go_router`, `http`, `web_socket_channel`, `file_picker`, `window_manager` (desktop-only, conditional import).

Adopted 2026-08-21: `flutter_gen_ai_chat_ui: ^2.15.0` (MIT, verified publisher, 98 likes) — maintained pub. Covers the conversation-list need that the tracker records under `conversation.node-assembler` / `conversation.streaming-tail` / `tool.lifecycle-pairing`: markdown + LaTeX + streaming word-by-word, thinking→answer morph, `ChatMessage.rich` tool-call cards, citations. Transitives `flutter_markdown_plus`, `flutter_math_fork`, `flutter_streaming_text_markdown`, `google_fonts`, `shimmer`, `url_launcher` satisfy the expected math/highlighting rows (`katex`, `shiki`) via the package's built-in renderers.

Expected further additions during migration: `shared_preferences` or host-backed settings storage, `image_picker` (attachments), `file_selector` (macOS pickers).

## Rules applied

- Hand-rolling justified only where it deletes owned code/tests (markdown incremental parser is owned code — port it; do not substitute a different markdown dialect).
- Platform plugins need web + macOS stories (conditional imports for desktop-only).
- Every decision lands in tracker rows via the Dependency Mapping Agent.

## Sources

- `packages/client/ui-primitives/package.json`
- `packages/client/ui-conversation/package.json`
- `packages/client/ui-tool/package.json`
- `packages/client/runtime/package.json`
- `packages/client/connection/package.json`
- `apps/flutter/pubspec.yaml`
