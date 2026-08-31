# Current Conversation Debug Report — Flutter vs React Master (2026-08-31)

SHA: `4f2038e343c92bbb1dff37416cb8909b95dd07b8` (`4f2038e343 fix: update tracker reactPackage for moved runtime sources`)
Date: 2026-08-31
Author: parity-pass agent (react-codebase-auditor + flutter-integration)
Source roots: `packages/client/ui-conversation`, `packages/client/ui-chat`, `packages/client/ui-tool`, `packages/api/session-controller/client`, `apps/flutter/lib/src/plugins/conversation`, `apps/flutter/lib/src/features/conversation`, `apps/flutter/lib/src/core/session/live_sync.dart`

> This report answers §24 "DEBUG THE CURRENT FLUTTER SCREEN FIRST" A–I before any UI edits, and records the live data divergence found.

---

## A. What rendered from `session/follow` snapshot?

Follow snapshot is the **authoritative history window** (Host `session/follow {cursor, records:[SessionHistoryRecord], hasMore, projections:{asOfSeq,values}}` → Client `SessionEventWindow`). In Flutter, `live_sync.dart:openFollowFor()` opens `mux.openSessionFollow(sid, maxMessages:50)` over `WSS /api/remote.mux`, decodes `type:'snapshot'` → `HistoryEntry[]` + `cursor` + `projections`, and calls `liveHistoryProvider(sid).replaceAllWithCursor(entries, cursor)`.

- **React path:** `Session.doOpen() → SessionEventStream.open({maxMessages:50}) → RemoteJournalStream` yields follow snapshot `cursor+records+hasMore` and never HTTP `session/page` on open (`packages/api/session-controller/src/client/transport.ts:133` + `gateway/journal-stream.ts:149`). The assembler then does `replaceWindow(entries,hasMore)` with sorted `seq` + `LocationIndex.rebuild`.
- **Flutter before this pass:** `liveHistoryProvider.replaceAll(entries)` stored only the list, dropping `cursor`. The accepted seq was implicitly the last entry's `seq`, but if the follow window was incomplete (`hasMore:true` and earlier history not yet paged), the cursor fencing was missing: a subsequent live `event` with `seq` just above the last entry but still ≤ `cursor` could be appended duplicate. Now fixed via `_acceptedSeq = max(lastSeq, cursor)` and `appendLive` checks `seq <= _acceptedSeq`.

**Visible in screenshot (React):** the opening `Context snapshot · @dsh-system-prompt sandbox:policy, approval:policy` and `Context · catalog · skill-catalog <system-reminder>` rows are *snapshot-derived context injections* (first two rows below header). They render from snapshot-folded `ContextMessageNode` (`form:'snapshot'` vs `'catalog'`) via `ContextInjectionRow`’s `contextBody` branch — not from assistant text. Flutter was rendering them via `ContextNode`/`_ContextRow`, but previously mis-classified as user bubbles before the `source.kind !== 'user'` fix; now parity restored (collapsed `DisclosureRow` with `IconContextInjectionOutline16`, provenance label, bounded body).

**Flutter now:** `ChatView` builds `ConversationNodeFolder` deterministically each frame from `liveHistoryProvider` entries in order. Snapshot replacement is atomic: `replaceAllWithCursor` fences future duplicates by cursor.

---

## B. What rendered from live event (`session/event` via `session/follow` tail)?

Live tail messages are discrete `type:'event'` frames on the same `session/follow` logical stream after the snapshot. Types observed during the "hi" scenario:

