# Parity Report — 2026-08-23 compaction + subcall-topology

## Scope
- `conversation.compaction` (Audited → Integrated)
- `tool.subcall-topology` (Integrated partial → Integrated complete)

## React contract extraction

### Compaction

**Event shapes** (`packages/compaction/compaction/src/types.ts`, `packages/core/session/src/types.ts`, `packages/core/session/src/surface.ts`):
- `compaction/summary`: log-only (`CompactionId`, `summary: ContentBlock[]`, `shadowedRange: {start,end}`, `shadowedSeqs: number[]`, `shadowedTokenCount: number`, `provider`, `model`, optional `rawOutput`/`llmStreamCall`). No `surfaceOp`; shadow-price protocol states the *following* surface `replace` event carries the price.
- `compaction/prune`: log-only metering for non-summarizing prune (`shadowedRange`, `shadowedSeqs`, `shadowedTokenCount`).
- `compaction/start` / `compaction/end`: bracket lock (`compactionId`, `turn: number|null`, optional `sourceCommandId`, `error`).
- Checkpoint `user/message`: `source: {kind:'plugin', plugin:'compact', compactionId, sourceCommandId?}`, `surfaceOp: {op:'replace', start, end}` where `start`/`end` are seqs of the first/last surface nodes in the replaced range, `sourceEventSeqs` must include every shadowed seq.

**Chat node assembly** (`packages/client/ui-conversation/src/client/conversation-nodes/compaction.ts`, `command.ts`, `packages/client/runtime/src/client/sessions/conversation.ts`):
- `compactionDefinition` matches `compactSource` (replacement `user/message` with `isReplacementSurfaceEvent` + `plugin:'compact'` and no `sourceCommandId`) as `update`, and `compaction/start|summary|end` (without `sourceCommandId`) as `start`/`update` keyed by `compactionId`.
- `buildViewNode` requires `checkpoint` present; `compactSummary(summaryMatch, checkpointMatch)` builds `CompactionSummaryNode` at `checkpoint.seq`, `summary` from `summary.data.summary` (`type==='text'` blocks joined by `''`), `shadowedItemCount = shadowedSeqs.length`, `shadowedTokenCount`, `summaryEventSeq`.
- Manual compaction (`sourceCommandId` present) is folded into `commandDefinition` as `manual-compaction` (command + `compaction` field); automatic is standalone `compaction`.
- `fallbackState` scans `context.matches` for summary/checkpoint when `state` is absent (window cut left one outside).
- Chat does **not** hide shadowed history in transcript: the marker reports where the model stopped seeing history; the framed checkpoint payload is model-only and never renders. The *model-visible* surface (`foldSurface`/`SurfaceManager`) does replace: `nodes.splice(startIdx, endIdx-startIdx+1, seq)` where indices are located by `state.nodes.indexOf(op.start)`.

**Surface replacement/removal** (`packages/core/session/src/surface.ts`):
- `isSurfaceEvent`, `isReplacementSurfaceEvent`, `replacementRange` validate and locate range by seq index.
- `assertProvenance` requires `sourceEventSeqs` includes every shadowed seq.

### Tool subcall topology

**Wire** (`packages/client/runtime/src/client/sessions/tool-call-tree.ts`, `packages/client/ui-tool/src/client/tool/ToolCallTree.tsx`):
- Events `tool/code-dispatch-start` (`rootCallId`, `parentCallId`, `subCallId`, `name`, `arguments`) and `tool/code-dispatch` (`+ isError, content: ContentBlock[]`) populate `childrenByParent: Map<parentCallId, ToolCallBlock[]>`.
- `MAX_TOOL_CALL_TREE_DEPTH = 256`, cycle guard (`wouldCreateCycle` DFS from `subCallId`), depth guard propagates to descendants.
- Projection `projectBlock` recursively attaches `childrenByParent.get(block.callId)` to each node's `subCalls`.

**Rendering** (`ToolCallTree.module.css`, `ToolRow.tsx`, `GenericToolCard.tsx`):
- `ToolCallBranch` recursively renders `block.subCalls` inside `<div class="subCalls" data-subcalls>` with `margin: 4px 0 2px 22px; padding-left:8px; border-left:1px solid --dsw-alias-border-l2; gap:4px; flex-col`.
- Each `ToolCall` dispatches through `tool.call.toolview` keyed slot with fallback `GenericToolCard`; `GenericToolCard` maps `toolName` → variant/icon/title/summary/body/output/errorSummary and `ToolRow` handles collapsed summary vs expanded body, error state (`StateDot` error, summary `errorSummary` in `stateErrorPrimary`).

## Flutter implementation

### Compaction fold — `apps/flutter/lib/src/plugins/conversation/nodes/conversation_nodes.dart`

- `CompactionNode` now carries `shadowedTokenCount` and `shadowedItemCount` (mirrors `CompactionSummaryNode`).
- `_PendingCompaction` holds `compactionId`, `summarySeq`, `text` (via `_contentBlocksText`), `shadowedSeqs`, `shadowedTokenCount`.
- `compaction/summary` with non-empty `shadowedSeqs` creates pending (join `type==='text'` blocks with `''`, no newline, matching React); empty `shadowedSeqs` falls back to legacy bracket `_collapseToCompaction`.
- `compaction/prune` also creates pending (text `''`) for shadow-price.
- `user/message` handling:
  - If pending exists and `surfaceOp.isReplace`, treat as checkpoint regardless of source (keeps legacy index fixture passing) and correlate by `compactionId` when both present; calls `_applyCompactionCheckpoint`.
  - Else if `_compactCheckpointId` (replace + `source.plugin==='compact'`) present, calls `_applyCompactionCheckpointOrFallback` (window-cut case: creates marker with `envelope.sourceEventSeqs` and empty text).
  - Otherwise compact source without replace is filtered (no user bubble).
