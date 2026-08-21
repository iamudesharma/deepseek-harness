# Interaction Inventory

Audited 2026-08-21 from `packages/interaction/*` event declarations and conversation wiring.

## Collaboration plane

| Interaction | Events | Package | Client surface |
|---|---|---|---|
| Tool approval | `approval/asked`, `approval/decided`, `approval/policy` | `packages/interaction/user-approval/src/index.ts` | `conversation.composer` chain head `ApprovalPanel` (`packages/client/ui-conversation/src/client/apply.ts:108`), permission presets picker |
| Ask-user questions | pending-wait keyed by request id | `packages/interaction/user-questions/` + session pending waits | question card routed via pending-interaction priority |
| Permission presets | `permission/preset` | `packages/interaction/permission-presets/src/index.ts` | `screen.ui-permission-presets` |
| Plan review | `plan/mode {active}` | `packages/plan/plan-mode/src/index.ts` | `conversation.input.plan` slot + plan review takeover |
| Commands | `command/run`, `command/done` | `packages/interaction/commands/src/types.ts` | command palette + `conversation.chat.commandview` fallback card |

## Pending-wait semantics

- Per-session pending waits prioritize: user question > approval > plan review (runtime routes the highest-priority interaction into the composer area).
- Reconnect preserves pending waits; responses are idempotent by request id.
- Approval takeover: when an approval arrives mid-composition it takes over the composer chain (`selectApproval` at `packages/client/ui-conversation/src/client/apply.ts:108`).

## Flutter mapping

- `PendingInteractionManager` with typed entries (question/approval/plan-review), request-id keyed, reconnect-preserving.
- Composer chain becomes a prioritized widget list mirroring `conversation.composer` chain order.

## Sources

- `packages/interaction/user-approval/src/index.ts`
- `packages/interaction/permission-presets/src/index.ts`
- `packages/plan/plan-mode/src/index.ts`
- `packages/interaction/commands/src/types.ts`
- `packages/client/ui-conversation/src/client/apply.ts`
- `packages/client/ui-plan/src/client/`
- `packages/client/ui-user-questions/src/client/`
- `packages/client/ui-permission-presets/src/client/`