- `user/message` (source.kind `'user'`, `surfaceOp` null) → `UserMessageNode`
- `turn/start` (turn number) → location bracket only, no row
- `step/start` (step number) → opens `StepGroupNode` grouping bucket
- `assistant/chunk` (streaming deltas: `block-start`, `text-delta`/`reasoning-delta`/`tool-call-delta`, `block-end`, `usage`/`finish`) → incremental `AssistantNode {streaming:true}` via `ToolStreamAccumulator` + `_chunkBuffers`/`_reasoningBuffers`
- `assistant/message` (authoritative durable content blocks: `text`/`reasoning`/`tool-call`/`image`) → settles `AssistantNode {streaming:false}`
- `tool/call` + `tool/result` (`source.callId` pairing) → `ToolNode` root running→settled, recursive `subCalls` via `childrenByParent` map
- `tool/code-dispatch-start|code-dispatch` → nested `ToolSubCall` tree depth up to 256
- `llm/retry`, `llm/retry-started` → `ModelRetryNode`
- `turn/end` (reason error|max-tokens) → `TurnErrorNode`, otherwise closes step/turn

In React the **append path** is `ConversationNodeAssembler.append(LiveEntry)` — one `D` `match()` per Definition + `O(1)` key lookup + single Context update + possibly one Location `applyData` — never scanning the full window. Publication cadence per match (`immediate` for structural, `animation-frame` for deltas, `none` for `step/start`/`usage`) coalesces via `flush()` + rAF.

In Flutter the live path is `liveSync.onMuxEnvelope(SessionEventFrame)` → `liveHistory.appendLive(entry)` → next `ChatView` build re-folds full window via `ConversationNodeFolder`. No incremental `match` per Definition yet; fold is whole-window each build `O(N)` `N≤50`. Gap detection uses `seq > tail+1` → drop until snapshot repair (mirrors React `replaceThrough` without flooding `session/page`). Duplicate detection now uses `_acceptedSeq` fence (`seq <= acceptedSeq` → drop).

**Screenshot:** the `"Thinking · The user is just saying 'hi' again ..."` rows and `Hey! 👋 What can I help you with?` assistant rows are live `assistant/chunk` → `assistant/message` lifecycle. The large grey `Thinking` boxes in Flutter were the same `AssistantNode.reasoning` but rendered as a big bordered box vs React's compact `DisclosureRow` (`variant:think`, `data-state:running|ok`, separator dot + one-line summary scrolled `scrollWidth-clientWidth`). Flutter's `_ReasoningRow` now mirrors helpers (`firstLine/latestLine`) and post-frame `jumpTo(max)` while running, `jumpTo(0)` on settle.

---

## C. What rendered from legacy message provider (`messageListProvider` / `liveMessageListProvider`)?

- **`messageListProvider` (FutureProvider.family<List<Message>,String>)** — Historical HTTP fallback (`getSessionEvents` → `session/page`) **now pure view of `liveHistoryProvider`** (0 HTTP on open). Before this pass there were **2× `session/page` per open** (`LiveHistory.build` microtask + `messageListProvider` fallback) saturating the 6-connection browser limit and blocking `session/prompt` behind pending `page`s (25 pending in screenshot). Fixed via `liveHistoryProvider`-only window; explicit `getSessionEvents` remains for `loadOlder`/offline tests only.
- **`liveMessageListProvider` (Provider.family<List<Message>,String>)** — Derived from `liveHistoryProvider` + `optimisticMessagesProvider` + `isRunning` via `messagesFromHistory(history,isRunning:true)` streaming buffer handling. **Not used by active ChatView** — `ChatView` folds directly from `liveHistoryProvider` into `ConversationNode`s. This provider is kept as a compatibility projection for `MessageList` consumers (e.g., legacy widget tests) and must not be watched by the active transcript (would duplicate). It was responsible for the **global Set dedup bug**: `baseUserContents = base.where(user).map(trim).toSet()` hid legitimate repeated `"hi"` across turns (same content globally). Fixed to tail-only dedup (mirrors React's tail atomic swap and ChatView's tail dedup). `MessageList` itself is legacy (not routed; `ConversationScreen` → `ConversationColumn` → `ChatView`, not `MessageList`).
- **`liveHistoryProvider` (NotifierProvider.family<LiveHistory,List<HistoryEntry>,String>)** — **Authoritative** per §5: sole history source (`session/follow` snapshot `replaceAllWithCursor` + live `appendLive` with cursor fence + gap drop). All transcript rendering must read this (directly via `ChatView` or indirectly via derived `messagesFromHistory` when compatibility needed).

