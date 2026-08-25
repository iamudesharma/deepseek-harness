# Core runtime / protocol remediation — 2026-08-25

Scope: Agent A pass over the 20 core/runtime/protocol tracker rows (`api.*`, `runtime.*`, `protocol.rpc-contracts`, `slot.registry`, `slot.tool-renderer-registry`, `modules.client-plugin-loading`, `plugin.client-lifecycle`, `state.streaming-*`, `tool.lifecycle-pairing`, `locale.service-dictionaries`, `interaction.plane`). This report is the `evidence.parityReport` target for every row this pass touched. No row was promoted to Verified and no evidence was invented; every command below was executed on 2026-08-25.

## Classification per row

| Row | Classification | Action this pass |
|---|---|---|
| api.connection | implemented-but-missing-evidence | Integrated — unary envelope/echo contract newly pinned |
| api.llm | not-applicable (backend seam) | flutterTarget corrected to the real consumer seam; Integrated |
| runtime.session-store | implemented-but-missing-evidence | flutterTarget corrected to live_sync.dart; Integrated |
| runtime.projection-store | partial (higher-seq-wins missing) | Implemented SessionProjectionStore + live_sync wiring; Integrated |
| runtime.pending-interactions | partial (approvals absent) | flutterTarget corrected to questions_state.dart; stays Audited with gap recorded |
| interaction.plane | partial (approval surface absent) | flutterTarget corrected to question_node_card.dart; stays Audited with gap recorded |
| runtime.remote-event-dispatch | implemented-but-missing-evidence | flutterTarget corrected to runtime_services.dart; Integrated |
| runtime.settings-scope | implemented-but-missing-evidence | Integrated on existing settings_scope.dart |
| settings.runtime-scope | implemented-but-missing-evidence | Reconciled as ui-settings base-plugin face; target → app_plugins.dart; Integrated |
| runtime.host-born-sessions | implemented-but-missing-evidence | Wire contract pinned by new test; carrier files claimed by sibling rows so status stays Audited (see below) |
| protocol.rpc-contracts | implemented-but-missing-evidence | Target → rpc_envelope.dart; Integrated |
| slot.registry | evidence-complete | Integrated |
| slot.tool-renderer-registry | implemented-but-missing-evidence | Target corrected to plugins/tool/tool_presentation_registry.dart; Integrated |
| modules.client-plugin-loading | implemented-but-missing-evidence | Target → plugin_host.dart; Integrated |
| plugin.client-lifecycle | implemented-but-missing-evidence | Target → plugin_contract.dart; Integrated |
| state.streaming-assistant | implemented-but-missing-evidence | Target → message_provider.dart; Integrated on replay evidence |
| state.streaming-reasoning | implemented-but-missing-evidence | Target → chat_ui_adapter.dart; Integrated on replay evidence |
| state.streaming-tool | not-implemented in Flutter client | Stays Audited — no tool-call-delta path exists client-side (see honesty notes) |
| tool.lifecycle-pairing | implemented-but-missing-evidence | Target → conversation_reducer.dart pairing site; Integrated |
| locale.service-dictionaries | implemented-but-missing-evidence | Target → runtime_services.dart LocaleService; Integrated |

## Implementation change (one)

**runtime.projection-store** was genuinely partial: React's `ProjectionValueStore`
(`packages/client/runtime/src/client/sessions/projection-store.ts`) holds
`key → {value, seq}` under **higher seq wins**, seeded from the history tail's
`projections` block and updated by `session/projection` push frames; the Flutter
fold applied every projection frame unconditionally, so a replayed or stale
frame could regress a value.

Added `apps/flutter/lib/src/core/session/projection_store.dart`:
`SessionProjectionStore.offer(key, value, seq)` accepts only strictly-newer
watermarks; `seed(block)` enters each key at the block cut and returns the keys
that may still publish (a stale baseline cannot overwrite a newer frame);
`sessionProjectionStores` keeps one store per session for the container
lifetime so seq memory survives reconnect resyncs.

Wired into `apps/flutter/lib/src/core/session/live_sync.dart`: the mux push case
guards all title/plan/permissions folding behind `offer(...)`, and all three
history-resync sites (subscribe-with-empty-live, reconnect-current,
reconnect-all) seed through `publishableProjectionKeys(...)` before publishing.
One deliberate behavior delta, matching the React contract: a history tail that
carries a projections block *without* a `title` key no longer clears the local
title (absent key = capability absent, not an empty title).

New tests: `apps/flutter/test/session/projection_store_test.dart` (7 cases:
strictly-newer acceptance, stale-baseline-vs-push race, same-cut idempotence,
per-key independence).

## New wire-contract tests

`apps/flutter/test/api/connection_client_rpc_test.dart` pins the unary RPC face
against a scripted HTTP host: `POST /api/<method>` carries
`{type:'client-request', rpcId, method, payload}` plus the `x-rpc-id` header;
the responder echoes the initiator-minted UUID rpcId; results unwrap through
`result.value`; `result.ok == false` discriminates into an exception carrying
the error message; `session.create` sends only set fields and unwraps
`result.value.sessionId`; `respond()` posts the `client-response` carrier
echoing the requested frame's rpcId and parses the `{accepted}` receipt;
non-2xx carrier status surfaces as an exception.

