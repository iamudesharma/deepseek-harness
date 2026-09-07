# 2026-08-24 — Workspace / Sidebar Completion (Agent C)

This report documents the parity closure for the workspace/sidebar workstream against the React contracts in `packages/client/ui-workspace`, `packages/client/ui-sidebar`, `packages/client/ui-primitives`, `packages/client/runtime`, and `packages/client/ui-model-selection`.

One line per paragraph per workspace/sidebar instruction; visual evidence is outside the tracker.

## Traced React Contracts

`WorkspaceBrowser.tsx` defines the browsing region (section header with `WorkspaceBrowser.module.css`, search with `SANITIZE`/`DEBOUNCE 250ms`/`MAX_CODE_UNITS 500`, grouped tree vs flat list, `deriveGroups`/`deriveFlat`/`deriveSearchResults` with local `title`/`workspace` substring plus ranked `session.search` snippet overlay, `hasMore` at `SESSION_SEARCH_RESULT_LIMIT 20`, `pending`/`unavailable` states, `insertWorkspaceBefore`/`insertSessionBefore` host durability, `createWorkspace` via directory flow, `ViewOptionsMenu` `groupBy`/`orderBy`, `SidebarRoot.tsx` 150ms crossfade with `lastWideWidth` freeze and 2000ms scrollbar linger).

`Rows.tsx` defines `ProjectRowItem` with `HoverCard` (500ms dwell, 8px gap, grace-close, copy), `abbreviateHomePath` POSIX-only `~` rewrite with Windows/UNC/root guard, `createdLabel` via dictionary `date.ymd` + `hover.created`, and `SessionNodeItem` with `sessionStatuses` precedence `approval → plan-review → question → subagents → running → completed → idle`, `StateDot` `warning`/`ongoing`/`done` with halo, and `SearchResultItem` snippet.

`stores.ts` declares `createWorkspaceViewStore` with `persist: 'dsh.workspace.view.v5'` over `groupBy`/`orderBy`/`groupExpansion`/`sessionOrderByAccount`/`sessionUpdatedAtByAccount`.

`ModelSelect.tsx` is a two-pane `MenuDropdown` (root `Model`/`Effort` rows drilling to provider-grouped model list plus dynamic effort list, load/error/retry, selection via `session.selectModel`, rejection toast anchored to `[data-composer-card]`).

`Toast.tsx` is a body-portal transient banner (`HOLD_MS 3000` + `FADE_MS 1000`, slide -6 easeOut) optionally anchor-centered to the composer card.

`settings-store.ts` derives the selectable `defaultPreset` enum from the host schema union at `['defaultPreset']` via `SettingsSchemaService.nodeAtPath` + `rehydrate`, not a hard-coded stub.

Directory-flow holes are declared as `single` `root` slots `conversation.hero.workspace.directoryFlow` and `sidebar.workspaces.directoryFlow` with occupant-owned picking interaction.

## Flutter Implementation

`apps/flutter/lib/src/utils/abbreviate_home_path.dart` ports `runtime/workspaces/path.ts:abbreviateHomePath` verbatim (POSIX `~`, Windows/UNC/root guards, `home` optional).

`apps/flutter/lib/src/utils/workspace_labels.dart` ports `Rows.tsx:createdLabel`/`hoverTimeLabel`/`relativeTime`/`workspaceLabel` with `createdLabel` using wall time `Created YYYY/M/D HH:MM` without browser locale, and `relativeTime` buckets `now`/`minutes`/`hours`/`days`/`months`/`years`.

`apps/flutter/lib/src/core/session/session_models.dart` extends `SessionSummary` with `pendingInteraction`/`completed`/`runningSubagentCount`, parses them from host JSON (`pendingInteraction` closed union, `completed` bool, `runningSubagentCount` int), adds `sessionStatuses()` implementing the exact precedence plus `SessionStatus` (`state`/`label`), and extends `WorkspaceView` with `createdAt`/`updatedAtMillis` parsing ISO-8601 and aliasing `path`/`title`.

`apps/flutter/lib/src/features/sidebar/sidebar.dart` now wraps workspace headers in `DsHoverCard` with `WorkspaceHoverContent` (`title`, abbreviated `cwd`, `createdLabel`, copy `cwd`) and session rows in `DsHoverCard` with `SessionHoverContent` (`title`, `hoverTimeLabel`, all `sessionStatuses` with dots), disables hover while `menuOpen` or `drag.active`, uses `timeLabel` from `workspace_labels.dart`, filters `blank` sessions except current (sessionVisible parity), derives groups via `deriveWorkspaceGroups` with `sessionIds` membership plus `cwd` fallback, `sessionOrderByAccount` reconciliation, `orderBy` activity promotion, `collapsedSessionLimit 5` overflow, and `ReorderableListView` for workspace order (`workspace.insertBefore`) and per-workspace session order (`workspace.insertSessionBefore`) when `orderBy != updated` and not `Ungrouped`, with local `workspaceSessionOrderProvider` plus host durability and `debugPrint` on rejection; search uses `search_derive.dart:deriveSearchResults` (local newest-first plus ranked host `session.search` overlay, dedup, `limit 20`, snippet, `hasMore`).

