# Agent Note: Flutter approval plane, tool-argument streaming, and host-born session policy extraction

Status: implemented

## Problem

The migration tracker carried four Audited core/runtime rows whose React contracts were traced but whose Flutter halves were missing or carrier-collisioned: `runtime.pending-interactions` (approval half absent; no sidebar reconciliation), `interaction.plane` (no approval surface), `state.streaming-tool` (unimplemented, wire contract untraced), and `runtime.host-born-sessions` (invariant implemented but both carrier files already claimed by sibling rows, so no unique flutterTarget remained).

## Decision

The interaction plane rides one shared reconciliation policy. `apps/flutter/lib/src/plugins/user_questions/pending_interactions.dart` owns the pure policy — stable wait keys `a:<approvalId>` / `q:<rpcId>`, plan-review narrowing through `planReviewOf`, question-beats-approval precedence, summary reconciliation through an explicit-clear `SessionSummary.withPendingInteraction`. Per-kind stores sit beside it (`questions_state.dart`, new `approval_state.dart`), and `live_sync.dart` routes all four interaction frames into them; a connection-generation drop clears waits and markers, and mux-open replay re-arms them idempotently.

Approvals answer only `allowed-once | rejected`: the client-answerable vocabulary comes from `packages/host/apiproxy/src/api/approvals.ts`, where cancelled/unavailable are host-side outcomes. The new card (`ui/approval_card.dart`, port of ui-conversation's ApprovalPanel at composer-chain priority 1) latches after one click, re-arms on a failed answer, and leaves only on the resolved frame.

Tool arguments stream inside `assistant/chunk` — there is no delta frame. The trace closed the three-way question for `state.streaming-tool` as option (a): the event carries `{turn, step, chunk: StreamChunk}` (`packages/core/session/src/types.ts`), the agent loop appends one event per delta (`packages/core/agent-loop/src/agent.ts`), and React accumulates in `PartialAccumulator.push` case `tool-call-delta` (`packages/client/runtime/src/client/sessions/partial.ts`). `core/events/tool_stream.dart` ports that accumulation and `ConversationNodeFolder` routes deltas onto the in-flight `AssistantNode.partialToolCalls`; the committed parity fixtures contain zero such chunks, so the semantic-parity byte compare needed no fixture change.

Host-born creation is extracted, not re-claimed: `core/session/host_session_policy.dart` holds three pure functions (`sessionCreatePayload`, `isWorkspaceAttachFailure`, `adoptHostBornSession`) consumed by `connection_client.createSession`, both sidebar creation flows, and the welcome submit. The two UI flows additionally project the adopted blank summary before the confirming list pull lands — a deliberate parity improvement matching React's synchronous-addressability guarantee in `manager.create`, and the one behavior change beyond mechanical extraction.

## Contract correction shipped in the same change

`QuestionIntent.tryFromJson` discarded the intent's `approve` label (hardcoded empty string), which silently disabled `planReviewOf` narrowing — the plan-review decision card could never claim its request. The decoder now carries the label through, restoring the documented routing and unblocking the identical predicate the status derivation depends on.

## Alternatives considered

A separate per-session multi-wait ledger mirroring React's manager map was rejected: the host serializes asks per session (one inline await per approval, one ask() at a time), so single-slot stores plus settlement-by-id carry the same observable behavior with less machinery; if concurrent asks ever surface, sibling-preserving storage returns locally to the two stores because settlement already matches on identity.

## Consequences

The cost: the approval card omits the paired-command line (React reads the running call's `argsRaw.command`; the Flutter node fold retains no argument text, so the line is absent rather than invented), and visual parity for the card stays partial until a golden diff exists. The purchase: both plane rows complete their request→pending→UI→respond→resolved→reconcile chain with tests, the streaming row implements only the real contract with citations instead of inventing a frame, and the host-born row gains a unique carrier through legitimate extraction while pinning the wire contract in `connection_client_rpc_test`.

## Testing

`flutter analyze lib` zero errors; new suites `apps/flutter/test/plugins/ws_input/approval_plane_test.dart`, `apps/flutter/test/session/tool_stream_test.dart`, `apps/flutter/test/session/host_session_policy_test.dart`; neighbors green (ws_input group, live_sync/sessions_controller unit tests, `api/connection_client_rpc_test`, conversation nodes/plugin tests, replay pair including semantic parity, `integration/business_host_test`). Evidence recorded in `migration/parity-reports/2026-08-26-approval-plane-streaming.md`.