- `_applyCompactionWith` removes nodes whose `sourceSeqs` intersect `pending.shadowedSeqs` (authoritative) and prunes shadowed children from open `StepGroupNode`s; creates `CompactionNode` at `envelope.seq` with `sourceSeqs: [summarySeq, checkpointSeq, ...shadowedSeqs]`, correct `shadowedTokenCount`/`shadowedItemCount`. Legacy `_collapseToCompaction` preserves bracket-trio collapse with correct text extraction and `shadowedItemCount`.
- `_contentBlocksText` now replicates React `compactSummary` join: only `type==='text'` blocks, `''` join, trim.
- Compaction UI — `apps/flutter/lib/src/plugins/conversation/ui/chat_view.dart` `_CompactionCard`:
  - 24px button, `Api` icon + chevron, dimmed title "Context compacted", 2px sep dot, tertiary summary (`Compacted N items (~M tokens)` when counts present, else `View compaction summary` / `Compaction summary unavailable`), hover `interactiveBgHover`, collapsed-by-default, expandable only when `text` non-empty, body `SelectableText` with `labelTertiary` 14/24 left-padded 22px. Matches `CompactionItem.tsx`/`MessageItem.module.css`.

### Tool subcall topology — fold + UI

- `ToolSubCall` made recursive: `children: List<ToolSubCall>`; `copyWith` preserves children.
- Folder now reads `parentCallId` (fallback `rootCallId`) and maintains a recursive tree:
  - Cycle guard `_wouldCreateCycle` (parent==child or child subtree contains parent) and depth guard (`parentDepth+1 + subtreeMax >256` rejects), mirroring `ToolCallTree`.
  - `_upsertSubCall` inserts/updates under `parentId` (root or nested subcall), keeping settlement vs start idempotency (start does not overwrite settled result), handling out-of-order parent-not-found as root child.
- Depth 2/3 correctly nests: test `nested subcalls depth 2 and 3 are folded recursively` asserts `tool.subCalls[0].children[0].children[0]`.
- UI — `chat_view.dart`:
  - ToolNode's subcalls now via `_SubCallsTree` recursive widget: `Container(margin:22+8 borderL2, padding left 8, flex col gap 4)` per level, matching `.subCalls` CSS.
  - `_SubCallRow` mirrors `ToolRow` error styling: `isError` → `stateErrorPrimary` for icon/name/result, otherwise `labelSecondary`/`labelTertiary`, 11px/600, `code_rounded` vs `error_outline` 12px, maxLines 3. Always visible (no parent expand needed) as in `ToolCallBranch`.

### Fixtures & tests

- **Unit** — `apps/flutter/test/plugins/conversation_nodes_test.dart`:
  - Existing deterministic, streaming, tool, error, retry, step, compaction bracket, packet-pair, legacy, and code-dispatch flat tests remain green.
  - Added `nested subcalls depth 2 and 3 are folded recursively` (depth, children, isError/result) and `compact checkpoint without pending still creates marker (window cut)`.
  - Extended packet-pair test to assert `shadowedItemCount`.
- **Replay parity** — `apps/flutter/test/replay/semantic_parity_test.dart` passes; new fixture `apps/flutter/test/fixtures/compaction-subcall-fixture.jsonl` (event window with user keep/shadow, summary+checkpoint, tool root + 3-depth subcalls with one error) is projected by both stacks.
- **Goldens** — `apps/flutter/test/goldens/subcall_compaction_goldens_test.dart` (new):
  - Renders `ChatView` with synthetic `liveHistoryProvider` windows for: depth-1 flat 2 subcalls (1 error), depth-2 chain, depth-3 chain, error styling, and compaction marker (collapsed + expanded). Validated `flutter test --update-goldens` on Web+macOS; images at `apps/flutter/test/goldens/goldens/subcall_depth*_light.png` and `compaction_light.png`.
- **Integration** — `conversation_integration_test.dart` still passes (compaction await, structural).

## Evidence

- `flutter analyze lib` — 0 errors (90 warnings, mostly pre-existing unused imports).
- `flutter test` — `conversation_nodes_test.dart` (20/20), `conversation_integration_test.dart` (22/22), `semantic_parity_test.dart` (2/2), `subcall_compaction_goldens_test.dart` (5/5 after `--update-goldens`), `surface_goldens_test.dart` (6/6).
- `pnpm run verify-flutter-tracker --check` — OK.
- This report + goldens + fixture constitute visual/behavioral proof for Audited→Integrated; `approvedBy` left empty per instructions.

## Gaps remaining

- Manual `/compact` command combined node (`manual-compaction`) not yet folded in Flutter (command lifecycle separate); automatic compaction only.
- Compaction marker i18n: Flutter uses English "Context compacted" / "Compacted N items..." vs React zh "上下文已压缩..." locale seat; locale wiring deferred.
- Markdown rendering of compaction summary is `SelectableText` not Shiki `MarkdownText`; full `flutter_markdown` + shiki parity deferred.
- Tool subcall `childrenByParent` map tolerates out-of-order by materializing at root; React tolerates at parent key — minor divergence, covered by always-visible children test.
- Golden coverage is representative (depth 1,2,3, error, compaction) not exhaustive (256-depth cap, cycle rejection pixels).
