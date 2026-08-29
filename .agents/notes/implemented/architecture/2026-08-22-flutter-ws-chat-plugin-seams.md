# Agent Note: Chat plugin seams for ui-tool / ui-trajectory / ui-message-feedback in Flutter

Status: implemented

English | [中文](2026-08-22-flutter-ws-chat-plugin-seams.zh.md)

## Problem

The React client composes `ui-tool`, `ui-trajectory`, and `ui-message-feedback` through slot entries (`conversation.chat.node` keyed `'tool-call'`, the `tool.call.toolview` child hole, `conversation.view`, `conversation.chat.assistant-actions`). The Flutter conversation plugin drives chat-node rendering through a different seam — `ConversationController.renderers` (hub.dart), dispatched by node-kind key where a `ToolNode` dispatches by its wire tool name — and declares only four ledger keys (`conversation`, `conversation.session.header.actions`, `conversation.composer.dock`, `conversation.details`). Porting the three packages 1:1 would register into holes no shell ever declares, while the live dispatch path would go unused.

## Decision

Port each package as a `DshPlugin` under `apps/flutter/lib/src/plugins/{tool,trajectory,message_feedback}/`, translating slot semantics onto the seams that actually render today:

- **ui-tool** registers one chat-node renderer per wire tool name on `ConversationController.renderers` — the Dart analog of the keyed `'tool-call'` entry, because the Flutter fold keeps one `ToolNode` per call. The `tool.call.toolview` child hole becomes service `'toolPresentation'`: a `ToolPresentationRegistry` with an open key domain, conflict-throwing `register`, and the generic card applied at the dispatch site exactly like React's `fallback:` parameter. Shipped presentations mirror React's registrations (bash/read rows, edit/write diff row, grep/glob search row); todo/web/ask rows stay unclaimed and keep the generic fallback until ported.
- **ui-trajectory** keeps React's ledger shape: a wait-and-follow injection into `conversation.view` (id `'trajectory'`, order 10) that installs once a shell declares the hole, rendering the provider-backed screen for the selected session. React's `conversationEvents`/`conversationViews` services have no Dart counterparts yet, so the timeline fold is not re-implemented.
- **ui-message-feedback** provides service `'messageFeedback'` (per-session controllers) and ports the controller slice that carries real semantics: list-once seeding, mutations serialized behind a tail future, version compare-and-set with reconciliation from the `version-conflict` reply's authoritative row. The assistant-actions ledger entry waits on both the undeclared hole and a generated remote namespace.

Feature widgets moved with their behavior: the provider-based tool tree to `plugins/tool/ui/tool_call_tree.dart`, the trajectory screen/provider to `plugins/trajectory/`, the feedback screen/provider to `plugins/message_feedback/`. Two compatibility re-export shims remain at the old feature paths (`features/tool/tool_models.dart`, `features/trajectory/trajectory_screen.dart`) solely because out-of-scope importers (WIP `chat_ui_adapter_test.dart`, `app_router.dart`) still reference them; delete each shim together with its importer.

## Alternatives considered

**Register ledger entries into `conversation.chat.node` anyway** (queued until declared). Rejected: nothing in the Dart composition declares that subtree, so the registration would be permanently dead machinery while the actual dispatch happens through the renderer registry.

**Extend `ChatNodeData` with status/args/sessionId** so the tool renderer sees the full call. Rejected here: it is a conversation-plugin contract change owned by another workstream; the current adapter derives what the fold already exposes deterministically (one line = running, two = settled) and enriches automatically when the share grows.

## Consequences

Tool cards, the trajectory tab, and feedback controllers are testable without a booted shell; `test/plugins/ws_chat/` covers registry dispatch per folded tool name, install-on-declare for the trajectory tab, and toggle/retract/conflict controller semantics. The details panel (`conversation.details.tool`), assistant-actions wiring, and the todo/web/ask summary rows are deliberately absent and land with their owning integration work — an unclaimed name renders the generic card rather than failing.
