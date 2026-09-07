# Locale Propagation Completion Pass

**Date:** 2026-08-28 · **Agent:** L2 (retry) · **Authority:** `packages/client/locale` (React locale runtime) · **Mechanism:** existing `LocaleService` + `localeRevisionProvider`/`bindLocale` consume pattern only — no new localization mechanism.

## Summary

The plumbing was already done (LanguageRow publishes through the shared `LocaleService`; `MaterialApp.locale` + `supportedLocales` bound in `app_plugins.dart`; `localeRevisionProvider` lives in `core/services/runtime_services.dart`). The gap: most widgets rendered literal strings instead of consuming the registered dictionaries. This pass wired every owned surface onto the shared registry via one helper, extended the dictionaries to full key parity with the React files, and proved live flipping end-to-end.

## Shared helper design

Added to `apps/flutter/lib/src/core/services/runtime_services.dart` (the core locale file, no new framework):

- **`typedef Translate = String Function(String key)`** — the bound translate face.
- **`bindLocale(ns)` extensions on `Ref` and `WidgetRef`** — the single sanctioned consume call: watches `localeRevisionProvider` (rebuild on every locale/registry publish), then returns the stable `LocaleService.bind(ns)` function. Widgets: `final t = ref.bindLocale(kWorkspaceNamespace);` inside `build`.
- **Seeded namespaces** — the service constructor now registers `common` (cross-feature vocabulary, verbatim from `packages/client/locale/src/locales/{zh,en}.ts`) and `settings.locale` (Language row copy, verbatim from `.../locales/settings.ts`), mirroring React where the same package that ships the service registers both (`client/index.ts`: `locale.register(COMMON_NS, …)`, `locale.register(SETTINGS_NS, …)`).
- **Bind fallback chain extended to match React**: entry namespace (active locale → any registered locale carrying the key) → shared `common` vocabulary → key itself. Previously the chain skipped common; existing fallback-to-key tests still pass because their probe keys are absent from common too.

## Audit table — fixed

Every row consumed via `ref.bindLocale(...)` + revision watch; dictionaries registered by the owning plugin's `apply` with `onDispose`.