## Carrier corrections recorded in the tracker

Legacy targets pointed at files that never existed. Each row now names its real
carrier, verified unique across the whole ledger (the gate forbids two rows
claiming one file):

- runtime.session-store → `core/session/live_sync.dart` (frame dispatch into resident state; list store itself belongs to `state.sessions`)
- runtime.projection-store → `core/session/projection_store.dart` (new, above)
- runtime.pending-interactions → `plugins/user_questions/questions_state.dart` (+ `question_responder.dart` as response carrier)
- interaction.plane → `plugins/user_questions/ui/question_node_card.dart`
- runtime.remote-event-dispatch → `core/services/remote_event_bus.dart` (`RemoteEventBus.$on`/`dispatch`, extracted from runtime_services.dart with a re-export because that file is already claimed by form.locale; fed by live_sync's `host/remote-event` route)
- settings.runtime-scope → `core/bootstrap/app_plugins.dart` (`SettingsPlugin` `'ui-settings'` provides `'settingsScope'` and registers the children plugins; the scope mirror seam itself belongs to runtime.settings-scope)
- protocol.rpc-contracts → `core/api/rpc_envelope.dart` (rpcId/RpcError/result carriers; `frames.dart` and `host_description.dart` are companion faces owned by sibling rows)
- slot.tool-renderer-registry → `plugins/tool/tool_presentation_registry.dart`
- modules.client-plugin-loading → `core/plugin/plugin_host.dart` (service table + fixpoint activation)
- plugin.client-lifecycle → `core/plugin/plugin_contract.dart` (`DshPlugin.apply`/`inject`/`onDispose` effect discipline)
- state.streaming-assistant → `features/conversation/message_provider.dart`
- state.streaming-reasoning → `features/conversation/chat_ui_adapter.dart`
- tool.lifecycle-pairing → `features/conversation/conversation_reducer.dart` (chat-pipeline call↔result site; the hub-fold site is `conversation_nodes.dart`, owned by `tool.subcall-topology`)
- api.llm → `features/model_selection/model_directory.dart` (`session.models` / `session.selectModel` consumer seam)
- locale.service-dictionaries → `plugins/conversation/locales.dart` (representative zh/en dictionary carrier; the LocaleService registry/bind/fallback face itself stays with form.locale's claim on runtime_services.dart — seam split recorded in the row notes)

## Commands executed for this pass

```
flutter analyze lib                                        → 0 errors (115→122 infos before lint cleanup, 0 errors after)
flutter test test/connection test/unit test/settings test/slots test/renderer \
  test/plugin test/services test/api test/session          → all pass (incl. new files)
flutter test test/integration/business_host_test.dart      → pass
flutter test test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart → pass
flutter test test/plugins/ws_chat/tool_plugin_test.dart    → pass
flutter test test/conversation/conversation_reducer_test.dart test/conversation/chat_ui_adapter_test.dart → pass
flutter test test/plugins/conversation_nodes_test.dart     → pass
flutter test test/replay/semantic_parity_test.dart         → 2/2
pnpm vitest run packages/client/runtime/tests/semantic-parity.client.spec.ts → 2/2 (React side, identical fixture)
pnpm run verify-flutter-tracker --check                    → OK (112 items)
```

Semantic replay evidence for session-store/streaming/pairing rows: both drivers
project the canonical fixture byte-identically
(`migration/parity-reports/react-parity-projection-v1.txt`); the fixture covers
text-delta and reasoning-delta coalesced settle, atomic tool call↔result
pairing, blank clearing, queue/jobs snapshots, approval/question request+resolve,
one `session/projection`, and stream errors on both carriers.

## Remaining honesty notes

- **runtime.pending-interactions / interaction.plane stay Audited (partial).**
  The question half is complete end-to-end (frame-fed store keyed by envelope
  rpcId, responder echoing it, composer-chain takeover, generic + plan-review
  cards). The approval half is absent: `ApprovalRequestedFrame` /
  `ApprovalResolvedFrame` decode but live_sync drops them; there is no approval
  wait store, no responder, and no approval card. Building that surface belongs
  to a package-migration pass, not this integration remediation.
- **state.streaming-tool stays Audited (not implemented).** The client wire
  folds `tool/call` atomically; React additionally accumulates
  `tool-call-delta` argument partials (`partial.ts`, ui-conversation assistant
  definition) and the Flutter side has no counterpart anywhere. The committed
  parity fixture contains zero tool-call-delta frames, so replay cannot see the
  gap — recorded here instead of faking coverage.
- **runtime.host-born-sessions stays Audited.** The invariant holds structurally:
  sessions exist only after `session.create` returns a host id (welcome flow in
  `app_router.dart`, sidebar new-session flow), with no local fake pre-entity.
  But both carrier files are already claimed by sibling rows
  (`route.conversation.chat.node`, `screen.sidebar`) and the gate forbids a
  second claimant, so the row cannot reach Integrated without either a small
  extraction of the creation policy into its own file or a Gatekeeper decision.
  The `session.create` wire contract is now pinned by
  `connection_client_rpc_test.dart` as partial evidence.
- platformParity remains unset on these rows: they are category
  runtime/protocol/state/api/slot, not platform categories, and Web/macOS
  sweeps belong to the platform agents' passes.
