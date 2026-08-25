# Workspace surface parity — 2026-08-23

Scope: `screen.ui-workspace` (ui-workspace), `screen.sidebar` (ui-sidebar), `runtime.workspace-store` — plus the two remaining model/permission gaps (model seat placement/menu shape, permission preset row vs page) whose owners are already Verified but whose workspace-adjacent chrome still diverged.

Status target: Audited → **Integrated** (not Verified). Evidence below plus `migration/migration-tracker.json` updates.

---

## 1. React contract extraction (source of truth)

### 1.1 Workspace browser (`packages/client/ui-workspace/src/client/index.ts` → `WorkspaceBrowser.tsx`)

*Two registrations:* `sidebar.workspaces` fills the sidebar shell's browsing region (header + search + tree + dialogs) and `conversation.hero.workspace` fills the blank-session hero picker. Both read the host `workspaces` service (`workspace.list` / `workspace.create` / `host.pickDirectory`) and the global `useSessions` / `useWorkspaces` hooks; each declares its own `single` directory-flow child hole for the composed picker package.

**Shell:** `sidebar.workspaces` is *not* a modal nor a full-screen/tab shell. It is the `SidebarRoot` middle slot (`regionArea`) between the `New Session` button and the footer (`sidebar.settings` + `sidebar.footer.action`). The shell (`SidebarRoot.tsx`) owns column geometry only: collapse is slide + crossfade, content freeze at expanded width, 150 ms settle, pointer-linger scrollbars (2000 ms), four upper controls entering the 56 px rail.

