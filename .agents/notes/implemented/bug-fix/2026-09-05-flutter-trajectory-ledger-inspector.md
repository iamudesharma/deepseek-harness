# Agent Note: Flutter trajectory ledger and inspector match React

Status: implemented

English | [中文](2026-09-05-flutter-trajectory-ledger-inspector.zh.md)

## Problem

Flutter's trajectory view folded raw history into ledger rows instead of React's curated projection: every tool appeared twice (call row plus result row), control-plane noise (`permission/preset`, `sandbox/mode`, `approval/policy`, inbox splices, `session/title`) rendered as `SYSTEM` rows React never shows, each `assistant/chunk` delta became its own row, text-less assistants showed `—` instead of `(tool call only)`, and tool rows carried Flutter-invented per-tool semantic summaries instead of React's verbatim `name args → result-preview`. The inspector was thinner in the same way: fixed `Overview/Input/Output/Timing` tabs for tools with no `Schema` tab, no conditional Payload/Result tabs, no hierarchy link, no token rows, a bare Started/Duration timing block, and hardcoded English copy with no locale dictionary.

## Decision

The Flutter fold projects the same row model React's `layout.ts` plus `TrajectoryTable.tsx` define, and the inspector follows React's `detailTabs` matrix.

- One tool cell per `callId`: the call row carries raw `args` verbatim (2048→512 preview cap) and the result joins it as `outputDetail` with a separate `resultPreview` inline span; errors surface `error.code`; unpaired calls stay `running` with null duration; orphan results stand alone. `request/header` projects the only system rows (`Initial System Prompt` / `System Prompt Updated`) and feeds the per-tool schema capture (`description` + `parameters`) from the header catalog.
- Chunk deltas accumulate per step and emit one tail row only for steps with no settled message; settled steps drop their chunks. Text-less assistants driving tool calls (message blocks or same-step calls) label `(tool call only)`.
- Ledger text runs a `trajectoryPreviewText` port (2048 source cap, markdown-to-plain, single line, 512 cap with `…` only when cut); full text survives in preview/detail fields. Search indexes the same corpus React does (payload, result, thinking, schema, callId, source) with multi-term AND.
- The inspector switches per kind: tools get Summary (Status, Assistant-Message hierarchy jump, Payload/Result/Schema/Timing preview sections) plus conditional Payload/Result plus always-on Schema (catalog description and parameters tree, `Schema unavailable` fallback) and Timing (local/Unix Started toggle, thousand-separated millisecond durations, session-timestamp source, assistant TTFT/generation/throughput when chunk times and usage exist); messages get token rows; users get Source-tab navigation; system rows get System Prompt and catalog Tools tabs. Header shows the kind tag with `Turn N · Step M`.
- All new copy lives in a `trajectory` locale dictionary (`locales.dart`, En+Zh), including the renamed tabs (Summary/Preview/Raw/Source/Payload/Result/Schema/Timing).

## Alternatives considered

**Keep per-tool semantic summaries in trajectory rows.** Lost: React trajectory shows raw args verbatim; the semantic summaries belong to chat tool cards, and the two surfaces disagreed on every non-trivial row.

**Keep one row per chunk delta.** Lost: React never rows chunks; deltas update the in-flight cell in place, and replayed histories sprayed dozens of fragment rows.

**Cite empty usage-host assistants in ordering/shadows.** Lost: already decided in the turn-process note; the same gate (visible content required for sequence membership) applies here so compaction shadows stay exact.

**Port the request inspector and subtool expansion in the same change.** Lost: request numbering/usage accumulation and `code-dispatch` sub-rows need provider-level inputs the history fold does not have yet; ledger and inspector parity stood alone and shipped first.

## Consequences

The reporting session's real log folds to 78 curated rows (`USER hi`, `CONTEXT …`, `SYSTEM Initial System Prompt`, `TOOL bash {…} → ls output`, `(tool call only)` assistants, turn-2 audit flow) with schema descriptions resolving from the header catalog. Collapsed-turn summaries, timeline tooltips/TTFT splits, request inspection, and subtool rows remain deferred as documented in the new tests' scope and the prior tracker notes.

## Testing

- `trajectory_ledger_parity_test.dart`: 12 pass (folded tools, running calls, noise dropped, tool-call-only, chunk accumulation/vanishing, header prompt plus schema, usage/source survival, 512-cap rule).
- `trajectory_ledger_test.dart` (4 expectations updated to React behavior), `trajectory_plugin_test.dart`, `trajectory_fold_test.dart`: 43 pass total.
- Real-log fold of session `00b22885` verified curated shapes, then removed.
- `flutter analyze` on both touched/added library files: 0 errors (6 pre-existing infos elsewhere in the file).
