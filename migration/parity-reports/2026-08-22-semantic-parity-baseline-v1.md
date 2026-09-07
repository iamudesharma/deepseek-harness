# Semantic Parity Replay — Baseline v1 (P2.1)

**Date:** 2026-08-22 · **Skill:** `$semantic-parity-replay` · **Scope:** Web + macOS · **Stage:** semantic replay (visual parity not started)

## Mechanism

One canonical fixture — `apps/flutter/test/goldens/replay/parity-stream.jsonl`
(40 wire frames, `{"stream","rpcId","frame"}` JSONL, the P0 stream format) —
drives BOTH implementations through their real stacks:

| Side | Driver | Path |
|---|---|---|
| React | `packages/client/runtime/tests/semantic-parity.client.spec.ts` (jsdom) | TypertRegistry → RuntimeClient → ui-settings → locale → ui-theme → ui-layout → ui-conversation; frames enter via `ConnectionSinks.onMuxEnvelope/onHostEnvelope`; session window opened through `SessionRuntime.binding().session.open()`; projection read from `Session.getSnapshot()` (real conversation Definitions) |
| Flutter | `apps/flutter/test/replay/semantic_parity_test.dart` (`ParityProjector`) | Frames decoded by `MuxFrame.fromJson` / `HostFrame.fromJson`; state projected under the documented fold rules (chunk coalescing, call↔result pairing, blank/running lifecycle) |

Both emit **schema v1** lines (session blank/running, seq-ordered nodes with
user text / assistant block histograms / tool-result pairing+error,
turn-end map, running-calls, queue length, pending interaction). The React
result is committed as `react-parity-projection-v1.txt`; the Flutter test
byte-compares against the same file. Either runtime drifting fails CI.

## Fixture coverage

prompt ack (user/message append) · multi-step turn (step/start/end ×3) ·
token streams (text + reasoning deltas → coalesced settle) · assistant
messages with reasoning+text blocks · tool calls bash/write with ok and
`PermissionError` results (canonical tool-result message shape) ·
todo/write projection event · approval requested/resolved · question
requested/resolved · queue snapshot mutation cycle · jobs snapshot ·
projection push · mux+host `stream/error` tolerance · agent-error frame ·
session-status flips · workspace changed/order/archived/remote-event.

## Result

**PASS.** Both drivers byte-match:

```
session s-200 blank=false running=false
node 2 user text="hello parity"
node 7 assistant turn=1 step=1 blocks=reasoning:1,text:1 interrupted=false
node 11 tool-result callId=c-1 name=bash error=none
node 13 tool-result callId=c-2 name=write error=PermissionError
node 18 assistant turn=1 step=3 blocks=text:1 interrupted=false
turn-end 1 seq=21
running-calls 0
queue 0
pending none
```

Commands:
- `pnpm vitest run semantic-parity` (React)
- `cd apps/flutter && flutter test test/replay/semantic_parity_test.dart`

## Defect found & fixed during baseline

**Flutter blank-bit divergence (fixed).** React's object layer clears a
session's `blank` bit when an authoritative `user/message` event replays;
Flutter only derived blank from list summaries, so a live/replayed history
would re-show the blank-session hero over real content. Fix: the live fold's
event→summary rule now clears blank on `user/message`
(`applySessionEventToSummary` in `live_sync.dart`). Regression covered by the
parity projection line itself plus `test/unit/live_sync_test.dart`.

## Wire-shape findings (fixture corrected to real contracts)

- Tool-result messages ride user-role `Message` with
  `source:{kind:'tool',callId}` and `content:[{type:'tool-result',...}]`.
- `assistant/message` is surface-admitted only with `surfaceOp:"append"`.
- Stream-error bodies always carry `details:{}`.
- Events delivered to an uninstantiated/unopened session buffer or drop by
  contract; drivers model the production open-first order.

## Remaining replay work (stage 2 candidates)

- Subcall topology (`tool/code-dispatch-*`) — needs Flutter fold support first.
- Retry (`llm/retry`) and compaction checkpoint events cross-stack.
- Reconnect gap-repair scenario driving both repair paths (React
  `repairGap`, Flutter `liveHistoryProvider` resync) against one fixture.
- Interaction-plane flows (model select, permissions, attachments, settings,
  directory picker) — no session-log contract; covered by behavior suites
  today, visual-parity stage next.

---

# P2.1 Completion Pass — 2026-08-22 (final semantic coverage)

## Closed replay gaps