**Finding:** No duplicate insertion after fixes. The previous "repeated hi" artifact in the screenshot was traced to:
  1. The `displayFailure` no longer triplicates, but repeated identical `"hi"` content across 3 turns was being hidden by the global Set dedup in `liveMessageListProvider` (only tail dedup retained), making some `"hi"` appear to come from history vs optimistic echo confusion.
  2. Optimistic echo (`optimisticMessagesProvider` tail + `ChatView` tail synth) vs durable host echo (`user/message` seq) double-render when `content-trim` equality matched a non-tail duplicate. Fixed via tail-only check (only hide optimistic when durable tail is same text).

---

## D. What rendered from tool node (`tool/call` / `tool/result` / `code-dispatch`)?

- **React:** `ui-conversation` dispatches ordered `tool-call` `ConversationViewNode` through slot `conversation.chat.node` key `tool-call`. That single registration `ToolCallTree` (from `ui-tool`) recursively walks `ToolCallBlock.root.subCalls` and sends root + children at every depth through the same atomic `tool.call.toolview` slot (wire tool name key → owning business package row, fallback `GenericToolCard`). Each wrapper preserves `data-chat-anchor-key="call:<id>"` + `data-chat-call-id`. Running/success/error/interrupted states come from frozen call/result slice; background persistent-shell results use expandable generic IO card.

- **Flutter before:** `ConversationNodeFolder` produced `ToolNode {callId,name,status,result,subCalls:List<ToolSubCall>}` with depth-capped `childrenByParent` ingest (`MAX_DEPTH 256`, cycle guard) mirroring React's `childrenByParent` walk, then `ChatView._builtin` fallback `_ToolFallbackRow` (single string row `'$tool $argsRaw'` in `_IoCard`) rendered when no registry `hub.controller.renderers` override existed; `ToolCallTree` imported but only via `ToolNodeAdapter`. Nested depth `N` support existed but collapsed to one string row, not per-level tool-specific presentation. Status chips used `StateDot`/`Icon pending`.

- **Flutter after parity awareness:** `ToolNode` recursive `_SubCallsTree` + `ToolNodeAdapterWithSubCalls` keep parity with React's recursive dispatch. When `hub.controller.renderers.resolve('tool-call')` is present (real host run with `tool_plugin` registration), `_buildNode` routes through that override with full `ChatNodeData` raw+subCalls; otherwise `_ToolFallbackRow` retains for tests/offline. `kindForTool` mapping and `_variantFor` search→read→bash→write→edit→code matches `toolRowModel` classification.

---

## E. What rendered from reasoning node (`assistant-step` reasoning block)?

- **React:** `ReasoningRow` inside `AssistantNodeView` (`AssistantMarkdown` splits `blocks` by `type:'reasoning'`). Compact `DisclosureRow` with `IconThinkOutline14`, `t('message.think')` title, chevron, collapsed `separator` dot + `summary` (`running ? latestLine(text) : firstLine(text)`) with `summaryRef.scrollLeft = running ? scrollWidth-clientWidth : 0` via `useThrottledVisualUpdate` (rAF coalesced). Body `.thinkBody` is raw reasoning text (italic, `lineHeight 1.4`, bounded). While `status==='running'` the disclosure is a sibling of markdown text sibling set; no outer bubble border. Turn-process compact folding additionally hides reasoning in closed Turns until explicitly expanded.

- **Flutter:** `_ReasoningRow` (inside `AssistantNode` builtin) + separate `_ReasoningBlock` (legacy `MessageList`). Both use same `firstLine/latestLine` helpers, `_scrollController` jumped post-frame to `maxScrollExtent` while `widget.running` else `0`. Disclosure `InkWell` toggles `_expanded`, collapsed summary rendered in `SingleChildScrollView` horizontal `NeverScrollableScrollPhysics`, expanded body `SelectableText` italic 12/ labelSecondary. Flutter's summary now correctly shows **latest non-blank line while streaming, first line when settled**, matching React. Previously the screenshot's "large separate boxed row" came from rendering raw reasoning as a full `_MarkdownBody` plus a thick `Container` with `bgOverlay 0.6` — now collapsible via `DisclosureRow` token parity (`bgOverlay.withOpacity(0.6)` should be token `bgOverlay`? Keep but note visual token gap).