| Surface (file) | Strings wired | Namespace | React citation |
|---|---|---|---|
| `plugins/workspace/ui/workspace_picker_chip.dart` | 工作区 / loading / add / folder-error title | `workspace` | `ui-workspace/src/client/locales.ts` |
| `features/sidebar/sidebar.dart` | section headers, view-options menu, New session, search placeholder/clear/pending/unavailable/hasMore, footer count, Settings link, rail tooltips, workspace/session rename+delete dialogs and menus, blank/running/idle subtitles, relative-time row labels, hover created stamps, empty states | `workspace` (+`settings` trigger, `common` cancel/delete/more) | `ui-workspace/src/client/locales.ts` (full key set ported); `group.today…older`, `session.blank`, empty hints are Flutter-surface additions |
| `plugins/workspace/locales.dart` | dict grown to full React key parity + cited Flutter-surface keys; added `{name}`/`{n}`/time-bucket format helpers | `workspace` | as above |
| `plugins/agent_preset/ui/agent_preset_screen.dart` | title/nav, refresh, loading/error/retry/close, settings-row title/description, seat hint, all-presets header, group headers, trust badges, in-use/default/broken badges, set-default/duplicate/delete actions + unavailable variants, copy dialog (title/ID/name/create), delete dialog (title/description/confirm) | `settings.agentPreset` | `ui-agent-preset/src/client/locales.ts`; `refresh`, `allPresets`, `defaultBadge`, `deleteUnavailable` are Flutter-surface additions |
| `plugins/agent_preset/ui/agent_preset_label.dart`, `agent_preset_hero_seat.dart` | preset display name via locale-live `presetDisplayText(t:)`; header hint; seat tooltip | `settings.agentPreset` | as above |
| `plugins/agent_preset/locales.dart` | dict completed to the full React key set (`view`, `presetId`, `displayName`, groups, copy/delete dialogs, …) | `settings.agentPreset` | as above |
| `plugins/model_selection/ui/model_seat.dart` | trigger fallback, menu aria, effort menu/provider default/no-efforts, failure-row load-failed (via `common.load.failed`), error toast fallback | `model` → `common` | `ui-model-selection/src/client/locales.ts` |
| `plugins/permission_presets/ui/permission_seat.dart` | risk-confirmation dialog (title/description/acknowledge/cancel/enable), gate tooltip, Custom label, switch-failed snackbar | `permission.access` (+`common`) | `ui-permission-presets/src/client/locales.ts`; `accessMode`, `custom`, `switchFailed` Flutter-surface |
| `plugins/plan/ui/plan_screen.dart` | screen title, off state title/hint, enter button | `plan` | chip keys verbatim from `ui-plan/locales.ts`; screen keys Flutter-surface |
| `plugins/skill/ui/skill_screen.dart` | nav, refresh, search hint, loading/loadFailed, empty states, retry (common) | `skill` (+`common`) | row keys verbatim from `ui-skill/locales.ts`; screen keys Flutter-surface |
| `plugins/goal/ui/goal_bar.dart`, `goal_screen.dart` | phase label, pause/resume/edit/clear tooltips, empty state | `goal` | action/phase keys verbatim from `ui-goal/locales.ts`; `phase.complete`, empty keys Flutter-surface |
| `plugins/deliverables/ui/deliverables_screen.dart` | app-bar title, empty title/hint | `deliverables` | produced keys verbatim from `ui-deliverables/locales.ts`; empty keys Flutter-surface |
| `plugins/jobs/ui/jobs_screen.dart` | app bar/header list label, count line, running/idle badge, status badges, empty state | `job` (+`common`) | status/count/list keys verbatim from `ui-jobs/locales.ts` (English statuses render lowercase per React source of truth); header/badge/empty keys Flutter-surface |
| `plugins/workflow_run/ui/workflow_screen.dart` | nav, empty title/hint | `workflowRun` | run-panel keys already verbatim; screen keys Flutter-surface |
| `plugins/user_questions/*` (NEW `locales.dart`, plugin registration, `approval_card.dart`, `question_node_card.dart`) | approval header/reject/allow-once; question card cancel/submit via common | `question` (+`common`) | full key set verbatim from `ui-user-questions/locales.ts`; approval.* Flutter-surface |
| `features/settings/settings_screen.dart` | app title, four tab labels, General section + description, notifications row, workspace directory row, about section/tagline, Enter-behavior row (title/description/queue/steer/loading/select) | `settings`, `models`, `plugins`, `inventory`, `conversation`, `common` | tab/nav/title keys per each `ui-settings-*` locales; enter-behavior keys verbatim from `ui-conversation/locales.ts` (`settings.enter.*`); section/row copy Flutter-surface |
| `features/settings_general/widgets/language_row.dart` | row title, select placeholder | `settings.locale` (seeded) → `common` | `packages/client/locale/src/locales/settings.ts` |
| `features/settings_general/widgets/appearance_row.dart` | Appearance title + Light/Dark/System cubes | `settings` | values verbatim from `ui-theme/src/client/locales.ts` (`appearance.*`); Dart hosts them in the `settings` ns because the ui-theme analog sits in bootstrap (see handoff note below) |
| `features/settings_models/settings_models_screen.dart` | whole section copy (`_t` is now a live bind against the models ns, replacing the hardcoded English map) | `models` | subset of `ui-settings-models/src/client/locales.ts` |
| `plugins/settings/children/{general,models,plugins,plugin_inventory}` | dicts extended with nav/tab/section/row keys consumed by the shell | same ns each owns | React-cited; inventory `nav` Flutter-surface |

Also fixed en route (compile blockers adjacent to the pass, noted for the record): missing `slot_registry` import in `plan_plugin.dart`, missing session-model imports in the concurrent agent's new `agent_preset_hero_seat.dart`. No tracker promotions; `verify-flutter-tracker --check` OK (112 items).

## Handoff items — NOT MINE (found hardcoded, left untouched)

These sit in surfaces another agent owns concurrently. Suggested ns:key included so the next pass can land them mechanically.

| Location | String | Suggested wiring |
|---|---|---|
| `plugins/conversation/ui/chat_view.dart:290` | `'执行中…' : 'Running…'` via `Localizations.localeOf` in build | `t('status.running')` on a conversation-side key (React `stats.toolCall` family or a dedicated `turn.running`); must drop the `localeOf` capture and use bindLocale |
| `plugins/input_trigger/ui/input_menu_anchor.dart`, `composer_trigger_binding.dart` | composer attach/menu chrome labels | input-trigger-owned ns (React `ui-input-trigger/src/client/locales.ts` exists, unported) |
| `widgets/primitives/block.dart:111,152` | `复制成功/复制`, `收起/… 其余 N 行` | `common.copy/copied/collapse` + a block-owned expand key; primitives take `Translate` params or convert to ConsumerWidget |
| `widgets/primitives/terminal_block.dart:54-105` | `运行中/失败/完成/复制/已复制/无输出/收起/展开 N 行/信号 N/退出码 N` defaults | constructor defaults should come from `common` + a terminal ns at call sites |
| `widgets/primitives/codeblock.dart:20-21`, `read_block.dart`, `search_block.dart`, `diff_block.dart` | `复制/复制成功` default params | `common.copy/copied` |
| `widgets/layout/app_frame.dart` (details/right-track chrome) | any future panel chrome | frame-owned ns when the details track lands |
| `routing/app_router.dart` | route titles, if any surface adds them | follow each destination's owning ns |
| Sidebar snackbars (diagnostics): `'Failed to create session: $e'`, `'Failed to create workspace: $e'`, `'Directory picker unavailable'`, `'Workspace "$path" created'`, `'Rename/Fork/Archive failed'`, `'Delete — pending host wire'`, rename-pending notice, agent-preset toasts (`Created preset "…"`, `Failed to …`), plan exit-failure prefix, skill `'Inspect — stub'` | error/toast diagnostics | policy call needed: either a `common.error` template family or an explicit decision that wire-diagnostic interpolations stay untranslated (React passes runtime failure strings through untranslated by policy — see ui-workspace locales header). Listed rather than silently translated. |
| `_SearchResultsView` matches line `'Showing matches for "…" · N results'` | composed diagnostic-style line | candidate key `search.matchesLine` if product wants it localized |
| `utils/workspace_labels.dart` `workspaceLabel()` `'Ungrouped'` fallback | pure-function fallback used before dictionaries exist | keep as en fallback (documented) or thread Translate |