### A. Subcall topology — CLOSED at the fold level
- React contract traced (`ui-conversation/conversation-nodes/tool.ts`):
  `tool/code-dispatch-start` / `tool/code-dispatch` key on `rootCallId`,
  fold into the root block's `subCalls` children.
- Flutter implementation (WS-Chat owning file
  `plugins/conversation/nodes/conversation_nodes.dart`): new `ToolSubCall`
  model + two fold cases attaching/updating subcalls in place under the
  parent `ToolNode`; unknown roots fail loud. Unit test:
  `conversation_nodes_test.dart` "code-dispatch folds nested subcalls…".
- Cross-stack evidence: fixture turn 2 exercises a `run-code` call with two
  dispatches (one failing); both projectors emit the identical line
  `node 29 tool-result callId=c-3 name=run-code error=none subcalls=2/1`.
  Remaining leg is UI rendering of nested children inside tool cards —
  deferred to P2.2 visual scope; row stays unpromoted.

### B. Retry events — CLOSED at the fold level
- React contract: producer-correlated chain keyed by `retryId`;
  `llm/retry` → scheduled attempt, `llm/retry-started` marks it started.
- Flutter implementation: label-only markers replaced by structured
  `ModelRetryNode {retry, maxRetries, delayMs, failureCode/Message, state}`
  in the same folder; transcript lines keep legacy prefixes
  (`retry #N`, plus `started`). Old marker test updated to the correlated
  contract + uncorrelated-started no-op case.
- Cross-stack evidence: fixture emits `llm/retry`(r-1) then
  `llm/retry-started`; identical projection line
  `node 31 model-retry retry=1 maxRetries=2 state=started`.

### C. Gap-repair dual-drive — CLOSED
Same scenario driven through each stack's production repair path:
window seeded [1,2]; live seq 4 arrives over a gap.
- React: buffered into `liveBuffer`, `repairGap()` pulls the authoritative
  page, stitches buffer; duplicates dropped by seq guard.
- Flutter: `LiveHistory.appendLive` detects the gap, invalidates and refetches
  server truth via `getSessionEvents`; reconnect-replay duplicates dropped.
Both converge to window [1,2,3,4,5] (React spec test 2; Flutter
semantic_parity_test gap test). Generation semantics unchanged and still
pinned by `test/connection/connection_generation_test.dart`.

### Compaction — NOT closed; owning workstream identified
React folds the log-only pair (`compaction/summary` + replacement
user/message checkpoint with `surfaceOp replace`); Flutter's production fold
models the bracket trio (`compaction/start|summary|end`,
`applyCompactionSummary`). These are different event contracts; unifying them
is an implementation decision owned by **WS-Chat** (conversation node
definitions). Per policy this pass does NOT fake alignment: compaction stays
out of schema v1, fixture carries no compaction frames, and both sides keep
their own suite coverage. Tracker row `conversation.compaction` remains
partial/unpromoted.

### D. Interaction-plane flows — behavior-suite evidence mapped
No session-log contract exists for these flows (they are RPC/UI interactions),
so semantic *replay* does not apply; the real runtime contracts are covered by
these executed suites (all green in the full run):

| Flow | Production seam | Evidence suites |
|---|---|---|
| Model selection | modelDirectories service + conversation.input.model seat | ws_surfaces plugins/render tests |
| Permissions | permission_presets plugin over settings face | ws_tasks/plugins suites + host boot |
| Attachments | AttachmentPlugin staging consumed by composer send path | conversation_test "composer attachments controller stores staged files" |
| Settings | SettingsScope describe/mutate + four children plugins | settings_scope_test, ws_surfaces suites |
| Directory pickers | Browse/Native picker plugins binding the adaptive seam | ws_surfaces plugins test |
| Commands/references/input | popup shell, @ source, trigger pipeline | ws_input suites (33) |
| Jobs/workflows/deliverables/goal | WS-Tasks renderers + services | ws_tasks suites |

## Updated classification deltas (from the original 89-row audit)

- `tool.subcall-topology`: not-implemented → **partial** (fold implemented
  this pass; nested card rendering pending). Target reconciled to
  `plugins/conversation/nodes/conversation_nodes.dart`.
- No other classification changed; the three known gaps remain honestly
  open: `tool.subcall-topology` (partial now), `platform.drag-drop`
  (not-implemented), `platform.open-external` (not-implemented).

## Gate status after this pass

Full Flutter suite, analyzer, live-host gates, React vitest driver, and
`verify-flutter-tracker --check` re-run at stage end — see final section of
the P2.1 report for recorded numbers. Nothing marked Verified.
