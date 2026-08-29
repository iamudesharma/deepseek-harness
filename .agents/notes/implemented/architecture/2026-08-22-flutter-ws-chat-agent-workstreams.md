# Agent Note: Flutter WS-Chat + WS-Agent business-plugin workstreams

Status: implemented

[English](2026-08-22-flutter-ws-chat-agent-workstreams.md)

## Problem

After the ui-conversation hub reached its integration gate (chat-node seam, header/composer/details holes, seven runtime services), the plan's first four business plugins — ui-tool, ui-trajectory, ui-message-feedback (WS-Chat) and ui-subagent, ui-skill, ui-agent-preset, ui-plan (WS-Agent) — had no Flutter plugin boundary. Their legacy `features/*` code predated the host and could only render through direct router imports.

## Decision

Both workstreams ran as parallel agents against disjoint tracker row sets, producing one Flutter plugin per React package under `apps/flutter/lib/src/plugins/<name>/`, following the five-layer order (contract → services → slot registration → UI → tests). All seven register in the booted app host; subagent's navigation ports and plan's command executor are wired to real implementations at registration (`sessionsProvider.setCurrent` + list re-pull; carrier send for `/plan off` outcome mapping).

Chat-node contributions register on the shared `ConversationController.renderers` seam keyed by wire tool/node name — the Dart analog of React's keyed `conversation.chat.node` entries — with per-tool presentation dispatch extracted to a dedicated registry (`tool.call.toolview` analog). Trajectory contributes into `conversation.view`; skill feeds the `/` trigger source with single-flight caching; agent-preset renders a leading header band.

All ten affected tracker rows advanced to `Integrated` with integration points citing boot activation, hub cohabitation, and per-plugin runtime tests (341 suite green, analyzer clean).

## Alternatives considered

**Direct feature imports retained (no plugin boundary).** Rejected: it recreates the flat-screen architecture the migration exists to replace, and dependent packages could not contribute chat-node renderers without cross-importing the conversation screen.

**One combined "business plugins" agent instead of two workstreams.** Rejected: the row sets are disjoint by plan design; parallel agents with per-row ownership kept write authority clean and halved wall-clock time.

## Consequences

The chat-node registry currently has no per-entry removal (contributions live until host teardown) — acceptable while the host boots once per process, but hot-swap of individual renderers will need a removal API. Registrations that require undeclared hub holes (subagent composer chain seat, agent-preset settings rows/hero chip, tool details hole, plan input seat) are deferred with their declarations pending in `kConversationChildSlots`; each is documented at its plugin. Chip undo/redo intents are declared but handled by no one until the input-trigger workstream.