`apps/flutter/lib/src/features/sidebar/search_derive.dart` ports `tree.ts:deriveSearchResults` including `workspaceBySession` label, `sessionVisible` (`subagent`/`blank`/`archived` filtering), `byRecency` tie-break, `ordered` dedup, `limit` slice, `hasMore` (`content.hasMore || ordered.length > limit`), and `snippet` overlay.

`apps/flutter/lib/src/core/connection/connection_client.dart` adds `workspaceInsertBefore`, `workspaceInsertSessionBefore`, `workspaceRename`, `workspaceDelete`, and `sessionSearch` (`session.search` `SESSION_SEARCH_RESULT_LIMIT 20`) over `callMethod`/`_postTypert` with `RpcResponse` unwrapping via `parseRpcMessage`.

`apps/flutter/lib/src/features/sidebar/workspace_view_store.dart` provides `WorkspaceViewSnapshot` (`groupBy`/`orderBy`/`groupExpansion`/`sessionOrderByAccount`/`sessionUpdatedAtByAccount`) with `toJson`/`fromJson` and `SharedPreferences` persistence under `dsh.workspace.view.v5`, hydrated into the four `StateProvider`s plus `workspaceSessionUpdatedAtProvider` and auto-saved on each change via `workspaceViewPersistenceProvider` (watched in `Sidebar` and `_ExpandedSidebar`).

`apps/flutter/lib/src/widgets/layout/app_frame.dart` already freezes `lastWideWidth` while `!_settled` during 150ms collapse, clips via `AnimatedContainer` width `cols.sidebar` with inner `SizedBox` width `sidebarCollapsed && !_settled ? _lastWideWidth : cols.sidebar`, crossfades wide content via `AnimatedOpacity` `opacity 0` over `_collapseSettle 150ms` (reduced-motion drops to zero), and reuses `DswTokens.transitionDurationSlow` for slide; `Sidebar` (`_SidebarState`) adds `everWide` rail-in transform, `settled` flag, and pointer `linger` 2000ms that hides `scrollbarTheme` thumb/track via `Theme` override while `!_pointerInside`.

`apps/flutter/lib/src/plugins/model_selection/ui/model_seat.dart` now surfaces selection rejection through `toastProvider` (`showError` with `state.error` anchored to the composer card via `DsToastHost` top 120 plus anchor rect when available), preserving the two adjacent `PopupMenuButton`s for model and effort (provider-grouped, `defaultEffort`, failure rows disabled, `select` via `ModelDirectory.select`) as a Flutter-ergonomic split of the React root drill; full `MenuAnchor`/`SubmenuButton` two-pane drill is deferred but the trigger shows combined `model · effort` label and both menus share the same `directory.load`/`select` busy gating and error copy (`t('error.action')`).

`apps/flutter/lib/src/widgets/primitives/toast.dart` holds at full opacity `HOLD_MS 3000` then fades `FADE_MS 1000` via `AnimatedOpacity`, slides `-6` easeOut `160ms` (dropped under `prefersReducedMotion`), and `DsToastHost` can be wrapped around a `GlobalKey` anchor (`[data-composer-card]` analog) to center horizontally over the composer card instead of viewport when supplied.

`apps/flutter/lib/src/core/settings/settings_scope.dart` now stores the host `schema` per namespace from `settings.describe` (`section['schema']`) into `SettingsScopeSnapshot.schema`.

`apps/flutter/lib/src/plugins/permission_presets/permission_presets_service.dart` derives `options` from `permissionOptionsOf(snapshot)` which rehydrates the `defaultPreset` union (`type: 'union'` `list` of `const` nodes with `meta.description`) exactly as `settings-store.ts:permissionDefaultOf` does, validating `currentValue` is advertised and returning empty when unavailable.

`apps/flutter/lib/src/plugins/directory_picker/directory_picker_plugin.dart` and `apps/flutter/lib/src/plugins/workspace/workspace_plugin.dart` declare the two `single` `root` holes (`conversation.hero.workspace.directoryFlow` with `WorkspacePickerChip` occupant, `sidebar.workspaces.directoryFlow` with `BrowseDirectoryFlow`/`NativeDirectoryFlow` occupants) via `slots.register` `children` and occupy them through `slots.inject` wait-and-follow (browse on web, native on desktop, priority-separated single-slot enforcement), so a composition without a picking affordance shows no add button and an open flow withdraws when its occupant unloads.

