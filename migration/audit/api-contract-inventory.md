# API Contract Inventory

Audited 2026-08-21 from `packages/client/connection/`, `packages/client/runtime/src/client/contract/`, and `packages/client/modules/`.

All contracts are TypeScript-typed over the connection's HTTP + WS transport. Flutter must extract them mechanically, never hand-invent.

## Connection / transport

- `ConnectionHandle` — `packages/client/connection/src/client/index.ts:47-75` — fields `api: IApiClient`, `hostDescription: HostDescription | null`, `rpc: HostRpc`, `start(): Promise<void>`.
- `HostDescription` — only after readiness (`packages/client/connection/src/client/connection.ts`); cleared on generation disconnect.
- WS downlink — `packages/client/connection/src/client/web-api-client.ts` + `packages/client/connection/src/client/connection.ts` (mux + host frames, generation-scoped).

## Session surfaces

- `session.create` — host-born session + agent + cwd (client sends `workspaceId`, host creates entities).
- `session.list` / `session.history` — history paging + baseline snapshots.
- `session.prompt` — sends user message, does not deliver stream; stream arrives via `mux/host` frames.
- `session/projection` — `ProjectionValueStore` updates, higher-seq-wins.
- `session/event` — live event frames (typed via `SessionEventMap`).
- Sources: `packages/client/runtime/src/client/contract/session.ts`, `packages/client/runtime/src/client/sessions/`, `packages/client/connection/src/client/rpc.ts`

## Workspace surfaces

- `workspace.list` (baseline) + incremental `workspace/create|update|delete` — `packages/client/runtime/src/client/contract/workspaces.ts`, `packages/client/runtime/src/client/workspaces/service.ts`
- `host.listDirectory` / `host.createDirectory` / `host.pickDirectory` — `packages/client/runtime/src/client/contract/workspaces.ts:41`

## Interaction surfaces

- `approval/decided`, `permission/preset`, `plan/mode` event responders — `packages/interaction/user-approval/src/index.ts`, `packages/interaction/permission-presets/src/index.ts`, `packages/plan/plan-mode/src/index.ts`
- `command/run|done|feedback/record` — `packages/interaction/commands/src/types.ts`

## Settings / locale / models

- `SettingsScope` — `packages/client/runtime/src/client/contract/settings-scope.ts`
- Locale `zh/en` dictionaries — `packages/client/locale/src/locale-settings.ts`
- Model/provider config — `packages/client/ui-model-selection/src/client/`

## Brand / directory / attachment

- Brand slot fills — `packages/client/ui-brand-official/src/`
- Directory pickers (browse vs native) — `packages/client/ui-directory-picker-browse/`, `packages/client/ui-directory-picker-native/`
- Attachment limits — enforced both in `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx` and host submit.

## Sources

- `packages/client/connection/src/client/index.ts`
- `packages/client/connection/src/client/web-api-client.ts`
- `packages/client/connection/src/client/rpc.ts`
- `packages/client/runtime/src/client/contract/session.ts`
- `packages/client/runtime/src/client/contract/workspaces.ts`
- `packages/client/runtime/src/client/contract/settings-scope.ts`
- `packages/client/runtime/src/client/sessions/`
- `packages/client/runtime/src/client/workspaces/`
- `packages/client/modules/src/index.ts`
- `packages/interaction/user-approval/src/index.ts`
- `packages/interaction/permission-presets/src/index.ts`
- `packages/plan/plan-mode/src/index.ts`
- `packages/interaction/commands/src/types.ts`
