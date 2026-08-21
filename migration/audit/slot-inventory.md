# Slot Inventory

Audited 2026-08-21 from `packages/client/ui-slots/` and `packages/client/ui-conversation/` contract.

Slots are the feature composition seam: packages declare slots, fill them via `ctx.slots.register()`, and compose via `ctx.slots.inject()`. No feature imports another feature implementation.

## Slot core

- **Package:** `packages/client/ui-slots`
- **Files:** `packages/client/ui-slots/src/index.ts`, `packages/client/ui-slots/src/store.ts`, `packages/client/ui-slots/src/renderer.ts`
- **Key types:** `SlotMap` (merge-extensible), `PropsRuntime`, `PropsRenderSlots`, `PropsStore`, `ComposedProps`, `SlotRendererHost`

## Declared slots

### Conversation (from `packages/client/ui-conversation/src/client/contract/slots.ts`)

- `conversation` (root, declares 12 children)
- `conversation.session` (per-session)
- `conversation.session.header` + `conversation.session.header.actions` + `conversation.session.header.utilities`
- `conversation.view` (owner `ConvViewOwnerProps`)
- `conversation.chat.node` — keyed session slot, `ChatNode<Kind>` + hook context; inject `ChatNodeTurnDataInjected`
- `conversation.message.images` (per-session)
- `conversation.chat.commandview` — keyed session, fallback `GenericCommandCard`
- `conversation.chat.turnTail` — chain session
- `conversation.chat.assistant-actions` (list)
- `conversation.details.tool` — single session, `block: ToolCallBlock`
- `conversation.composer` — chain session, `ComposerChainProps{interactions,session}`
- `conversation.hero.workspace` (root)
- `conversation.hero.brand.mark` (root)
- `conversation.hero.agentPreset` (root)
- `conversation.composer.bar` (session-maybe)
- `conversation.input.attachments` (session-maybe, `ComposerAttachmentsOwnerProps`)
- `conversation.input.plan`, `conversation.input.model` (session)
- `conversation.input.dock`, `conversation.composer.dock`, `conversation.input.left`, `conversation.input.right` (lists)
- `conversation.input.overlay` (injected by input-trigger)

### Layout / sidebar / workspace

- `sidebar`, `conversation`, `details`, `shell.overlay` from `packages/client/ui-layout/src/client/index.ts`
- `sidebar.brand.*`, `sidebar.workspaces`, `sidebar.settings`, `sidebar.footer.action` from `packages/client/ui-sidebar/src/client/contract/slots.ts`
- `sidebar.workspaces.directoryFlow`, `conversation.hero.workspace.directoryFlow` from `packages/client/ui-workspace/src/client/contract/slots.ts`
- Tool: `tool.call.toolview` (keyed by tool kind) from `packages/client/ui-tool/src/client/contract/slots.ts`

## Flutter mapping

- `SlotMap` + `SlotRegistry` → `DshSlotRegistry` (`register/unregister/inject/resolve/render` with teardown)
- `createSlotRenderer`/`SessionProvider` → Flutter builder consuming `SlotRegistry` + `HostObservable` via `ValueListenableBuilder`
- Per-feature contributions become Dart slots in a planned Flutter core-slots module (target path decided at implementation; not yet created).

## Sources

- `packages/client/ui-slots/src/index.ts`
- `packages/client/ui-slots/src/store.ts`
- `packages/client/ui-slots/src/renderer.ts`
- `packages/client/ui-conversation/src/client/contract/slots.ts`
- `packages/client/ui-conversation/src/client/apply.ts`
- `packages/client/ui-layout/src/client/index.ts`
- `packages/client/ui-sidebar/src/client/contract/slots.ts`
- `packages/client/ui-workspace/src/client/contract/slots.ts`
- `packages/client/ui-tool/src/client/contract/slots.ts`