- **Gap remain:** Flutter lacks `useThrottledVisualUpdate` rAF coalesce (does postFrame per update, could jitter faster streams), lacks `visuallyHidden` running label a11y span, and Turn-process folding still absent so reasoning not auto-collapsed after settled Turn.

---

## F. What rendered from context node (`context` type)?

- **React:** `ContextInjectionRow` (`data-context-injection`) collapsed `DisclosureRow` with `IconContextInjectionOutline16` or `<ReferenceIcon kind=session>` when `provenance.role==='recall'`, title `t(provenance.role==='recall' ? 'message.contextRecall' : 'message.contextInjection')`, collapsed dot + `provenance.label` (`data-context-source`) + dot + `summary` (`data-context-summary`). Body via `contextBody(form, {content,source,t})` branching on **resolved `rendered` form** (`instructions|catalog|snapshot|notice|relay|recall|null`), not declared form — when fields unreadable it shows opaque body `data-context-injection-body` `data-context-form` bound to rendered/null.

- **Flutter:** `ContextNode {text,label,form,sections}` derived by `Folder.add user/message` classification (`source.kind !== 'user'` → context). `_ContextRow` title `form==='snapshot' ? 'Context snapshot' : form!=null ? 'Context · $form' : 'Context'`, summary `sections.map(name).join(', ')` or first line of text, body bounded to 20k. The derivation for catalog shows `skill-catalog` etc through `sections` names, approximated. Not injected into `UserMessageNode` bubble, not assistant text.

- **Screenshot gap noted:** React context rows appear as thin disclosure rows with browse icon + title + summary + source dot, clearly above `Hi! How can I help ...`. Flutter previously injected context text into assistant bubbles or as large raw prose; now isolated but spacing/icon not pixel-perfect.

---

## G. What is duplicated?

**Found duplicated paths (before fix, now guarded):**

1. **Snapshot + live event duplicate seq** — Snapshot record `user/message` seq 8 and live `session/event` with same seq 8 would produce two visible messages if appended without fence. **Guard:** `LiveHistory.appendLive` checks `seq <= _acceptedSeq` (cursor fence) then `seq <= tailSeq` duplicate drop; `_acceptedSeq` is updated to `max(lastEntrySeq, cursor)` on `replaceAllWithCursor`. Snapshot establishes cursor X, events ≤X ignored, only >X appended. Text-based dedup not used.

2. **Optimistic local echo + host-durable duplicate** — `ComposerController.submit` writes to `optimisticMessagesProvider` instantly (mirrors React `session.beginSubmission` echo + one-paint yield), then host emits `user/message` via live tail within 100–200 ms. **React atomic swap:** `ChatView` computes `observedRpcIds(order,nodes,queue)` set of durable `user/steering` `source.rpcId` + queue `rpcId` and hides `visibleSubmissions` whose `requestId` is observed. **Flutter:** `ChatView` synthesizes `UserMessageNode key:'optimistic-${id}'` only when tail is not already same text; `liveMessageListProvider` now hides optimistic only when tail is same user text (tail-only). Previously global Set hid repeated same text across turns. **Remaining gap:** Flutter still uses content equality not `rpcId` set, so repeated identical `"hi"` with same text but different `rpcId` could momentarily show both before durables settle? Fixed tail-only reduces global collision, but true parity needs `rpcId` field on `Message` + observer set — recorded as model diff `MISMATCH`.

3. **Dual store duplication** — `MessageList` (legacy `LiveHistory + messageListProvider`) vs `ChatView` (liveHistory → folder). Not simultaneously rendered (routing picks `ChatView` via `ConversationColumn`), so no visible double list, but the existence of `messageListProvider` still caused **network-level duplication**: 2× `session/page` per open saturating the 6-conn limit, leaving `session/prompt` queued (25 pending). **Fixed:** `messageListProvider` and `liveHistoryProvider` no longer issue HTTP on open; queue projection/queue-frame no longer invalidates `messageListProvider`. Provisionally flagged as "compatibility projections only" — see §5.

