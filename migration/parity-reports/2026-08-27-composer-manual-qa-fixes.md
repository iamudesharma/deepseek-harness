# Composer manual-QA fix pass — 2026-08-27

Continuation of an interrupted manual-QA bug-fix pass on the Flutter conversation composer. React source under `packages/client/*` stayed authority; no redesign, no new framework. Gatekeeper was not run.

## BUG1 — model selection

Root cause: the composer's live dropdown was the only model surface reachable in the composed UI, but its menu opened downward from a chip at the viewport bottom and landed off-screen (unclickable rows), and nothing pinned the select/effort payload contract against `session.selectModel`.
Fix: strict group-only resolution with no synthesized rows (`apps/flutter/lib/src/plugins/conversation/ui/composer.dart:723`), pick sends `{provider, model, reasoningEffort: target.reasoning?.defaultEffort}` (`composer.dart:1028`), provider-default row clears a stale effort when `defaultEffort == null` (`composer.dart:1052`), effort picks preserve provider/model (`composer.dart:1066`), Effort row only while the exact current model advertises reasoning (`composer.dart:995`), menu flips upward near the viewport bottom (`composer.dart:791`), drill titles collapse instead of overflowing (`composer.dart:887`). `kAvailableModels` has no remaining consumer anywhere reachable (`features/conversation/composer_controller.dart:374`, zero references).
Tests: `test/integration/composer_contract_test.dart` — default-effort payload, effort-preserve payload, non-reasoning hides the Effort row, empty catalog renders "No models available" and never calls `selectModel`.

## BUG2 — trigger keyboard + pipeline

Root cause: three gaps — (a) externally seeded field text was clobbered by empty Riverpod state on first frame so seeded drafts never detected; (b) caret/selection-only notifications skipped detection, so the menu didn't follow the token under the caret; (c) the IME-composition guard read a build-time snapshot that went stale before the key arrived.
Fix: mount-time adoption between field and state, deferred post-frame and reconciled against live state so neither side clobbers the other (`composer.dart:103-130`, sync re-read at `composer.dart:328`); every field notification feeds detection, with transaction pushes still gated on real text edits inside `track()` (`input_trigger/ui/composer_trigger_binding.dart:99-107`); composition is read from the live field at key-event time (`input_trigger/ui/input_keyboard_producer.dart:77-98`) over the unchanged arbitration contract — ↑/↓ move highlight, Escape closes without cancelling, Enter picks-when-open else falls through to submit (`input_trigger/input_trigger_controller.dart:160-181`). Shift+Enter inserts a newline through an explicit intent, porting InputBar.tsx's textarea branch (`composer.dart:399`, action at `composer.dart:417`). Trigger outlets stay mounted at `conversation.input.left/right` (`composer.dart:520,522`) and `conversation.input.overlay` (`composer.dart:564`).
Tests: full `test/plugins/ws_input` suite green (73 tests) including arrow-highlight pick, Enter-with-no-menu submits, Escape dismisses without cancel, Shift+Enter newline, IME guard, chip-delete splice.

## BUG3 — hit-test independence

Root cause: floating menus painted above the composer card through negative-offset translation, but taps outside an ancestor box never reach Flutter children — slash-menu and popupSelect rows were unclickable (taps fell through to the Scaffold); the model dropdown had the same failure downward.
Fix: both overlay seats now render their open content through root-overlay portals positioned off a measurable anchor box, each with its own outside-tap dismiss barrier — trigger menu (`input_trigger/ui/input_menu_anchor.dart:39-118`) and popupSelect shell (`commands/ui/popup_select_overlay.dart:56-130`); WorkspacePickerChip already rode OverlayPortal (`workspace/ui/workspace_picker_chip.dart:106`). Each control opens only its own surface: PermissionSeat submits `/permission <value>` behind the RiskConfirmation checkbox for danger-full-access (`permission_presets/ui/permission_seat.dart:67-90`), plan exit rides its own docked chip. No tap-stealing ancestors remain over shared controls (the app-frame drag strip handles horizontal drags only).
Also fixed en route: hole contributions must carry the registry's two-argument builder shape or the outlet asserts — corrected the one-arg registrants (`conversation/ui/slots/hole_outlet.dart:64`, `input_trigger_plugin.dart:67`, `subagent_plugin.dart:79`, `agent_preset_plugin.dart`, `jobs_plugin.dart`).

## BUG4 — blank-session layout

State found complete from the interrupted pass; verified rather than rebuilt. Blank sessions render the hero phase of the one plugin shell — fish headline slot, workspace picker seat, resident composer — never a parallel tree (`conversation/ui/column.dart:43-60`, `conversation_screen.dart:116-141` decommissioned hand-rolled variants). Geometry comments cite the mirrored InputBar.module.css values (root padding 16/0/16/8, card max width 780, radius 22, `.overlayAnchor` strip at the card top edge) at `composer.dart:385-394`.

## BUG6 — composed-shell contract tests

Added `test/integration/composer_contract_test.dart`: mounts the REAL host via `buildAppHost` + `activateAll` under one provider container with a captured client, then asserts per control — model dropdown payload (default/preserve/clear/no-synthesis), `/permission danger-full-access` command payload gated by the risk dialog (Enable dead until acknowledged), plan-chip `/plan off` execution, `/` trigger menu open + pick executing detached through `session.prompt`, attachment rail intake, and submit carrying draft text plus base64 image parts with queue mode. 8/8 green.

## Gates

- `flutter analyze lib` → 0 errors.
- Green: `test/plugins/ws_input` (73), `test/plugins/conversation_integration_test.dart`, `test/widgets/conversation_test.dart`, `test/unit/composer_controller_test.dart`, `test/integration` (13 pre-existing incl. business-host five-workstream activation + 8 new contract tests) — 158 total.
- Goldens: `test/goldens/surface_goldens_test.dart` passed unchanged; no regeneration because the golden surfaces (app frame, terminal ANSI block, primitives row) contain none of the touched composer/menu geometry.
- `pnpm run verify-flutter-tracker --check` OK (112 items); `--strict` OK.

## Live-host transcript

Scripted envelope POSTs to `http://127.0.0.1:8787/api/<method>` (origin `http://127.0.0.1:8321`); full step log at `evidence/2026-08-27-live-model-select-transcript.json`. Session `session-5a0ae92f-f3bc-4331-8e3b-770bbb573421`: catalog exposes 4 providers (deepseek-official, opencode-go, opencode, local); selecting deepseek-official/deepseek-v4-flash echoes the advertised default `reasoningEffort: high`; switching to opencode/gpt-5.1 echoes no stale effort; back-to-A restores; explicit `low` persists across a fresh `session.models` pull; local/deepseek-v4-flash (non-reasoning) clears the effort persistently; unavailable provider/model is rejected `model-unavailable` (no synthesis), and a null-model payload is rejected `bad-request` (strict wire validation).

## Tracker honesty

`screen.conversation` and `route.conversation.chat.node` demoted Verified → Integrated: the composer surface changed after their Verified review (portal remounts, directional model menu, explicit Shift+Enter, seed adoption, HoleRenderer signature fix), behavior re-covered by the contract test while visual parity awaits gatekeeper pixel re-review. Nothing was promoted. `platform.ui-model-selection` stays Verified (its target widget is untouched) with a note recording that the interactive composer dropdown is `_LiveModelDropdown` over the same directory service, plus the new evidence paths. `--check`/`--strict` remain green after the edit.
