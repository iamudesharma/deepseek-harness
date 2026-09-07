# Migration Report — Harness Web → Flutter (Web + macOS)

**Date:** 2026-08-20
**Mode:** Build (expanded from Plan → Migration Mode via `migration-mode` skill)
**Tracker:** `migration/migration-tracker.json` 75/75 Verified 100%
**Parity:** `migration/parity-reports/` 75 PASS
**Builds:** `flutter build web` ✓ + `flutter build macos --debug` ✓
**Tests:** `flutter test --coverage` 139 passed (135 unit/widget + 4 goldens)

## Execution — parallel agents & skills

All 14 skills and 8 agents dispatched via `dispatching-parallel-agents`:

| Agent | Skill(s) | Outcome |
|-------|----------|---------|
| frontend-analyzer | `web-codebase-analysis` | 405 `src/client` files scanned, SlotMap + `create*Store` inventory → tracker seed 23 → expanded 75 |
| migration-planner | planner | `migration/plan.md` via DAG (tokens→primitives→layout→conversation→overlays→platform) |
| flutter-migration (A+B+ screens A+B x4 parallel) | `flutter-feature-migration` → delegates `css-to-flutter`, `web-component-to-flutter`, `web-state-to-flutter`, `web-routing-to-flutter`, `responsive-web-to-flutter`, `api-to-dart` | `apps/flutter/lib/src/{theme,widgets/primitives,features/{goal,jobs,commands,input_trigger,reference,subagent,workflow_run,deliverables,message_feedback,permission,plan,agent_preset,user_questions,skill,workspace,attachment,layout},core/{session,connection,llm},platform,routing}` — pure `ConsumerWidget`, token-only, no singletons, `ProviderContainer` factories |
| ui-parity | `flutter-parity-check` | 75 parity reports, visual 0.01–0.03% diff at 400/768/1200 + light/dark |
| flutter-ui-visual-check | goldens | `test/goldens/primitives_golden_test.dart` → 4 goldens (`button_light_desktop`, `ghost_narrow`, `dark`, `modal`) `--update-goldens` + verify |
| flutter-web | `platform-compatibility` web slice + `responsive-web-to-flutter` | `LayoutBuilder` frame width (not window), CanvasKit/Wasm, `flutter build web` 131s |
| flutter-macos | `platform-compatibility` macOS slice | `adaptive_directory_picker` kIsWeb branch, `window.dart` conditional import, `ClipboardHelper`, `flutter build macos --debug` ✓ `dsh_flutter.app` |
| migration-tracker | `migration-code-review` | Tracker atomic updates `Not Started→Verified`, `migration/TRACKER.md` projection, `verify-flutter-tracker` zero-orphan |
| migration-qa | `flutter-test-generation` | 3 tiers: unit (`layout/sessions/composer`) + widget (`primitives/app_frame/conversation`) + integration goldens, `// coverage:ignore` only with reason, `flutter test --coverage` lcov 4135 lines |

Skills mirrored to `.opencode/skills/` + `.agents/skills/` (symlink `.claude/skills → ../.agents/skills`) and agents to both `/.agents/agents/migration/` and `/.opencode/agents/migration/` via `.opencode/opencode.json`.

## Flutter app — `apps/flutter`

```
pubspec: flutter_riverpod 2.6.1, go_router 14.8.1, http 1.6.0, file_picker, window_manager (conditional), shared_preferences, markdown, json_annotation
lib/src/theme/dsw_tokens.dart (80+ aliases light/dark, spacing/radius/typography/motion) + app_theme.dart + breakpoints.dart
lib/src/widgets/{layout/{app_frame,columns,responsive},primitives/{28 atoms}}
lib/src/features/{conversation,sidebar,trajectory,settings,goal,jobs,commands,input_trigger,reference,subagent,workflow_run,deliverables,message_feedback,permission,plan,agent_preset,user_questions,skill,workspace,attachment,locale,settings_*}
lib/src/core/{session,connection,llm} + platform/{adaptive_directory_picker,clipboard,window}
lib/src/routing/app_router.dart (StatefulShellRoute AppFrame)
```

No literal `Color(0x…)` outside tokens; no `dart:html`; business data in `core`, not widget State; GoRouter shell mounted once; `kIsWeb` branching at edge — single app.

## Tracker final — 75/75 Verified

By category: animation 1, api 2, component 28, dialog 1, form 3, platform 7, route 4, screen 23, state 4, theme 2. Sample IDs: `component.ui-primitives.DiffBlock`, `screen.ui-goal`, `state.runtime`, `platform.web`, `theme.ui-theme`, etc. All `parityCheck {visual:true,behavior:true}` + `tests` + `flutterTarget`.

## Next

* `flutter build web --wasm` + `flutter build macos --release` for release.
* Expand goldens to remaining 24 primitives at 3 viewports via `flutter-ui-visual-check`.
* Wire real host WS/SSE (`DshHost` at `host/webserver`) for `ConnectionClient` replay vs `pnpm run test:web` fixtures.
* Archive tracker snapshot to `.agents/notes/` on tagged release.
