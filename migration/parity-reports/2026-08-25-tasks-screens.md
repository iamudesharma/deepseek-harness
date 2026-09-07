# 2026-08-25 — Trajectory / Subagent / Agent-Preset / Message-Feedback / Skill screens (Agent C)

This report documents parity closure for the remaining Audited task/workflow feature screens against the React contracts in `packages/client/ui-trajectory`, `packages/client/ui-subagent`, `packages/client/ui-agent-preset`, `packages/client/ui-message-feedback`, and `packages/client/ui-skill`.

One line per paragraph; visual evidence is outside the tracker and remains unclaimed (`visual: missing` until goldens exist).

## Classification before changes

`screen.trajectory` classified partial: plugin contribution, routed timeline screen, and a pure history fold existed with a slot-lifecycle test, but the fold had no direct coverage and the React table view/toolbar/search were absent.

`screen.ui-subagent` classified partial: all React-package registrations (header catalog action, keyed node renderer, read-only composer widget + verbatim claim selector, navigation link) existed and were tested, but the standalone screen rode hardcoded demo fixtures — production synthetic fallback.

`screen.ui-agent-preset` classified partial: roster/list/select/label were real over `agentPreset.list`/`agentPreset.select`, while view/copy/delete were stubbed snackbars ignoring the `authorable` gate from the wire contract.

`screen.ui-message-feedback` classified partial-strong: the controller port (CAS versioning, serialized mutations, conflict reconciliation, note asymmetry) was complete and tested, but the surface carried demo rows plus synthetic 400 ms/300 ms delays.

`screen.ui-skill` classified implemented-but-missing-evidence for its React contract surface (keyed tool row + session-keyed catalog), except the `'/'` trigger source registration was missing entirely; the catalog-browse screen is a Flutter-side extra.

## Traced React contracts

`ui-skill/src/client/index.ts` registers three effects: locale dictionaries, the `tool.call.toolview` key=`skill` row (`SkillRow.tsx`: state-derived leading icon, first-line error summary, instructions disclosure, plain Inspect), and the `'/'` input-trigger source (order 2, single-flight per-session `skill.list` cache, prefix filter, user-only marker riding the description, pick landing literal `/name `, warm hook, lexicon roll + `subscribeLexicon`, preset-switch invalidation of exactly that key, connection/reset clearAll).

`ui-subagent/src/client/index.ts` registers dictionaries, the header catalog action (`SubagentCatalogAction.tsx`, id `subagent-catalog`, order 10, visible only with evidence of children), and the composer chain takeover (priority −10, `selectReadOnlySubagent` claiming one-shot history and stopped parent-offline continuable children); `openChild` lands on the child row through the shared sessions list.

`ui-agent-preset/src/client` mounts four surfaces over one roster: General-settings default row, new-session chip, header label, and management section (`AgentPresetSection.tsx` + `section-store.ts`: trust-grouped cards, broken/in-use badges, copy dialog as the only creation path, confirmed delete gated on `authorable`, read-only viewer fed by `agentPreset.read`, location action via `agentPreset.openDocument`).

`ui-message-feedback/src/client` registers one controller per session into `conversation.chat.assistant-actions` (`MessageFeedbackActions.tsx`: hover/focus seeding, toggle decided against committed items, note popover with stale-generation guards, row vs panel failure surfacing).

`ui-trajectory/src/client` registers conversation-node definitions plus the `conversation.view` tab rendering table/timeline alternatives over a snapshot builder with search index and virtual rows.

## Flutter work this pass

`apps/flutter/lib/src/plugins/skill/skill_plugin.dart` now registers `_SkillSource` into the `TriggerSourceRegistry` (trigger `/`, name `skill`, order 2): candidates filter the catalog, the description carries `user-only · …`, the pick returns `TextOutcome('/name ')`, and warm/lexicon/subscribeLexicon ride the catalog's single-flight cache; teardown removes the source and drops every cached key with the existing invalidation path.

`apps/flutter/lib/src/plugins/subagent/ui/subagent_provider.dart` replaced both demo fixtures with real derivations: `subagentsFamilyProvider(parent)` maps summary-known children (`origin == 'subagent'`, oldest first) off the shared sessions list, and `subagentTranscriptProvider(child)` folds the child's durable history (`user/message`, `assistant/message`, `tool/call`) into transcript rows; `transcriptFromHistory` is pure and directly tested.

