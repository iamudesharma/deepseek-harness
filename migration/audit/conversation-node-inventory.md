# Conversation Node Inventory

Audited 2026-08-21 from `packages/client/runtime/src/client/conversation/` and `packages/client/ui-conversation/src/client/`.

## Contracts

- `ConversationNodeDefinition<State>` at `packages/client/runtime/src/client/contract/conversation.ts:171-228` — `kind`, optional `target`+`buildViewNode`, `match(event)->{id,role}|null`, `start(context,match,reader)`/`update(context,match)`, `publication` (`none`/`animation-frame`/`immediate`), `buildLocationData`/`buildViewNode`. `ConversationContext<State>` (`key,kind,id,matches,start,state,current`), `ConversationPreviousContext`, `ConversationContextReader.previous(kind)` (strictly backward, agent note 2026-08-09).
- Registries: `ConversationDefinitionRegistry` (`packages/client/runtime/src/client/conversation/definition-registry.ts`), `ConversationEventRegistry` (sole `registerFallback`), `ConversationViewRegistry`.
- Snapshot: `ConversationSnapshot` at `packages/client/runtime/src/client/sessions/conversation.ts:368-431` — `ChatSnapshot{order,nodes:ChatNodeStore,locations:ChatLocationNodeIndex,timeline,legacy}`, keyed store values are reference-stable live readers. `ChatSnapshotBuilder` at `packages/client/ui-conversation/src/client/conversation-nodes/chat-snapshot-builder.ts`.

## Built-in node definitions (13, at `packages/client/ui-conversation/src/client/conversation-nodes/register.ts:19`)

- `inbox-next-turn`, `inbox-next-step` — `inbox.ts`
- `input-message` — `message.ts`
- `assistant-step` — `assistant.ts` (matches `step/start|assistant/chunk|assistant/message|llm/retry`, publication `animation-frame` for chunks else `immediate`)
- `tool-call` — `tool.ts` (recursive `subCalls`)
- `command` — `command.ts`
- `compaction` — `compaction.ts`
- `model-retry` — `retry.ts`
- `turn-error`, `turn-max-tokens`, `turn-tail` — `turn-*.ts`
- `unknown-surface` (fallback) — `fallback.ts`
- Each registered via `ConversationEventRegistry.register(kind)` through `ctx.effect`.

## Streaming tail

- `publication: animation-frame` for `assistant/chunk` is coalesced by `Notifier` (`packages/client/runtime/src/client/sessions/notifier.ts:14-50`: N `markFrameDirty` → 1 `requestAnimationFrame`, `markDirty` → 1 microtask).
- Append cost is `#definitions + updated IDs`, not history length (agent note section 6.5).

## Flutter mapping

- Definitions → planned Flutter conversation-nodes module, one builder per kind (not yet created)
- Context folding → per-kind state classes + `ConversationSnapshot` equivalent
- View builder → `ChatSnapshotBuilder` port
- Tests: golden snapshots for grouped turns, nested tools, compaction, retry, 10K+ events.

## Sources

- `packages/client/runtime/src/client/contract/conversation.ts`
- `packages/client/runtime/src/client/conversation/definition-registry.ts`
- `packages/client/runtime/src/client/conversation/event-registry.ts`
- `packages/client/runtime/src/client/conversation/view-registry.ts`
- `packages/client/runtime/src/client/sessions/conversation.ts`
- `packages/client/ui-conversation/src/client/contract/slots.ts`
- `packages/client/ui-conversation/src/client/apply.ts`
- `packages/client/ui-conversation/src/client/conversation-nodes/register.ts`
- `packages/client/ui-conversation/src/client/conversation-nodes/chat-snapshot-builder.ts`
- `.agents/notes/implemented/architecture/2026-08-09-client-conversation-node-assembly.md`