## Tests

New — `apps/flutter/test/integration/locale_flip_test.dart` (real `DshApp` → `buildAppHost` → `activateAll`, stub carrier, business_host pattern):

1. **Dictionary completeness** — zh/en key sets identical across all 19 touched namespaces.
2. **Fallback chain** — unknown key everywhere → key itself; entry-ns miss but common hit → `取消`/`Cancel` following a real `setLocale`.
3. **Live flip** — pumps hero + sidebar (wide surface) + `/settings`; asserts initial Chinese copy (工作区 chip, 新建会话, 语言 row, 通用 tab, 繁忙时 Enter 键行为); flips via `container.read(localeServiceProvider).setLocale('en')` — the exact publish path `LanguageRow.setLocale` drives — and asserts Language/General/Enter-behavior switched immediately; navigates home and asserts Workspaces/New session switched; flips back to zh and asserts byte-identical restore on both routes.

Updated harnesses (production registers these namespaces in plugin `apply`; direct-pump tests now mirror that registration):

- `test/features/settings/settings_screen_test.dart` — registers the four settings-child + conversation namespaces, pins en; expectations updated to React-cited copy ('Enter behavior while busy', 'Queue').
- `test/plugins/ws_agent/agent_preset_plugin_test.dart` — `_app`/`_sectionApp` register `settings.agentPreset` + pin en; `presetDisplayText` takes `t:`; badge/dialog expectations follow the renamed copy.
- `test/plugins/ws_surfaces/ws_surfaces_render_test.dart` — registers `model` + `workspace` namespaces.
- `test/plugins/ws_tasks/deliverables_plugin_test.dart` — registers `deliverables` for the standalone screen pump.
- `test/features/settings_general/language_row_test.dart` — title/placeholder expectations follow the seeded `settings.locale` + `common` dictionaries in the default zh locale.

## Results / gates

- `flutter analyze lib test` — **0 errors**.
- `flutter test test/integration/locale_flip_test.dart` — **3/3 pass** (completeness, fallback, live flip both directions).
- Suites green after the change: `test/features/**` (incl. language_row, settings, sidebar, locale binding/bootstrap), `test/plugins/ws_agent`, `test/plugins/ws_surfaces`, `test/plugins/ws_tasks`, `test/plugins/ws_input`, `test/conversation`, `test/integration` (incl. business_host co-activation), `test/replay`, `test/services`, `test/session`.
- `pnpm run verify-flutter-tracker --check` — **OK (112 items)**; no promotions; no parityCheck corrections required.
- Not run here: `pnpm run doc-sync` (no docs/ sources touched) and device-level visual capture (no GUI behavior change beyond copy source; screenshot diff would be identical per locale).

## Design notes for reviewers

- **Why the sidebar has no own namespace in Dart:** React splits sidebar chrome (`sidebar` ns, ui-sidebar plugin) from browsing-region copy (`workspace` ns, ui-workspace plugin). The Dart SidebarPlugin sits in `core/bootstrap/app_plugins.dart`, which this workstream may not edit, and Riverpod forbids registering (revision republish) while a provider initializes, so feature-side registration hacks were rejected. Instead the two sidebar-only keys (`session.new.label`, `toggle.open/collapse`) joined the `workspace` dictionary owned by the production registrar; the split is documented in `plugins/workspace/locales.dart`.
- **Appearance keys under `settings`:** same reasoning — ui-theme's `settings.theme` ns has no Dart registrar inside authority, so `appearance.*` rides the General section's `settings` ns (comment in `general_settings_plugin.dart`).
- **LocaleService seeds `common` + `settings.locale` in its constructor**, matching React's package-owned registrations; `setLocale` validation therefore always knows zh/en, matching React's registered-id check semantics.
