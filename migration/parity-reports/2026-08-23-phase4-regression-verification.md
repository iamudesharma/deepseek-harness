# Phase 4 Full Regression Verification — Agent F

Date: 2026-08-23 · Scope: post-wave regression sweep over the four concurrent agent landings
(A approval plane + tool_stream + host_session_policy, B input-trigger shortcuts + HoverCard +
route.root, C JsonTree/DsTooltip/DsIcons, D brandwordmark/fish_logo/session_workspace_services).

**Zero code changes were required. No regressions found. No tracker statuses touched.**

## 1. Shared-file conflict sweep

- `git status --porcelain`: 282 entries, all attributable to the four waves; no conflict markers
  (`<<<<<<<` / `=======` / `>>>>>>>`) anywhere under `apps/flutter/lib` or `apps/flutter/test`.
- Multi-touch seams verified wired and coherent:
  - `runtime_services.dart` re-exports `session_workspace_services.dart` (D's split) while keeping
    LocaleService + RemoteEventBus exports (A's earlier extraction) — single stable import face.
  - `session_workspace_services.dart` imports only connection_client + session_models.
  - `live_sync.dart` — A-only, untouched by others.
  - `conversation_nodes.dart` imports `core/events/tool_stream.dart`; `PartialToolCall` list on node
    model; folder folds deltas (tool_stream_test covers fold semantics).
  - `sidebar.dart` carries A's host-born `_handleNewSession`/`onCreateIn` (host_session_policy
    import) **and** C's DsTooltip plates + DsIcons rail controls together.
  - `app_router.dart` carries A's welcome adopted-blank edit + D's fish_logo import + SlotOutlet
    composition; B's route.root landed in `main.dart`.
  - `composer.dart` mounts `ComposerTriggerBinding` (B).

## 2. Analyzer

`flutter analyze lib`: **0 errors**, 123 warnings/info (lint-level: prefer_initializing_formals,
unused_import, invalid_use_of_protected_member in model_seat tests-only paths, etc.). C's mid-flight
flags on `tool_stream.dart` and `composer.dart` are clean in the final state. Gate met; lint cleanup
is not a regression and was not attempted.

## 3. Full Flutter test suite

`flutter test --reporter compact` run to completion: **754 passed / 0 failed / 0 skipped**
("All tests passed!"). No failures to classify.

## 4. Semantic parity

- `pnpm vitest run semantic-parity`: 1 file / 2 tests passed ("projects the canonical fixture
  identically to the committed reference").
- `flutter test test/replay/semantic_parity_test.dart`: 2 passed, including gap-repair/resync.
- Both suites read `migration/parity-reports/react-parity-projection-v1.txt` directly and assert a
  byte match; both green ⇒ projection is byte-identical to the reference. Nothing regenerated.

## 5. Golden tests

`flutter test test/goldens`: **36 passed / 0 failed without `--update-goldens`.** No regeneration
performed; no existing golden was stale.

Follow-ups noted (not blockers):
- No goldens yet for this wave's genuinely new visuals: approval card, trajectory Payload/Result
  DsJsonTree section, sidebar rail DsTooltip hover rendering. Per instructions these are recorded
  as follow-up rather than regenerated blindly.
- Residue from earlier runs (not deleted): `test/goldens/failures/*` diff artifacts (Aug 23 09:05)
  and scratch `_repro_fold_test.dart`.

## 6. Builds

- Web release (`--dart-define=DSH_HOST_URL=http://127.0.0.1:8787 --no-wasm-dry-run`): ✓ built in
  141 s (fonts tree-shaken).
- macOS debug (`--no-pub`): first attempt failed "CocoaPods not installed" — environmental;
  CocoaPods exists at `/opt/homebrew/bin/pod` but was off PATH. With `/opt/homebrew/bin` on PATH:
  ✓ built `build/macos/Build/Products/Debug/dsh_flutter.app` (harmless xcodebuild build-number
  warnings).

## 7. Live-host flows

Server already running on 127.0.0.1:8787 (HTTP 200, node PID). No DEEPSEEK_API_KEY in env and no
root `.env`, so nothing new was started; exercised the running server via curl over the Typert wire:

| Flow | Result |
| --- | --- |
| `session.create` | ✓ `session-0832bbdd…` returned |
| `commands/execute` `/permission workspace-write` | ✓ `{kind:"success",text:"preset workspace-write"}` |
| `commands/execute` `/plan on` → `/plan off` | ✓ `plan/mode active:true`, then success text |
| history tail | ✓ contains `user/message` (role user), plus `permission/preset`,
`sandbox/mode workspace-write`, `approval/policy ask`, `command/run`+`command/done` pairs,
`plan/mode`, `session/title`, `request/header`+`request/context` |

Model generation itself: environment-blocked — the turn reached LLM dispatch and failed with
`llm-deepseek: no API key for provider route "deepseek-official"` inside the host process. Turn
lifecycle (`turn/start`, `step/start`, `user/message`, title fallback, request headers, `step/end`,
`turn/end` error reason) logged correctly up to that point. Not faked; needs a keyed host for the
final model-turn leg of manual QA.

Wire-shape notes discovered while exercising: remote-style methods require exactly one plain-object
`args` field (`{args:{agentId,line,images}}`); `session.history` takes a flat payload
(`sessionId`,`maxMessages`). Both match what `ConnectionClient` sends.

## 8. User-flow regression matrix (each suite re-run individually)

| Flow | Suite | Result |
| --- | --- | --- |
| Permission / access / plan | plugins/permission_model_plan_test.dart | 18 ✓ |
| Conversation integration | plugins/conversation_integration_test.dart | 22 ✓ |
| Nodes / streaming partials | plugins/conversation_nodes_test.dart (+ session/tool_stream_test in full run) | 20 ✓ |
| Tools / subcalls | plugins/ws_chat/tool_plugin_test.dart | 5 ✓ |
| Subagents | plugins/ws_agent/subagent_plugin_test.dart | 12 ✓ |
| Tasks | ws_tasks/{deliverables,workflow_run,jobs}_plugin_test.dart | 5+5+5 ✓ |
| Input / commands / approvals (63+25 target) | ws_input suite: input_trigger 13, popup_and_composer 13, approval_plane 15, commands_reference_questions 7, input_keyboard_producer 6 | 54 ✓ |
| Shortcuts (new, B) | ws_input/input_trigger_shortcuts_test.dart | 9 ✓ |
| Workspace | features/sidebar/workspace_gaps_test.dart | 20 ✓ |
| Surfaces | ws_surfaces/{plugins,render} | 7+3 ✓ |
| Attachments / drag-drop | platform/drag_drop_test.dart, widgets/attachment_rail_test.dart | 26+9 ✓ |
| Directory picker | directory_picker/{browser,gaps,replay} | 18+7+5 ✓ |
| Settings | features/settings/settings_screen_test.dart, settings_general/language_row_test.dart | 6+8 ✓ |
| Session creation / restoration | session/host_session_policy_test.dart, unit/sessions_controller_test.dart, api/connection_client_rpc_test.dart | 4+25+6 ✓ |

All green; counts consistent with the full-suite total (754).

## 9. Tracker gates

- `pnpm run verify-flutter-tracker --check` → **OK (112 items)**
- `pnpm run verify-flutter-tracker --strict` → **OK (112 items, strict)**

Ledger: **Verified 29 · Integrated 79 · Migrated 3 · Audited 1 = 112**

Non-Integrated rows (unchanged, honest):
- Migrated: `component.ui-primitives.BrandWordmark` (faithful port, no composed consumer yet),
  `component.ui-primitives.OnboardingSurface`, `component.ui-primitives.Pill`.
- Audited: `platform.keyboard-shortcuts` (B's composer binding advances behavior; row status left
  as-is per instructions).

## 10. Remaining blockers before manual-QA phase

Nothing that would make the next phase "hidden implementation":

1. **Model-turn leg live QA needs a keyed host.** Everything through command/plan/history/title/
   dispatch verified live; final assistant-render-on-live-host requires DEEPSEEK_API_KEY loaded by
   the server process (environmental).
2. **Three Migrated primitives lack composed consumers** (BrandWordmark, Pill, OnboardingSurface).
   They are tested ports, honestly labeled; composing them is future work, not hidden logic.
3. **Golden coverage gaps for new-wave visuals** (approval card, trajectory JSON trees, tooltip
   rail hover) — follow-up goldens should be authored deliberately, not generated blind.
4. Cosmetic residue: `test/goldens/failures/`, `_repro_fold_test.dart`, 123 analyzer lints.
