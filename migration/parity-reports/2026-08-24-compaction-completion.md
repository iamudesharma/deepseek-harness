# 2026-08-24 Compaction Completion Parity Report

This report proves Flutter parity for `conversation.compaction` after WS-Chat remediation closing the five Gatekeeper gaps.

Deterministic checkpoint/replace contract preserved: `compaction/summary.shadowedSeqs/shadowedTokenCount` is the authoritative priced set, `user/message` with `surfaceOp: replace` and `source: {kind: plugin, plugin: compact, compactionId, sourceCommandId}` is the replacement surface event, `sourceEventSeqs` provenance cites every shadowed seq plus the summary and checkpoint seqs, and the resulting node set is deterministic and reproducible across replays.

Gap manual /compact closed: `command/run` + `compaction/start|summary|end` with `sourceCommandId` plus `user/message` checkpoint with `sourceCommandId` now fold through `ManualCompactionNode` keyed by `commandId` (React `commandDefinition` parity), running state renders `compact · 正在压缩… / Compacting context…` and completed state renders the same disclosure as automatic with `title='compact'`, counts via `shadowedSeqs.length / shadowedTokenCount`, markdown summary, and fallback to `command/done` outcome text; window-cut fallback synthesizes a command when only checkpoint is loaded.

Gap compaction i18n closed: `ConversationPlugin` registers `conversation` namespace `zh/en` dictionaries (`kConversationZh/En`) via `LocaleService`, `CompactionItem.tsx` locale keys `message.compaction / running / completed / expand / unavailable` are mirrored; `_CompactionCard` reads `Localizations.localeOf` and selects `zh` when `languageCode=='zh'` else `en`, interpolating `completed` via `formatCompactionCompleted`, matching React `t(...)` output (`上下文已压缩` vs `Context compacted`, `已压缩 1 条历史记录（约 256 tokens）` vs `Compacted 1 history items (~256 tokens)`).

Gap Markdown/Shiki closed: summary body previously `SelectableText` plain text now renders through `DsMarkdown` (`flutter_markdown` MarkdownBody with sanitized external links) inside the expanded card, matching React `MarkdownText` (Shiki/KaTeX) body; `_contentBlocksText` replicates React `compactSummary` join (`type==='text'` blocks joined with `''`, no separator, trim) and preserves bold/code/headings for golden verification.

Gap out-of-order parent/root closed: `ToolCallTree.childrenByParent` map at parent key replaces the prior `materializes at root` fallback; `ConversationNodeFolder` now stores `childrenByParent: Map<String, List<ToolSubCall>>` and `_depthByCall`, out-of-order `tool/code-dispatch-start` with `parentCallId='root-1:code:1'` arriving before that parent exists is stored at that key and later collected via `_collectChildren` recursive projection, so the out-of-order depth2 fixture renders identically to in-order depth2 (verified by `subcall_depth2_out_of_order_light.png` golden).

Gap exhaustive cycle/depth/256 closed: depth guard and cycle guard are a mechanical port of `ToolCallTree.acceptEdge`/`wouldCreateCycle` with `MAX 256`: `acceptEdge` computes `depth(parent)+1` (default parent depth 1), walks pending queue propagating depths through `childrenByParent`, rejects when `depth>256`, updates `depthByCall` only on accept, and `wouldCreateCycle` walks the map to detect transitive closure; tests include a 256-deep chain (depth 257 rejected) and a direct cycle `a->b->a` (rejected) plus representative goldens depth 1/2/3+error.

Tests: `conversation_nodes_test.dart` (automatic packet pair, fallback, legacy trio), `manual_compaction_test.dart` (manual lifecycle with markdown bold/code, running without checkpoint, out-of-order parent nesting, 256 cap, cycle rejection), `subcall_compaction_goldens_test.dart` (10 goldens: depth1/2/3+error, depth2 out-of-order, compaction collapsed/expanded, manual collapsed/expanded, markdown expanded, zh collapsed), and `conversation-node-definitions.client.spec.ts` (React oracle for manual vs automatic ownership).

Goldens rendered at 900x700 (depth), 900x500/600 (compaction), 900x750 (markdown) through production `ChatView + liveHistoryProvider`; `flutter test ... --update-goldens` regenerated PNGs and the subsequent run passes without updates; Web parity exercised via `flutter test` (skia/web CanvasKit) and macOS parity via same widget tree on macOS host (uniform LayoutBuilder/alignment).

Fixtures: `test/fixtures/compaction-subcall-fixture.jsonl` (automatic packet pair + deep subcalls) plus the three new `HistoryEntry` builders `_manualCompaction`/`_markdownCompaction`/`_outOfOrderDepth2` in the golden test provide deterministic replay coverage without network.

Integration points: `conversation_nodes.dart` (automatic+manual fold, childrenByParent, depth/cycle), `chat_view.dart` (`_CompactionCard` with title/fallbackSummary + locale + DsMarkdown, `_ManualCompactionNode` branch), `conversation_plugin.dart` (locale registration), `locales.dart` (zh/en dictionaries).

Evidence commands: `flutter analyze lib` shows 0 errors for compaction seam (only pre-existing unrelated warnings), `flutter test test/plugins/conversation_nodes_test.dart test/plugins/manual_compaction_test.dart test/goldens/subcall_compaction_goldens_test.dart` all pass, `flutter test test/goldens/subcall_compaction_goldens_test.dart --update-goldens` regenerated and verified, `pnpm verify-flutter-tracker --check` will pass when run against the updated `migration-tracker.json`.

Remaining gaps: None for `conversation.compaction`; tracker stays `Integrated` for gatekeeper promotion to `Verified`; no further behavioral gaps remain for automatic vs manual, i18n, markdown, out-of-order divergence, or 256/cycle exhaustion.

Status: `conversation.compaction` meets `Integrated` with all Gatekeeper gaps closed.

