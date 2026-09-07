# Event Inventory

Audited 2026-08-21 from `packages/core/session/src/types.ts`, `packages/core/session/src/known-event-types.ts`, and the persistence catalog.

Canonical `SessionEventMap` is merge-extensible: core defines 13 members at `packages/core/session/src/types.ts:236`, the rest arrive via `declare module '@deepseek-ai/dsh-session/types'` across packages. `docs/persistence-catalog.md` is the freshness-gated enumeration.

## Envelope

- `SessionEvent<T>` at `packages/core/session/src/types.ts:408` — `type`, `seq`, `time`, `data`, optional `ignorable`, and `surfaceOp/sourceEventSeqs` only when `SurfaceEventType`.
- Default `required-on-read`: a reader meeting an unknown `type` without `ignorable:true` must refuse the log. `SESSION_FORMAT_VERSION=0` at `packages/core/session/src/types.ts:56`; only structural format changes bump it (agent note 2026-08-10).

## Known event types (48)

Surface events (also project): `user/message`, `assistant/message`, `tool/result`. All others log-only.

| Event | Declaration | Surface |
|---|---|---|
| `turn/start`, `turn/end` | `packages/core/session/src/types.ts:243,252` | no |
| `step/start`, `step/end` | `packages/core/session/src/types.ts:254,256` | no |
| `user/message` | `packages/core/session/src/types.ts:264` | yes |
| `assistant/chunk` | `packages/core/session/src/types.ts:266` | no |
| `assistant/message` | `packages/core/session/src/types.ts:277` | yes |
| `tool/call`, `tool/result` | `packages/core/session/src/types.ts:283,295` | tool/result yes |
| `todo/write` | `packages/core/session/src/types.ts:303` | no |
| `request/header`, `request/context` | `packages/core/session/src/types.ts:308,313` | no |
| `session/end-seed` | `packages/core/session/src/types.ts:336` | no |
| `agent/inbox/spliced` | `packages/core/agent/src/types.ts:19` | no |
| `agent-preset/selected` | `packages/preset/agent-presets/src/session.ts:26` | no |
| `approval/asked`, `approval/decided`, `approval/policy` | `packages/interaction/user-approval/src/index.ts:44,55,67` | no |
| `command/run`, `command/done` | `packages/interaction/commands/src/types.ts:96,103` | no |
| `compaction/start|summary|end|prune` | `packages/compaction/compaction/src/types.ts:23,33,71,81` | no |
| `feedback/record` | `packages/feedback/command-feedback/src/index.ts:62` | no |
| `goal/change` | `packages/goal/goal/src/domain.ts:66` | no |
| `hook/invoked`, `hook/result` | `packages/hooks/hook-protocol/src/types.ts:19,31` | no |
| `llm/retry`, `llm/retry-started` | `packages/llm/llm-retry/src/types.ts:9,11` | no |
| `permission/preset` | `packages/interaction/permission-presets/src/index.ts:50` | no |
| `plan/mode` | `packages/plan/plan-mode/src/index.ts:54` | no |
| `sandbox/mode` | `packages/sandbox/sandbox-policy/src/session-mode.ts:33` | no |
| `schedule/change` | `packages/schedule/schedule/src/types.ts:219` | no |
| `session/title`, `session/title-llm-request` | `packages/session/session-title/src/index.ts:100`, `packages/session/session-title-llm/src/index.ts:43` | no |
| `subagent/descriptor` | `packages/subagent/subagent/src/descriptor.ts:37` | no |
| `team/*` (4 types) | `packages/experimental/agent-team/src/types.ts:206,208,210,212` | no |
| `tool/code-dispatch*` | `packages/core/tools/src/types.ts:40,56` | no |
| `tool-workflow/*` (4 types) | `packages/workflow/tool-workflow/src/types.ts:47,52,57,62` | no |
| `web/deepseek-search-llm-request` | `packages/web/web-search-deepseek/src/provider.ts:83` | no |

Listing is authoritative via `packages/core/session/src/known-event-types.ts:19` (`KNOWN_SESSION_EVENT_TYPES`, 48 strings) and `docs/persistence-catalog.md`.

## Flutter mapping

- Event vocabulary → planned Flutter core-events module with per-kind decoders (not yet created); unknown kinds fail loud.
- Replay fixtures keyed by event `type`+`seq` for the E2E agent.

## Sources

- `packages/core/session/src/types.ts`
- `packages/core/session/src/known-event-types.ts`
- `docs/persistence-catalog.md`
- `docs/architecture.md`
- `packages/core/agent/src/types.ts`
- `packages/interaction/user-approval/src/index.ts`
- `packages/interaction/commands/src/types.ts`
- `packages/compaction/compaction/src/types.ts`
- `packages/goal/goal/src/domain.ts`
- `packages/hooks/hook-protocol/src/types.ts`
- `packages/llm/llm-retry/src/types.ts`
- `packages/plan/plan-mode/src/index.ts`
