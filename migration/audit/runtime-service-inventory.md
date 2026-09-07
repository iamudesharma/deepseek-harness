# Runtime Service Inventory

Audited 2026-08-21 from `packages/client/runtime/` and `packages/client/connection/`.

The runtime is the React-free object layer consumed via `SlotRegistry` and Riverpod. All mutable state is owned here; React is the renderer only.

## Session runtime

- **File:** `packages/client/runtime/src/client/sessions/`
- **Contracts:** `packages/client/runtime/src/client/contract/session.ts`, `packages/client/runtime/src/client/contract/sessions.ts`
- **Semantics:** per-session resident objects consuming `mux/host` frames. Create via `session.create` (host-born). Paging (`history`), shared event windows, contiguous windows per definition, `ConnectionGeneration`-scoped cleanup. Ordering: server seq, not client insertion order.

## Workspace runtime

- **File:** `packages/client/runtime/src/client/workspaces/`
- **Contract:** `packages/client/runtime/src/client/contract/workspaces.ts`
- **Semantics:** baseline `workspace.list` → incremental `workspace/create|update|delete` changes, optimistic insertion, tombstones, ordering, deletion resurrect-through-tombstone avoidance, reconnect re-baseline. Session/workspace relationship: `currentWorkspace` derivation falls back across grouped sessions.

## Projection store

- **File:** `packages/client/runtime/src/client/conversation/` projection helpers; `packages/core/session/src/types.ts` surface projection concepts
- **Contract:** `ProjectionValueStore` seeded from `session.history` projections, updated by `session/projection` frames, higher-seq-wins on reconnect.
- **Used by:** todo list, plan state, session summaries, job indicators, compacted checkpoints.

## Pending interactions

- **File:** `packages/client/runtime/src/client/sessions/` pending-wait helpers; `packages/interaction/user-approval/`, `packages/interaction/commands/`, `packages/plan/plan-mode/`
- **Semantics:** per-session pending waits keyed by request id, prioritized across question vs approval vs plan review, routed via `selectApproval` / input `overlay` MenuView, reconnect-preserving.

## Remote / host dispatch

- **File:** `packages/client/connection/src/client/` (`connection.ts`, `rpc.ts`, `web-api-client.ts`)
- **Contract:** `ConnectionHandle` (`api`, `hostDescription`, `rpc`, `start()`), `HostDescription` only after readiness, mux/host dual downlinks, frame fanout to session runtimes.

## Settings scope

- **File:** `packages/client/runtime/src/client/contract/settings-scope.ts`
- **Semantics:** per-scope (host, workspace, session) settings mirrors, schema validation, persistence, host transport. Backs locale, theme, model selection.

## Reconnect / generations

- **File:** `packages/client/connection/src/client/connection.ts`
- **Semantics:** `ConnectionGeneration` increments on disconnect; generation-bound stores clear on disconnect; `reconnectAttempt`/`backoff`/`resync` fill gaps; reconnect replays missed history/projection frames.

## Sources

- `packages/client/runtime/README.md`
- `packages/client/runtime/src/client/index.ts`
- `packages/client/runtime/src/client/contract/session.ts`
- `packages/client/runtime/src/client/contract/sessions.ts`
- `packages/client/runtime/src/client/contract/workspaces.ts`
- `packages/client/runtime/src/client/contract/settings-scope.ts`
- `packages/client/runtime/src/client/sessions/`
- `packages/client/runtime/src/client/workspaces/`
- `packages/client/runtime/src/client/conversation/`
- `packages/client/connection/README.md`
- `packages/client/connection/src/client/connection.ts`
- `packages/client/connection/src/client/rpc.ts`
- `packages/client/connection/src/client/web-api-client.ts`