## Tests

`apps/flutter/test/features/sidebar/workspace_gaps_test.dart` (20 cases, all passing) covers `abbreviateHomePath` POSIX/Windows/root, `relativeTime` buckets, `createdLabel`/`workspaceLabel`, `sessionStatuses` precedence for all seven states, `deriveWorkspaceGroups` workspace order/membership and blank filtering, `deriveSearchResults` local recency / snippet overlay / dedup / hasMore / archive filtering, and `sanitizeSearchQuery` NUL + 500 cap with surrogate safety.

`apps/flutter/test/plugins/directory_picker/directory_browser_test.dart` (18 cases) and `directory_picker_gaps_test.dart` (6 cases) cover Miller columns, two-pane away-from-display-root, breadcrumb, draft debounce, slow-scan pill, parent-leg wait, hidden filtering, new-folder flow, `visibleEntries` helpers, slot hole contract, `aria-current` Semantics selected, IME `_isComposing` guard (`composing.isValid`), `DirectoryListSignal` abort, and locale dictionaries as before.

`apps/flutter/test/widgets/app_frame_test.dart` and `apps/flutter/test/goldens/surface_goldens_test.dart` verify `AppFrame` expanded at 1200×800 (sidebar visible, drag handle), collapsed, and goldens for light/dark fixtures.

`apps/flutter/test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart` and `ws_surfaces_render_test.dart` verify the eleven WS-Surfaces plugins activate, hero wait-and-follow, model seat trigger/catalog, workspace list/create wire, directory-picker seam, and attachment staging as before.

## Platform Verification

`flutter analyze --no-pub` reports 0 errors (warnings only) on both Web and macOS.

`flutter test test/features/sidebar/workspace_gaps_test.dart test/plugins/directory_picker/directory_browser_test.dart test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart test/widgets/app_frame_test.dart` passes.

Responsive `LayoutBuilder` viewport (`sidebarCollapse` 768) drives the same AppFrame column geometry on Web and macOS via `buildLightTheme`/`buildDarkTheme`; `window_manager` `minimumSize` plus `SharedPreferences` `dsh.workspace.view.v5` works on both.

## Tracker Update

`runtime.workspace-store` → `Integrated` (host `sessionIds`/`archivedSessionIds` membership, `workspace.list` create adoption, host-order grouping, durable view `SharedPreferences` `dsh.workspace.view.v5` with `groupBy`/`orderBy`/`groupExpansion`/`sessionOrderByAccount`/`sessionUpdatedAtByAccount`).

`screen.sidebar` → `Integrated` (wide/rail chrome with 150ms freeze/fade, 2000ms linger, HoverCard, status precedence, search ranked `deriveSearchResults` with `pending`/`unavailable`/`hasMore` at 20, durable `insertWorkspaceBefore`/`insertSessionBefore`).

`screen.ui-workspace` → `Integrated` (sidebar-grouped tree + view options `workspace`/`flat` + `manual`/`updated` + 250ms debounced sanitized search + add-workspace via `directoryFlow` holes + host `session.search` fan-out + folderError retry).

`form.model-select`/`platform.ui-model-selection` remain `Verified` with documented split-button two-pane approximation and toast anchor to composer card; `dialog.hoverCard` remains `Audited` with `DsHoverCard` now used in workspace/sidebar but not yet promoted pending gatekeeper.

## Remaining Gaps

Single-trigger `MenuAnchor`/`SubmenuButton` two-pane drill with back via `Escape` and in-menu `loading`/`error`/`warning` strips remains a visual polish (current two adjacent menus are behavior-complete and share the same `modelDirectories` store); `DsToastHost` anchor currently centers over viewport when no `GlobalKey` is supplied and could be wired to the composer card's `RenderBox` center for pixel-perfect anchor; `permission` settings row UI in `settings.general` still defers the `settings.general.item` hole.

## Evidence

`flutter analyze --no-pub` — 0 errors.

`flutter test test/features/sidebar/workspace_gaps_test.dart` — 20 passed.

`flutter test test/plugins/directory_picker/directory_browser_test.dart` — 18 passed.

`flutter test test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart` — 7 passed.

`flutter test test/widgets/app_frame_test.dart test/goldens/surface_goldens_test.dart` — 13 passed.

Parity report: `migration/parity-reports/2026-08-24-workspace-completion.md`.

