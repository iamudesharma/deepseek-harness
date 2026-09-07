# Shallow Integrated evidence consolidation — 2026-08-24

Scope: the 15 Integrated rows whose `evidence{testsRun,parityReport}` were empty after earlier waves. This report consolidates their existing on-disk test commands and parity sources; no new implementation is claimed here, no row is promoted to Verified, and no evidence is invented — every path below was verified to exist before being recorded in `migration/migration-tracker.json`.

## Rows covered

`screen.ui-commands`, `screen.ui-deliverables`, `screen.ui-goal`, `screen.ui-input-trigger`, `screen.ui-jobs`, `screen.ui-reference`, `screen.ui-settings-general`, `screen.ui-settings-plugin-inventory`, `screen.ui-settings-plugins`, `screen.ui-user-questions`, `screen.ui-workflow-run`, `component.brand-official`, `reference.composer-integration`, `input-trigger.suggestion-engine`, `platform.open-external`.

## Per-row verification performed (2026-08-24)

- Test files listed in each row's `tests[]` exist on disk (`ws_input/commands_reference_questions_test.dart`, `ws_input/popup_and_composer_test.dart`, `ws_input/input_trigger_test.dart`, `ws_tasks/{deliverables,goal,jobs,workflow_run}_plugin_test.dart` + shared `host_fixture.dart`, `ws_surfaces/ws_surfaces_plugins_test.dart`, `ws_surfaces/ws_surfaces_render_test.dart`, `integration/business_host_test.dart`, `platform/open_external_test.dart`, `replay/semantic_parity_test.dart`, React `packages/client/runtime/tests/semantic-parity.client.spec.ts`, goldens `test/goldens/surface_goldens_test.dart`).
- `business_host_test.dart` boots the real composed app (`buildAppHost` + `PluginHost.activateAll` over all five workstreams) and passes — it is the integration evidence for every plugin-backed row above.
- Replay-backed rows (`screen.ui-input-trigger`, `screen.ui-user-questions`, `input-trigger.suggestion-engine`) point at the committed byte-identical replay baseline: `pnpm vitest run semantic-parity` (React) vs `flutter test test/replay/semantic_parity_test.dart` (Flutter), diff fixture `migration/parity-reports/react-parity-projection-v1.txt` (40 wire frames).
- Visual rows (`component.brand-official`, `screen.ui-settings-general`) carry golden coverage through `surface_goldens_test.dart` (7/7 at last run) plus the P2.2 visual audit `migration/parity-reports/2026-08-22-visual-parity-p2-2.md`.
- `platform.open-external` carries its focused seam test `apps/flutter/test/platform/open_external_test.dart` (sanitizeUrl allowlist http/https/mailto + deny others).

## Commands executed for this evidence pass

```
flutter analyze lib                                  → 0 errors
flutter test test/plugins/ws_input test/plugins/ws_tasks test/plugins/ws_surfaces
flutter test test/integration/business_host_test.dart
flutter test test/platform/open_external_test.dart
flutter test test/replay/semantic_parity_test.dart   → 2/2
pnpm vitest run semantic-parity                      → 2/2 (React side)
pnpm run verify-flutter-tracker --check              → OK (112 items)
```

## Tracker deltas applied by this pass

For each of the 15 rows: `evidence.testsRun` set to the exact command above covering that row, `evidence.parityReport` set to this file, `evidence.replayDiff` set to `react-parity-projection-v1.txt` only where a replay baseline actually covers the row, and `tests[]` reduced to real existing file paths (the descriptive `(real DshApp boot…)` suffix was removed from entries; `business_host_test.dart` remains listed as the plain path). `integrationPoints` unchanged. No `status` change, no `approvedBy`/`reviewer` change.

## Remaining honesty notes

These rows stay Integrated: several still lack dedicated per-screen widget/golden coverage beyond their plugin tests (commands popup rendering, deliverables/goal/jobs/workflow-run chat-node visuals, settings children render), and Verified promotion will require the Gatekeeper to accept this consolidated evidence or demand deeper per-row artifacts.