`apps/flutter/lib/src/plugins/message_feedback/ui/message_feedback_screen.dart` and `message_feedback_provider.dart` dropped the demo row list, the fake loading future, and the artificial save delays; an unseeded surface shows the empty state and taps commit through the store immediately, matching the React posture where nothing renders until recorded feedback exists.

`apps/flutter/lib/src/plugins/agent_preset/ui/agent_preset_provider.dart` parses `authorable`/`hasDocument` alongside `presets` into `AgentPresetRoster` and adds `readPresetComposition`/`copyPreset`/`removePreset` over `callMethod('agentPreset.read'|'agentPreset.copy'|'agentPreset.remove')`; `agent_preset_screen.dart` gates duplicate/delete on authorability with broken presets excluded, opens the real composition text in the viewer, submits `{from, agentPreset, name}`, confirms removals, refreshes the roster after each mutation, and reports failures as snackbars instead of pretending success.

`apps/flutter/test/plugins/ws_chat/trajectory_fold_test.dart` covers the trajectory fold: envelope mode bounding turns and honoring `isError`, dangling envelopes staying running, user-boundary fallback with assistant summaries and time-window tool joining, trailing-chunk running status, and whole-log initial turns.

Focused suites extended in place: `skill_plugin_test.dart` gains source candidates/pick/lexicon/deactivation cases, `subagent_plugin_test.dart` gains fixture-free screen listing, empty-state, and fold cases, `message_feedback_plugin_test.dart` rewrites its widget case around seeded store state with toggle semantics, and `agent_preset_plugin_test.dart` gains roster/badge, viewer, copy-payload, and confirm-delete widget cases against a recording client double.

`app_router.dart` line 321 was the only external consumer of the reshaped provider and now reads `AgentPresetRoster.presets`.

## Verification

`flutter analyze lib` reports 0 errors across the app (60 pre-existing warnings, 51 infos; zero findings inside the five plugin trees).

`flutter build web --no-pub` succeeds (98.5 s, wasm dry run clean), verifying the web compile target including every changed file.

`flutter test test/plugins/ test/integration/business_host_test.dart` passes 238 tests: ws_agent 38 (incl. skill source, subagent link/screen/fold, agent-preset management), ws_chat (trajectory plugin + fold, message feedback, tool), ws_tasks, ws_input, ws_surfaces, directory_picker, and the real-app co-activation gate asserting the skill/subagent node keys and hole composition.

`flutter test test/widgets/` passes 113 tests (conversation hub, primitives, motion, frame).

macOS verification rides the same runs executing on the macOS host plus the clean analyzer; neither platform column claims full runtime-device parity yet (`platformParity: partial`).

## Tracker Update

All five rows moved Audited → Integrated with corrected targets pointing at the owning plugin files (the previous `features/*` paths did not exist or were compatibility shims).

`parityCheck.behavior` records `partial` per row: ported semantics are unit-proven (fold rules, CAS controller, catalog cache, link navigation, claim selector), while end-to-end behavioral parity awaits replay evidence; `visual` stays `missing` pending goldens.

`integrationPoints` name the live seams each surface already hangs on; `e2eScenarios` record meaningful replay candidates even though screen-category rows do not require them; `subagent.runtime-link` (category runtime) was left untouched for its owning agent.

## Remaining Gaps

Trajectory: React's table view alternative, toolbar search index, virtual rows, duration store, and the six conversation-node definitions remain with the conversation-fold workstream; the queued `conversation.view` contribution installs when a shell declares the hole.

Subagent: catalog token/duration metrics need projection values the Dart `SessionSummary` does not carry; the read-only composer registers when the hub grows a composer chain seat.

Agent-preset: the General settings row and hero chip register when `settings.general.item` / `conversation.hero.*` holes land; openLocation needs the native opener face.

Message-feedback: controls move into the assistant message actions row when `conversation.chat.assistant-actions` is declared, and mutations go live when a Dart carrier exposes `remote.messageFeedback`.

Skill: tool-row lifecycle coloring waits for a settled status bit on the chat-node seam; connection/reset clearAll lands with the connection generation row.