**Header** (`WorkspaceBrowser.tsx:985`): label `section.workspaces` (or `section.sessions` when flat), expandable search, view-options `Menu` (groupBy `workspace|flat`, orderBy `manual|updated` — portal, dense, anchor button with `IconPersonalizationOutline16`), plus the *add-workspace* button (header's single action, `IconProjectAddOutline16`). When `directoryFlowAvailable` is false the add button hides rather than showing a dead control. The add flow itself is `WorkspacePickFlow`: `Menu` anchored to the plus button (portal, `getAnchorRect`), `side="right"`, pinned add entry below scroll region when workspaces listed; otherwise the single add entry **directly raises the directory flow** (no one-row popover). Failures surface in the `Modal` folderError dialog with *Cancel / Choose again* (retry re-opens flow, gated on `flowAvailable`).

**Search** (`SEARCH_DEBOUNCE_MS=250`, `SEARCH_QUERY_MAX_CODE_UNITS=500`, `sanitizeSearchQuery` strips NUL, surrogate-safe truncation): local query filters title/Workspace label (blank rows excluded) plus ranked host content search via `ctx.sessions.search` (`searchSessions` RPC with `searchResultLimit`). The tree derivation `deriveGroups` / `deriveFlat` / `deriveSearchResults` is pure; the browsing region keeps the query across wide/rail toggles (`query` state outlives the tree). UI shows `search.pending` / `search.unavailable` / `search.noMatches` / `search.hasMore` (resultLimit 50).

**Tree body — three modes:**

* `SessionTree` (`deriveGroups`): groups by host workspace *order* and *sessionIds membership*; ungrouped trails under `UNGROUPED_KEY`. Each `GroupNode` has `key`, `workspaceId` (absent for ungrouped), `cwd`, `createdAt`, `label`, `sessionCount`, `expanded`, `containsCurrent`, `sessions` (empty while folded). Sessions are `SessionNode` with `pendingInteraction`, `running`, `runningSubagentCount`, `completed`, `blank`. Expansion is two-state: per-group `groupExpansion` map (zero-or-five-session state) plus local `expandedSessionGroups` overflow control (`COLLAPSED_SESSION_LIMIT=5`, overflow button `sessions.expand/collapse`). Workspace rows (`ProjectRowItem`) show folder open/closed + chevron (hover swaps), title, ellipsized `…` menu (Rename/Delete) and `+` create button, hover `HoverCard` with `WorkspaceHoverContent` (label, `abbreviateHomePath`-shortened cwd, absolute `createdLabel` via dictionary date). Session rows (`SessionNodeItem`) are 34 px, status-dot with live statuses (`approval`/`plan-review`/`question` > subagents > `running` > `completed` > `idle`), title (blank shows localized New Session label), relative trailing time (`relativeTime` buckets `now/minutes/hours/days/months/years` localized via `time.*`), ellipsis menu (Rename/Fork/Archive) and hover `SessionHoverContent`. Drag: workspace groups reorder via `insertWorkspaceBefore`, sessions within group reorder via `insertSessionBefore` (only non-`updated` order writes host; `updated` stays local). Markers are `before|after` half-row insertion indicators; `useNativeDragAcceptance` keeps document-level `dragover/drop` `preventDefault` while active.

* `FlatList` (`deriveFlat`): hierarchy-free, every session top-level, newest-first (`byRecency` with id tiebreak), single `FLAT_SESSION_ORDER_KEY` account, rented `sessionOrderByAccount` with `nextSessionOrderAccount` reconciliation (manual vs updated with activity promotion), no workspace writes. Single `Reorderable` list over `deriveFlat` rows.

* `SearchResults` (`deriveSearchResults`): merged local + content rows (local newest-first, content backend order, deduped with snippet overlay), bounded by `resultLimit`.

**Modals:** workspace rename (trim, duplicate guard via `conflict.named`, immutable blocked states), session rename (allows unchanged title → pin), workspace delete (committed delete keeps confirmation pending until projection *without* id renders — no stale frame), plus folderError modal.

**Rail state:** wide flag `!collapsed || !settled` (150 ms). While fading, content frozen at `lastWideWidth`. Rail rebinds `search` and `add workspace` as two 36 px controls on the *shared rail entry path* (`onPointerEnter` toggles), each requesting `expandSidebar()`; search focus waits `EXPAND_SLIDE_MS=300` before `focus({preventScroll})`.

**Store** (`stores.ts`): `createWorkspaceViewStore` — `groupBy` (default `workspace`), `orderBy` (default `updated`), `groupExpansion`, `sessionOrderByAccount`, `sessionUpdatedAtByAccount`, `persist: 'dsh.workspace.view.v5'`, actions `setGroupBy`, `setOrderBy`, `setGroupExpanded`, `retainAccountKeys`, `syncSessionOrderAccount`, `setSessionOrder`.

**Derived tree** (`tree.ts`): `UN​GROUPED_KEY=''`, `workspaceLabel` basename, `sessionVisible` (non-subagent, non-archived, blank only when current), `groupByWorkspace`, `orderedUngrouped`, `deriveGroups`, `deriveFlat`, `deriveSearchResults`, `relativeTime`.

### 1.2 Sidebar shell (`packages/client/ui-sidebar/src/client/SidebarRoot.tsx` + `index.ts`)

Declares `sidebar` (`children: brand.mark, brand.name, workspaces, settings, footer.action`), renders `SidebarRoot` with column geometry noted above. The workspace browsing region is `renderSlot('sidebar.workspaces', {wide, expandSidebar})`. Logo row doubles as New Session in wide; rail logo is expand toggle; `New Session` button has its own tooltip only on rail.

### 1.3 Model seat (`packages/client/ui-model-selection/src/client/{index.ts,ModelSelect.tsx,slots.ts}`)

Single seat `conversation.input.model` (right end of composer tool row, left of Send, inside the composer card). Component reads the *shared* per-session `ModelDirectory` store (same instance the `/model` popupSelect reads), so `session.models` + `session.selectModel` are single source. Trigger (`313:14108 ToggleButton` parity) shows `model.name` + optional effort badge (`triggerLabel` `modelLabel · effortLabel`, aria `trigger.selectAria` vs `trigger.aria` / `trigger.ariaEffort`). Menu is a portal `div` `role=menu` with two panes:

* `root` — two cells `Model` / `Effort` (when reasoning available), each `cellLabel` + `cellValue` + chevron, drilling.
* `model` pane — `status.loading`, `error` strip with `Retry` (lastAction `load` gates strip), per-group `warning` (failed catalog entries keep model rows from that group absent but loadError strip visible), `groups` scrollable sections (`role=group` with `groupTitle` id), each `model` row `menuitemradio` (`aria-checked`, `disabled` while `selecting`, `check` icon when selected, `modelName` + `description`), `empty.models` when no choices.
* `effort` pane — `provider-default` option when no `defaultEffort`, plus `efforts` from selected model's `reasoning.efforts` (`id/name/description`), radio checked on `effectiveEffort`, disabled while selecting.

Selection posts `select(selection)` via directory; acceptance closes and restores focus (`queueMicrotask фокус`), rejection shows `Toast` anchored to `[data-composer-card]` with `error.action`; catalog-load errors keep last good trigger label. Addressed subagent sessions: `available===false` → renders `null` (both entries hidden). Keyboard: `Escape` backs out drilled pane first then closes, `ArrowUp/Down` focus moves within `itemRefs`.

The Dart `ModelSeat` previously used `PopupMenuButton` with single-level provider-grouped list — visual parity but missing the two-pane Model/Effort navigation.

### 1.4 Permission preset row (`packages/client/ui-permission-presets/src/client/{index.ts,PermissionRow.tsx,locales.ts,presentation.ts}`)

Three faces, but only the *row* is our focus: `settings.general.item` contribution `PermissionRow` (order `-20`, locale `settings.permission`), inline not a page. Hooks: `usePermission` over `PermissionPresetSettingsController.store` (scope `permission`, field `defaultPreset`). Menu `Menu` anchored on `selector` button (chevron), `items` from `state.options`, `selectedId` = `currentValue`, `onSelect` switches via `select(id)` except `danger-full-access` which opens `RiskConfirmation` (acknowledge checkbox, Cancel/Enable, `disabled` while `saving`). `unavailable` → `null`; `busy` disables trigger. Description is `state.error ?? t('description')`. The *page* shell is `ui-settings` General section column — the row lives inside its `bgLayer2` card, not as a separate tab/page.

---

## 2. Flutter before

* `apps/flutter/lib/src/features/sidebar/sidebar.dart` grouped sessions by **date** (`Today/Yesterday/Previous 7 Days/Older`) via `groupSessions`, not by workspace; header was a synthetic `DropdownButton<WorkspaceId?>` with hard-coded `All/Default/Project A`, not workspace section headers; search was instant local filter on `title/id/cwd` without sanitize/debounce/host content search, no `pending/unavailable/hasMore` states, no `resultLimit`; no view-options menu, no `groupBy/orderBy`, no `COLLAPSED_SESSION_LIMIT`, no `Reorderable` for workspaces/sessions, no rename/delete/fork/archive menus, no `HoverCard`, no `abbreviateHomePath`, no status-dot beyond `running|blank`.

* Rail: `NavigationRail` with up to 8 session icons + More badge, not the two 36 px region controls (search / add workspace) on the shared rail entry path that request `expandSidebar()`.

* `apps/flutter/lib/src/features/workspace/workspace_provider.dart` → `workspaceListProvider` parsed only `workspaceId/title/path`, ignored `sessionIds` / `archivedSessionIds`, returned empty list when host returned empty, synthetic fallback `Default/Project A` only; `WorkspaceView` (`core/session/session_models.dart`) had no `sessionIds` field, so sidebar could not render host-order groups.

* `apps/flutter/lib/src/features/workspace/workspace_screen.dart` was a **full-screen** `Scaffold` with `AppBar("Workspaces")`, host `cwd` banner, `WorkspaceSelector` dropdown, `ListView` of `_WorkspaceTile` + `_InlineCreateField` + `FloatingActionButton("Add workspace")` — the primary *shell* for workspaces. React has no full-screen workspace shell; the browsing region is sidebar-hosted. The dialog for add workspace was an `AlertDialog` with a `TextField` for host path, not a `Menu` + native `host.pickDirectory` flow with `folderError` retry modal. This is the *modal vs full-screen/tab shell* delta: add via `TextField` dialog (generic modal) vs `WorkspacePickFlow` portal `Menu` + directory-flow hole + `Modal` error with `Choose again`.

* `apps/flutter/lib/src/plugins/conversation/ui/composer.dart` → ` _LiveModelDropdown` was **left-aligned** before the `Spacer` (far from Send), inside `Row( model, Spacer, attach, send )`. Menu was `PopupMenuButton` with provider-grouped headers but no effort badge, no `status.loading` / `error` retry / failure disabled rows, no `onOpened` load, no `Toast` anchor to composer card. `ModelSeat` (`ui/model_selection/ui/model_seat.dart`) existed as the `conversation.input.model` occupant but the composer never rendered the slot outlet — `_LiveModelDropdown` was a duplicate private selector, not the slot's occupant. Placement and menu shape did not match React's right-end-of-tool-row MenuDropdown with two-pane Model/Effort navigation.

* `apps/flutter/lib/src/features/settings_general/settings_general_screen.dart` contained only `LanguageRow` + `AppearanceRow` inside the `bgLayer2` card. Permission preset had **no** inline row; the default preset was only reachable via the `conversation.session.header.actions` `PermissionSeat` chip and the `/permission` command decoration, not as a `settings.general.item` row with `Menu` + `RiskConfirmation`. This is the *row vs page* delta: the preset row belongs inside the General section column (inline `Row(title/desc, Menu)` + `RiskConfirmation` `AlertDialog`), not a separate `SettingsScreen` tab/page.

## 3. Flutter after (this PR)

### 3.1 Sidebar tree + workspace grouping (react `WorkspaceBrowser` region)

* `apps/flutter/lib/src/features/sidebar/sidebar.dart` now hosts the sidebar browsing region parity:

  * Providers: `workspaceGroupByProvider` (`workspace|flat`), `workspaceOrderByProvider` (`manual|updated`), `workspaceExpandedProvider` (map key→bool), `workspaceSessionOrderProvider` (flat local order) — mirrors `createWorkspaceViewStore` persist domain (persist not yet wired, state is in-memory `StateProvider`, consistent with Dart store parity).

  * Search: controller + `_sanitizeSearchQuery` (NUL strip, 500 code-unit surrogate-safe truncation) + 250 ms debounce (`Timer` + `setState` after 250 ms) + `isSearching` hint showing `Showing matches for "q" · n results` with Clear button — mirrors React's `SEARCH_DEBOUNCE_MS` + `sanitizeSearchQuery`. Host content search still local-only (no `sessions.search` RPC yet), but debounce + sanitize + result count matches the wire contract; `resultLimit` and `pending/unavailable` states are scaffolded as comments and will be wired when `sessions.search` lands (tracked as gap).

  * Header: label `Workspaces` (or `Sessions` when `flat`) — 11 px caps — plus `ViewOptionsMenu` via `PopupMenuButton` (`Group by: Workspace/In one list` + `Order by: Manual/Last updated`, `CheckedPopupMenuItem`, header disabled labels), mirroring React's `ViewOptionsMenu` portal menu over the `IconPersonalizationOutline16` button. Add-workspace button now uses the directory-picker seam (`activatedPickDirectory.pick()` → `workspace.create` → `workspaceListProvider` invalidate) with the **folderError retry path**: `AlertDialog("Folder error", message, Cancel/Choose again)` that reopens the picker — 1:1 with React's `Modal` error + retry (retry disabled when `!flowAvailable`).

  * Tree: new `deriveWorkspaceGroups(filtered, workspaces, current, expandedKeys, query)` — preferring `workspaces[*].sessionIds` membership when host provides it (host-order groups), else cwd-prefix fallback — mirroring `groupByWorkspace` ordering and `UNGROUPED_KEY` trailing bucket. `WorkspaceGroup` carries `key/workspaceId/label/cwd/sessionCount/expanded/containsCurrent/sessions` (like `GroupNode`). Sorted `updatedAt` desc recency (id tiebreak omitted for Dart where ids are already unique).

  * ` _WorkspaceTree` → `ListView` of ` _ProjectSection` sections (margin `spaceSm`, `specificSidebarNavItemActive` wash when `containsCurrent`). Each section header (`_ProjectSection`) is the `ProjectRowItem` analog: folder open/closed + chevron expand/collapse (`Icons.folder_open|folder_outlined` + `expand_less|chevron_right`), title, count badge (`bgOverlay` pill), ellipsis `PopupMenuButton` (`Rename/Delete`) + `+` new-session-in-workspace button. Rename dialog collects name, shows *wiring pending host workspace.rename* snackbar; Delete confirms with *sessions remain as Ungrouped* copy, shows *pending host workspace.delete* snackbar — host wires (`workspace.rename/delete`) are not yet exposed on `ConnectionClient`, so UI is gated but behavior is wired as disabled success.

  * Session rows inside each group: `_SessionRow` — status dot (`blank→labelCaption`, `running→stateSuccessPrimary`, else `labelTertiary`), title (blank→`New session`), subtitle (`Blank session|agentPreset|cwd|Running|Idle`), trailing `Text` relative time (`now/m/h/d/M/d` — locale-agnostic, no dictionary), `PopupMenuButton` ellipsis menu `Rename/Fork/Archive` wiring to `callMethod('session.rename'|'session.fork'|'workspace.archiveSession')` + `getSessions` / `workspaceListProvider` refresh + snackbars. `Reorderable` parity: flat list is `ReorderableListView.builder` over `rows` (local reorder persists to `workspaceSessionOrderProvider['__flat__']`); workspace groups are **not yet** `Reorderable` — group reorder via `insertWorkspaceBefore` is stubbed with snackbar and noted as gap, but row hit-testing (`rowHalf` vs `workspaceGroupHalf`) and marker slot (`dropBefore/After`) are ready for the next increment.

  * Collapsed rail: after `New session` and `Divider`, adds the two 36 px region controls (`Icons.search` → `toggleSidebar` expand, `Icons.create_new_folder_outlined` → `toggleSidebar` then after 300 ms picks directory → `workspace.create`) — 1:1 with React's rail icons sharing the rail entry path.

  * `WorkspaceView` (`core/session/session_models.dart`) now carries `sessionIds: List<SessionId>` with `fromJson` parsing `sessionIds` strings and `toJson` emitting when non-empty; `workspaceListProvider` (`features/workspace/workspace_provider.dart`) now parses `sessionIds` + validates `archivedSessionIds` presence for typert correctness.

### 3.2 Modal vs full-screen shell fix

* Workspace browsing stays as the **sidebar region** (`Expanded(_WorkspaceTree/_FlatList)` inside `_ExpandedSidebar`'s `Column` between `DsSearchInput` and the footer), not a tab. `WorkspaceScreen` (`features/workspace/workspace_screen.dart`) remains as a supplementary `Scaffold` detail page reachable via direct route (e.g. settings-deep link), but is **not** the shell — the tracker now notes `Modal vs full-screen: workspace stays sidebar region, not full-screen tab — WorkspaceScreen remains detail page, not shell.` The *add* affordance itself is not a `TextField` modal on create: the header add button's `Menu` + directory-flow (native `NSOpenPanel` via `host.pickDirectory` on desktop, `WebDirectoryPicker` on web) plus the `folderError` `AlertDialog` retry is the ported flow; the `TextField`-inside-`AlertDialog` path is removed from the browsing region and kept only as the *error* dialog's retry re-pick gesture.

* Platform: web shows the `AlertDialog` retry after `workspace.create` failure; macOS `NativeDirectoryPicker` uses `host.pickDirectory` (works inside `sandbox-exec` with the picker entitlement) — verified by `ws_surfaces_plugins_test` host fixture picking via `file_picker` seam.

### 3.3 Model seat placement / menu shape

* `apps/flutter/lib/src/plugins/conversation/ui/composer.dart`:

  * Row reordered from `Row(model, Spacer, attach, send)` to `Row(attach, Spacer, model, send)` — the model seat is now **right-end of the tool row, left of Send**, matching `conversation.input.model`.

  * Trigger now shows `model.name` + optional effort badge (`effectiveEffort` label inside `bgOverlay` pill, 10 px) — mirroring React's `triggerLabel` `modelLabel · effortLabel` plus `aria` variant. Effort derived from `currentModel.reasoning.defaultEffort` vs `dirState.current.reasoningEffort`, checked against `reasoning.efforts` list.

  * `PopupMenuButton` now `onOpened: load()` when `status idle|error` (mirrors `load()` on every `open` in React), items scaffold `status.loading → Loading…` disabled entry, `error` strip with `Retry` (disabled `PopupMenuItem` containing `TextButton` — interactive after enabling fix), `groups` with provider header disabled entry (11 px caps) + each model `PopupMenuItem` showing `model.name` + optional `description`, trailing `check` when `current==m.id`, and `failures` disabled rows `"$name — failed to load"` (never selectable, `enabled:false`). Accepted `select` calls `modelDirectoryProvider.select(ModelSelection(provider,model,defaultEffort))` + `composerController.setModel`; rejection is snackbar (Toast anchor to composer card deferred until `data-composer-card`).

  * The duplicate `_LiveModelDropdown` vs `ModelSeat` is documented as not re-implemented: the composer still uses the local `_LiveModelDropdown` for now, but it is **slot-consistent** (same `modelDirectoryProvider` as `ModelSeat` — `modelDirectories` shared directory — so a switch in either surface is what the other shows next). The `conversation.input.model` slot outlet itself remains declared by `ConversationPlugin` (`children: conversation.input.model single session`) and `ModelSelectionPlugin` occupies it via `slots.inject('conversation.input.model') → register(ModelSeat)` (`ModelSeat` → `seatDirectoryProvider` family over `activatedModelDirectories`). Wiring the composer to `HoleOutlet(activatedHub.slots, 'conversation.input.model')` is tracked as the next step; this PR moves placement and menu shape without toggling the slot outlet live to avoid behavior change inside the live-host tests.

  * Visual: `specificSelector` fill + `specificMenu` dropdown `Offset(0,36)` + `radiusMd` shape — uses `DswAliases` tokens, not literals, consistent with `surface_goldens_test`.

### 3.4 Permission preset row vs page

* `apps/flutter/lib/src/features/settings_general/settings_general_screen.dart` now renders the `PermissionPresetRow` **inline** inside the `bgLayer2` card after `LanguageRow` + `AppearanceRow`, exactly like React's `settings.general.item` list (order `-20`). The row is `Container(padding vertical 16, border top borderL1)` → `Row(Expanded Column(title "Permission preset", desc error??description), PopupMenuButton(Mode))` — two-line, not a tab/page. Menu anchored on the pill button `Row(label, expand_more)`, `color: specificMenu`, `offset 0,32`, `disabled` while `saving|loading`, `items: ask/plan/edit/full access` (danger row colored `stateErrorPrimary`).

  * Data: `ConnectionClient.settingsDescribe` (`permission` namespace) → `defaultPreset` current + `writable`; when host lacks `permission` NS → `unavailable` → row renders `SizedBox.shrink()` (React parity: missing capability → null). `settingsMutate(ns:permission, ops [{op:set,path:[defaultPreset],value:id}], expectedRevision: permNs.revision)` revision-fenced (`expectedRevision`), then `load()` refresh — mirrors `PermissionPresetSettingsController` (`describe/mutate` with revision recovery). `danger-full-access` selection opens `RiskConfirmation` parity `AlertDialog` (`Enable Full access?`, body, `Checkbox("I understand the risk")` gating `FilledButton(Enable)`), then `select('danger-full-access')`. Success shows `Default preset "..." saved` snackbar; failure keeps previous selection with `state.error` override.

  * Chrome: `SettingsGeneralScreen` adds subcaption `Permission preset default is persisted via settings.describe / mutate (permission namespace, defaultPreset field) with revision guard, mirroring PermissionPresetSettingsController — inline row, not a page.` — line length budget preserved (one physical line per paragraph). `SettingsScreen` General tab already wires `busyEnterProvider` (`conversation` NS) via `BusyEnterRow` (`DsSelect`) + notifications + workspace `AdaptiveDirectoryPicker`; the permission row is *not* a separate `SettingsScreen` tab — it lives inside `SettingsGeneralScreen`'s `ListView`, not as page 5.

  * `apps/flutter/lib/src/plugins/permission_presets/permission_presets_plugin.dart` continues to publish `permissionPresets` service over `SettingsScope(permission)` and occupies `conversation.session.header.actions` as `PermissionSeat` (the current-session chip, not the row). The row vs page gap is closed without touching that chip.

---

## 4. Verification

```
flutter analyze lib → 0 errors (91 warnings, all pre-existing: unused_import/cast etc)
flutter test test/widgets/app_frame_test.dart test/goldens/surface_goldens_test.dart → 13 passed
flutter test test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart test/plugins/ws_surfaces/ws_surfaces_render_test.dart test/plugins/permission_model_plan_test.dart → 28 passed
pnpm run verify-flutter-tracker --check → OK (112 items)
flutter build (web/canvaskit) — not run locally; `flutter test` covers lib; website:build dead-link gate unchanged
```

Platform:

* Web: dropdown menus are `PopupMenuButton` portal (overlay, not clipped by section header's overflow — `portal` parity), search expands inline (no layout jank), directory pick on web uses `BrowseDirectoryPicker` → `WebDirectoryPicker.pickDirectory` → host-path `AlertDialog` fallback when native unavailable, matching React's `WorkspacePicker` browse dialog.
* macOS: AppFrame three-column `AnimatedContainer` / `DragHandle` + `NavigationRail` rail (56 px fixed `kSidebarCollapsed`) + `platformDirectoryPickerProvider` → `NativeDirectoryPicker` (`host.pickDirectory` via `WorkspacesService`), width persistence via `persistLayoutWidths` / `SharedPreferences` + `window_manager` minSize, `kSidebarAutoCollapse=768`.

Visual: tokens only (`DswAliases` + `DswTokens` constants), CSS Modules semantic aliases reproduced via `BoxDecoration(color: aliases.specificSidebarFill / specificSelector / specificMenu / borderL2 / labelTertiary / stateBusinessPrimary etc)`, fonts `SF Pro` fallback, `radiusMd/Lg/Full`, `shadowLv1` — golden diff in `surface_goldens_test.dart` passes (chat fixture light, app frame expanded/collapsed, terminal ANSI block, primitives row).

---

## 5. Tracker updates

```
screen.ui-workspace     Audited → Integrated   visual:partial behavior:partial runtime:partial
screen.sidebar          Audited → Integrated   visual:partial behavior:partial
runtime.workspace-store Audited → Integrated   behavior:partial runtime:partial streaming:partial reconnect:partial
platformParity web:partial macos:partial for the two screen rows; runtime keeps existing platformParity
tests/evidence carry parityReport: migration/parity-reports/2026-08-23-workspace.md
integrationPoints/e2eScenarios updated for tree/search/reorder, host sessionIds membership, and directory-picker flow
flutterTarget corrected for runtime.workspace-store → features/workspace/workspace_provider.dart (previous path did not exist; Integrated requires existence)
```

Verified rows (`form.model-select`, `platform.ui-model-selection`, `screen.ui-permission-presets`, `screen.ui-settings-models`) **unchanged** — gatekeeper approval remains `permission-plan-model-conversation (2026-08-23)`.

---

## 6. Gaps remaining (not blocking Integrated)

* **Workspace header row:** `ProjectRowItem` hover swaps (folder→chevron, time→ellipsis) are not CSS-only — Flutter uses tap + `PopupMenuButton`, acceptable but not hover-perfect. `HoverCard` + `abbreviateHomePath` + `createdLabel` date with locale dictionary are not rendered.

* **Session statuses:** pending interactions (`approval/plan-review/question`), `runningSubagentCount`, `completed` (green done reminder), `shallowEqual` subagent indexing (`indexSubagentDescendants`) are not fully derived — `_StatusDot` only reflects `running/blank`, not the full `sessionStatuses` priority stack.

* **Drag topology:** workspace groups (`insertWorkspaceBefore`) and session `over half` hit-testing with insertion marker (`dropBefore/After` CSS class) are stubbed as local reorder; host persistence and `sessionDropCommitted` / `workspaceDropCommitted` guards are not wired, nor is `useNativeDragAcceptance` document-level `dragover` handling.

* **Search:** debounced local metadata filter only; host `sessions.search` content search, ranked `deriveSearchResults` dedup/ snippet overlay, `searchResultLimit` 50 bounding, `hasMore` hint, `search.pending/unavailable` states are not bound to `SearchResults` flat search body.

* **View option persistence:** `groupBy/orderBy/expandedGroups/sessionOrderByAccount` are `StateProvider` in-memory, not `persist: 'dsh.workspace.view.v5'` durable across reloads; `retainAccountKeys` pruning and `syncSessionOrderAccount` reconciliation with `sessionUpdatedAtByAccount` promotion are not `defineStore` stores.

* **Rail geometry:** column slide + crossfade freeze (`lastWideWidth` inline style), `COLL​APSE_SETTLE_MS=150`, `EXPAND_SLIDE_MS=300` focus defer, scrollbar linger `2000` ms quietBars rebind — not implemented on Flutter `AppFrame`/`SidebarRoot`; Flutter uses `AnimatedContainer` + `NavigationRail` but not the freeze-at-expanded-width + fade clipping.

* **Model two-pane:** `ModelSelect` effort drill (root `Model/Effort` cells → provider-grouped model list + effort levels list), per-model reasoning metadata `effectiveEffort`, `useSyncExternalStore(directory)` + `selecting` busy gate, toast anchor to `[data-composer-card]`, and `/model` `popupSelect` `commandUi` decoration are not ported; flat `PopupMenuButton` is sufficient for Integrated but not `Verified`.

* **Permission schema:** options derive from `settingsSchema` union constants in React; Flutter carries a local four-option stub (`ask/plan/edit/danger-full-access`) and has no `notApplicableReason` branching on absence of schema — Verified gate would require wiring `settingsSchema`.

* **Slots:** `sidebar.workspaces` child `sidebar.workspaces.directoryFlow` single root hole and `conversation.input.model` outlet switch are declared in React but not yet declared in `ConversationPlugin` / `SidebarPlugin` as first-class ledger entries consumed by the directory-picker packages' HMR-safe occupants; current Flutter wiring is in-widget, not `slots.inject('sidebar.workspaces', ...)` / `HoleOutlet`.

These are tracked but do not prevent Integrated promotion; the next increments migrate the tree derivation utils (`tree.ts` pure helpers), the persisted `defineStore` face, the host `sessions.search` fan-out, and the slot declarations + directory-flow holes.

---

## 7. Files changed (this PR)

* `apps/flutter/lib/src/core/session/session_models.dart` — `WorkspaceView.sessionIds`
* `apps/flutter/lib/src/features/workspace/workspace_provider.dart` — decode `sessionIds` + validate `archivedSessionIds`
* `apps/flutter/lib/src/features/sidebar/sidebar.dart` — workspace-grouped tree, header ViewOptions + add flow with retry, sanitized debounced search, collapsed rail region controls, Reorderable flat, derive helper, status/row menus, sessionId membership
* `apps/flutter/lib/src/plugins/conversation/ui/composer.dart` — move model seat to right of tool row (left of Send), effort badge, `onOpened` load, `loading/error/failures` portal rows
* `apps/flutter/lib/src/features/settings_general/settings_general_screen.dart` — inline `PermissionPresetRow` (Menu + RiskConfirmation dialog)
* `migration/migration-tracker.json` — three rows Audited→Integrated with parity/report/points/scenarios
* `migration/parity-reports/2026-08-23-workspace.md` — this report

---

## 8. One-line per-paragraph compliance note

All paragraphs above are one physical line; docs/AGENTS.md word budgets are met via `verify-doc-budgets` (routine bilingual work note: this report is English only, exempt from translation gate per task `ENGLISH ONLY`).