4. **Tool-call ghost duplication** — Previous `conversation_reducer` created pending ghost `ToolCall` from `assistant/message` `tool-call` heads, then `tool/call` created a second running card with same `callId` (two entries for one logical call). **Fixed:** `AssistantNode` handling clears tool heads (`case 'tool-call': break`) and `conversation_reducer` skips creating ghosts (continue), so tool rows come only from real `tool/call` + `tool/result`.

---

## H. Which widgets do not exist in React anymore?

- **`MessageList` / `HarnessAiChat` / `chat_ui_adapter.dart` (flutter_chat_ui adapter)** — React has no third-party chat package (`flutter_chat_ui`, `dash_chat`, etc.) and no second engine. Flutter's `harness_ai_chat.dart` is a stub forwarding to `ConversationColumn/ChatView`; `message_list.dart` and `chat_ui_adapter.dart` are legacy bridges kept for tests only and not mounted in `ConversationScreen`. They should be archived or marked `Not applicable` once tests migrate to `ConversationNodeFolder` folds.

- **Blank-session hero rendered as a second tree** — In React the hero is a PHASE of the single `ConversationRoot` (`data-phase='hero'`): fish headline + `conversation.hero.brand.mark` + `conversation.hero.workspace` + `conversation.hero.agentPreset` + resident composer, centered in `ScrollBody` with `justify-content:center`. Flutter previously mounted a separate `SessionsMobileScreen` hero tree for blank; now consolidated as `_HeroPhase` inside `ConversationBody` single path — peer of React assembly. Keep only `WelcomeScreen` (no-session) as root `WelcomeScreen` (separate from session hero).

- **`ToolCallBlockPreview` inside `MessageBubble`** — React never renders tool-call heads inside `AssistantMarkdown` (case `tool-call`: `break`). Flutter's `MessageList._ToolCallBlockPreview` was that discarded preview; removed from `ChatView` tool heads (now skipped) — keep only via `ToolNode`.

- **Inline `_ReasoningBlock` with full bordered bubble in `MessageList`** — React reasoning is a disclosure, not a boxed bubble with shadow; now `_ReasoningRow` collapsible disclosure matches, not large `Container` with `radiusLg`. The remaining `_ReasoningBlock` inside legacy `MessageList` is historical.

---

## I. Which React widgets have no Flutter equivalent?

- **`TurnProcess` (`TurnProcessNodeView`)** — collapsed disclosure that folds `Context injection`, `reasoning`, earlier assistant material, tool rows and retries by default when a Turn completes, counts Tool vs subagent calls, shows `"Thought for a while"` when zero. Flutter currently flattens `StepGroupNode` children directly without this control; scroll depth after completed Turns is longer. Status: **MISSING** (requires `TurnProcessChatData` counting + `encodeTurnProcess` spec + `CompactTranscript` policy).

- **`TurnTail` (`TurnTailNodeView` + `conversation.chat.turnTail` chain + `conversation.chat.assistant-actions` list + `StatsLine`/`TurnUsageDisclosure`)** — per-Turn footer tail showing closing Assistant actions (copy/thumbs/share/feedback via `ui-message-feedback`), branchUnavailable dot, `ttftMs`/`tokensPerSecond` metrics, and **token usage** disclosure (`TurnTokenUsage` `{uncachedInputTokens, outputTokens, totalTokens, cacheRead?, cacheWrite?, reasoning?, routes?}`) derived only when window contains `turn/start` and every attempt reported safe usage. Flutter has static `'Deep diving…'` running indicator + tail Copy only, no metrics row, no route breakdown.

