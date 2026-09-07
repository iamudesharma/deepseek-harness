# ui-conversation → Flutter Conversation Plugin — Architecture Map

P1.5 preparation artifact (migration/plan.md §P1.5). Extracted from
`packages/client/ui-conversation/src/client/` on 2026-08-22. The migration unit
is the whole plugin; `conversation_screen.dart` is not a unit.

## 1. Plugin identity

| | React | Flutter target |
|---|---|---|
| id | `ui-conversation` (`@deepseek-ai/dsh-client-ui-conversation`) | plugin id `'ui-conversation'` |
| inject | `['slots','layout','sessions','workspaces','locale','connection','remote','settingsScope','conversationEvents','conversationViews']` | first slice: `['slots','connection','runtime','settingsScope']`; remaining names land with their runtime rows |
| provides | `ctx.conversation` (`IConversation`) | service `'conversation'` |

## 2. Slot registrations (apply.ts, 9 registers)

Anchor tree declared by the root register:

```
conversation                      single/root-scope anchor (children below)
├─ conversation.session           single/session   (store: chatStore)
│  └─ conversation.session.header single/session
│     └─ …header.actions
├─ conversation.composer          chain/session    (select: approval gate)
│  └─ conversation.composer.bar   single/session-maybe
├─ conversation.view              list/session     (id 'chat' declares ↓)
│  └─ conversation.chat.node      keyed/session    ← THE chat-node renderer seam
├─ conversation.message.images     list/session
├─ conversation.input.overlay / input.dock / composer.dock /
│  input.left / input.right        list/session
├─ conversation.details           single/session → child conversation.details.tool (keyed)
├─ conversation.hero.brand.mark / hero.workspace / hero.agentPreset   single/root
└─ conversation.chat.assistant-actions / chat.commandview / input.attachments /
   input.model / input.plan                            (aux holes)
```

`conversation.chat.node` is the seam the 18 dependents plug into (tool,
goal, trajectory, subagent, plan, workflow-run, deliverables, jobs,
user-questions, message-feedback each register a keyed renderer).

## 3. Service face (`service.ts`)

`IConversation { input: SessionInputResolver; blocks: ComposerBlocks;
send(text): Promise<void>; updateQueue(itemId, action): Promise<void>; cancel(…) }`
plus class `ConversationController` constructed via `ctx.plugin(...,{input,blocks})`.
Supporting pieces: `InputHub`, `ComposerBlockRegistry`, `ComposerSubmissionPolicy`
(`submission-settings.ts` namespace `CONVERSATION_SETTINGS_NAMESPACE`).

## 4. Stores

`createChatStore()` — shared handle passed to several registrations
(scroll position, drafts, panel state; NOT session data — that lives in the
object layer per client AGENTS.md rule 5/6).

## 5. Conversation nodes (`conversation-nodes/`)

Deterministic fold definitions, one file per family:
assistant, command, compaction, fallback, inbox, message, retry, tool,
turn-error, turn-max-tokens, turn-tail (+ `chat-snapshot-builder.ts`,
`register.ts`). Contract: `match(event)` reads only the current event;
`update` folds one match into State, replayable by log `seq`.

## 6. Dependent-package injection targets (18)

Each contributes via `slots.inject('conversation.…', () => slots.register(…))`:

| Package | Target slot(s) |
|---|---|
| ui-tool | `conversation.chat.node` key `<tool>` + declares `tool.call.toolview`; `conversation.details.tool` |
| ui-goal / ui-trajectory / ui-plan / ui-jobs / ui-workflow-run / ui-deliverables / ui-message-feedback / ui-user-questions / ui-subagent | `conversation.chat.node` keyed entries |
| ui-model-selection | `conversation.input.model` |
| ui-input-trigger | `conversation.input.left/right` |
| ui-agent-preset | `conversation.hero.agentPreset` |
| ui-attachment | `conversation.input.attachments` |
| ui-permission-presets | `conversation.composer` chain (approval gate) |
| ui-brand-official | `conversation.hero.brand.mark` |
| ui-directory-picker-* / ui-settings-* / ui-commands / ui-reference / ui-skill | indirect through their hosts above |

## 7. flutter_gen_ai_chat_ui decision

**Strategy A — isolate behind the chat-node seam** (chosen), with B as the
pre-committed fallback.

Grounds: current WIP confines the package to two files —
`chat_ui_adapter.dart` (harness→`ChatMessage` mapping) and
`widgets/harness_ai_chat.dart` (list mount). Folding stays in our reducer.
The WIP diff *converges toward* the React model (ports `displayFailureMessage`
from `sessions/failure-display.ts`, moves tool-calls out of assistant content
into real `tool/call` events, adds the `errorCode` chip mirroring
TurnErrorItem) — evidence the package can serve as one renderer's presentation
layer. Trigger for B: any point where `ChatMessage`/controller identity forces
folding or ordering into the package (parity violation), starting with its two
red tests.

## 8. WIP ownership boundary (do-not-cross until handoff)

- WIP-owned: `chat_ui_adapter.dart`, `conversation_reducer.dart`,
  `widgets/harness_ai_chat.dart` (by extension), `test/conversation/*`.
- Migration-owned (untouched by WIP): `message_provider.dart`,
  `live_sync.dart` consumption, session providers, P0 protocol parsers.