- **`TurnNavigator` rail** — `ChatTurnNavigationIndex {items():TurnNavigationItem[]}` (`turn, anchorKey, prompt, response` bounded previews) rendered as a compressed rail alongside the scroll with 10 px spacing → compressed when exceeding height. Flutter has no rail; `turnGrouping` dart provides base but no widget.

- **`SystemPromptRow` (collapsed `System prompt` row per initial/resumed request or real system-field change, before user messages, matching provider envelope)** — Flutter `_SystemPrompt` row stub vs full per-request system text with line breaks; React's disclosure rule (don't repeat for same-series config-only or tool-only changes, tool steps, retries) not fully replicated.

- **`MessageIconActions` (feedback actions row below closing assistant)** — React `ui-message-feedback` renders thumbs/list/share actions keyed by `MessageId` inside `assistant-actions` list; Flutter stub missing.

- **`conversation.message.images` single gallery** — React renders one consecutive image group via injected `MessageImages` slot with loaded `ImageLoader` + `peekImageUrl`. Flutter `_UserImage` loads via placeholder `Icon` placeholder not the `HistoricalImageCache` URL resolver; real image loader via `ctx.uiConversation.imageUrl` not wired.

- **`loadOlder` with prepend anchoring (`Load older` button → `anchorElement` pagingAnchor + scrollTop compensation for prepend height)** — Flutter `ChatView` has TODO `hasMore:false` `loadingOlder:false` and no `loadOlderAnchored` callback to server; button text present but no `session.loadOlder()` wiring except in `ChatView` header's `loadOlder` prop not bound to button.

- **`Searchable hidden` + `TurnError`/`ModelRetry` rendering subtleties** — React uses `searchableHidden` for hidden mounts (maintains searchability), localized token formatting (`token-format.ts`), and `displayFailureMessage` mapping with `AUTH` code collapsed to fixed line. Flutter `TurnErrorNode` matches but `ModelRetryNode` scheduled vs started state timing less granular.

- **`Request prompt` inspector (`request-prompt` definition via `ctx.uiConversation.inspectRequestPrompt`)** sharing Chrome system-visible text logic with Trajectory (header reuse) — Flutter never calls `inspectRequestPrompt`, system prompt snapshots incomplete.

- **`ForkAt` navigation (`fork({sessionId,atSeq,increaseTitle})` then `open(childId)`)** — React `ChatView` toolbar per-turn action opens fork; Flutter wires via `forkAt` prop but not surfaced as visible fork button.

---

## Trace Opinion — First Divergence Identified

The **first structural divergence** is not arbitrary padding but **conversation windowing/assembling ownership**: React owns a single `MutableSessionEventSource → UiConversation.binding(Assembler+views)+Session → ChatSnapshot` incremental deterministic assembly with predecessor `reader.previous`, `buildLocationData`, and `publication: none|animation-frame|immediate` plus per-session persisted stores. Flutter owned a dual-path ephemeral history (`liveHistoryProvider` list + `messageListProvider` HTTP page + `ConversationNodeFolder` re-fold each build) without cursor fence and without Location `previous` graph, plus a global-Set optimistic dedup that suppressed legitimate repeated content. The deepest fix applied here (cursor fence `replaceAllWithCursor` + tail-only dedup) restores seq identity semantics; the next required structural convergence is **one ordered Chat store with activeTargets + locations + navigation + legacy slice** (not two providers) and **TurnProcess folding** to achieve inbound scroll-height parity.

---

## Verification Checklist of Current State

- [x] `session/follow` snapshot → `replaceAllWithCursor` (cursor fence)
- [x] Live `session/event` seq duplicate drop (acceptedSeq + tailSeq)
- [x] Gap repair delegates to snapshot (drop, not `session/page` storm)
- [-] HTTP page storm removed (0 page on open) — done
- [x] Global Set dedup → tail-only (repeated `"hi"` across turns preserved)
- [ ] `rpcId` atomic swap (still content equality; needs branded fix)
- [-] Single authoritative store (`liveHistoryProvider` sole) — provider fan-out documented
- [ ] TurnProcess / TurnNavigator / StatsLine / images gallery still MISSING (documented in model diff MISMATCHs)

