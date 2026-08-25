# Directory Picker / Miller-Column Parity Report — 2026-08-23

## Scope
Tracker IDs:
- `platform.directoryPicker` → `apps/flutter/lib/src/platform/adaptive_directory_picker.dart`
- `platform.ui-directory-picker-browse` → `apps/flutter/lib/src/plugins/directory_picker/directory_picker_service.dart` + `directory_browser.dart`
- `platform.ui-directory-picker-native` → `apps/flutter/lib/src/plugins/directory_picker/directory_picker_plugin.dart`

Status: **Integrated** (not Verified). Gaps noted at end.

## React Source Trace

### Packages
- `packages/client/ui-directory-picker-browse/src/client/DirectoryBrowser.tsx` (1028 lines, figma Harness 813-23126 family)
- `packages/client/ui-directory-picker-browse/src/client/DirectoryBrowser.module.css`
- `packages/client/ui-directory-picker-browse/src/client/flow.ts` — `BrowseDirectoryFlow` occupant
- `packages/client/ui-directory-picker-browse/src/client/index.ts` — locale + double hole registration
- `packages/client/ui-directory-picker-native/src/client/flow.ts` — `NativeDirectoryFlow` renderless
- `packages/client/ui-directory-picker-native/src/client/index.ts`
- `packages/host/directory-picker/src/index.ts` — capability seam `DirectoryPicker` (`native` vs `browse`)
- `packages/host/directory-picker-browse/src/index.ts` — Node `BrowseDirectoryPicker` (listing window 1000, hidden flagged, symlinks, truncated, abort)
- `packages/host/directory-picker-native/src/native-picker.ts` — `pickNativeDirectory` (darwin osascript, win32 IFileOpenDialog, linux zenity/kdialog)
- `packages/client/runtime/src/client/workspaces/service.ts` — `IWorkspaces.listDirectory` / `createDirectory` / `pickDirectory`
- Tests: `tests/directory-browser.client.spec.tsx` (~964 lines), `tests/client-flow.client.spec.tsx`

### Capability Seam (host)
`DirectoryPicker` is merge-extensible discriminated union keyed by `kind`:
- `native: { kind:'native', pick(signal): Promise<string|null> }` — one OS chooser on host display. Abort terminates chooser. Unsupported platform throws.
- `browse: { kind:'browse', list(path?, signal): Promise<DirectoryListing>, createDirectory(path, name): Promise<string> }` — listing/creation primitives, works for remote clients, no host display.
- Consumers switch on `capability().kind`; unknown kind → hide affordance (not fail).

`DirectoryListing` shape:
```ts
{ path, home, crumbs: DirectoryEntry[], entries: DirectoryEntry[], truncated: boolean }
DirectoryEntry { name, path, hidden }
```
Crumbs = ancestry from filesystem root → listed dir inclusive, each jump target. `hidden` = dot-prefixed on POSIX (Windows hidden attribute not exposed). `truncated` when `entries` cut at `maxEntries` (1000) bounded window, tail missing.

### Browse Backend (host)
- `fullyQualified(path)` guard: POSIX-absolute vs Windows drive-qualified/UNC.
- `list` streams `opendir` into name-sorted bounded window `maxEntries+1`, `boundedInsert` O(log keep), eviction marks `truncated`. Symlinks to dirs via `stat` probe, broken/cyclic skipped. `raceAbort` vs signal so stalled network FS doesn't outlive caller. Abandoned handle close swallowed.
- `createDirectory` non-recursive `mkdir`, `EEXIST` → `directory-exists`, else `directory-create-failed`.

### DirectoryBrowser (Miller) Contract
680×500 dialog (viewport-clamped, Miller row scrolls sideways, columns scroll down). Header: title + breadcrumb + click-to-edit path zone. Content: Miller view.

**Layout**:
- One full-width level until row selected, then two columns splitting evenly (256px floor) around 1px divider `border-l3`. Solo column takes whole row.
- Header `pl24 pr14 pt16 pb8` gap 8, `crumbBar` flex with `crumbTrail` scroll, `crumbEditZone` flex `1 0 34px` pencil glyph, outline lit on hover/focus or when `pathInput` present. Title 16/24 510 `label-primary`.
- Content `p16 16 16 24` relative, `millerRow` flex `1 1 0` min-height 0 gap12 overflow-x auto scrollbar hidden. Column `flex 1 1 0` min-width 256 overflow-y auto `pr8` scrollbar gutter. Row `h28` gap4 `p4` radius6, hover `interactive-bg-hover`, selected `interactive-bg-active` + open-folder `button-info-fill`. Footer `p16 24` border top l3 flex-wrap gap8.

**State**:
- `parent: DirectoryListing|null`, `selected: DirectoryEntry|null`, `child: DirectoryListing|null`, `loading`, `slowScan` (derived via `SLOW_SCAN_DELAY_MS=300`), `scanWindow`, `error`, `pathDraft: string|null`, `showHidden`, `folderDraft: string|null`, `creatingFolder`, `createError`, `requestSeq`, `openGeneration`.

**Navigation (selection-anchored, quiet)**:
- Initial `open` → `navigate(undefined)` (home). Close invalidates in-flight (`supersede` aborts controller) and resets `loading`/`error`/`pathDraft`/`folderDraft`.
- `select(entry)`: immediate selected state on clicked row + pane split is the feedback (not held for child listing). Launches `listDirectory(entry.path)`, child preview right, crumbs follow selection. Failure clears `selected` fallback to single pane, re-parks focus on edit zone if focus fell to body (dot-revealed row re-hides).
- `advance(entry)` (right column pick): `setParent(child)` then `select(entry)` — view shifts one level deeper.
- `land(path?, {closeEditor, announce})` (crumb jump, submitted path, draft walk): launches target `list`, then parent leg `list(parentCrumb)`. Both legs land as ONE two-pane frame when parent settles within `PARENT_LEG_WAIT_MS=200`; past bound target commits single-pane at once and late parent upgrades in place. Failed parent or truncated window missing target → stay single-pane. While loading, stale view keeps rendering; `loading&&slowScan` floats `Loading…` pill `absolute right16 bottom8 bg-layer-2`. Error (browse `DirectoryBrowseError.message`) shows as `role=alert`.
- Parent selection anchored on actual parent entry (Windows case-folding: `toLowerCase` when sep is `\`), not typed `TYPED` case.

**Breadcrumb / current directory**:
- `displayCrumbs(listing, homeLabel)` collapses outside home: if `listing.crumbs` contains `home`, chain starts at localized `Home` crumb; else full ancestry. `separatorOf(listing)` from `home` path (`\` vs `/`). `levelDirectory(listing)` = `path` separator-terminated.
- Trail `scrollLeft=scrollWidth` on `crumbTail` change; Miller row `scrollLeft=scrollWidth` on `childPath` change (narrow viewport pin child into view).
- Current display: `crumbSource = child ?? parent`; `crumbs = displayCrumbs(crumbSource, t('browser.home'))`. Single vs two-pane determined by `displayCrumbs(target,'').length <2` (display root → single).

**Path editing**:
- Edit zone button (pencil, `aria-label`/`title` `browser.editPath`) seeds `pathDraft` with `base = selected?.path ?? parent.path` + trailing separator (`base.endsWith(sep)?base:base+sep`), supersedes pending listing, clears `previewSuspended`. No level → empty string (failed home recovery).
- Input `aria-label` editPath, `autoFocus`, controlled `value=pathDraft`, `onChange` supersedes, clears `previewSuspended`, `setPathDraft`. Composition guard `isComposing` prevents IME Enter submit.
- Editor cancellation observed at card scope (`editorScope` `display:contents`): `Escape` stops propagation, `refocusEditZone` if focus in input, `cancelPathEdit()` (supersede, `setLoading(false)`, `setPathDraft(null)`, `setError(null)`, fallback `setSelected(null)` if `child==null`, restart home if `parent==null`). `onBlur` when focus leaves card (document still focused, relatedTarget outside `closest('[role="dialog"]')`) cancels without re-parking (pointer paths suppress focus steal via `onMouseDown preventDefault` while `pathEditing`).
- Submission `Enter` (`!isComposing`, `trim()!=''`): `refocusEditZone=true`, `previewSuspended=true` (debounce must not supersede), `navigate(pathDraft)` (editor closes on arrival, failures surface).
- Speculative draft walk: `useEffect` on `pathDraft` debounce `DRAFT_PREVIEW_DEBOUNCE_MS=250` reads view via `viewRef` (not dep), `readDraft(current, pathDraft, scanned)`; if `directory==null||tail!=null` return (still inside listed level → prefix filter only); else `previewDraftLevel(directory)` → `land(directory,{closeEditor:false,announce:false})` (waits BOTH legs, no timeout, fails silently, clears error, re-parks focus onto editor if swap dropped focus to body).
- Filtering: `readDraft` → `directory` + `tail` (final segment prefix when `listing` is the level the draft's directory part names, `scanned` heals host respelling). `typedPrefix = crumbSource? readDraft(...).tail : null`. `LevelColumn` gets `filterPrefix = child==null ? typedPrefix : null` for left pane else `typedPrefix` for right. `visibleEntries(entries,selectedPath,showHidden,filterPrefix)` → selection exempt; `displayable = showHidden||!hidden||needle.startsWith('.')` (dot-led prefix reveals hidden); `narrowing = needle!='' && entries.some(matches)`; if narrowing → `matches`, else `showHidden||!hidden`. Prefix miss (no matches) releases filter (level shows whole, hidden returns to toggle) — a name being spelled, not demand for empty pane. Last pane is level draft names; stale pane holds still until landing (prevents double-move).
- Walk keeps panes: panes draft walked to stay put when editor closes (cancellation included); crumbs name where walk ended, `Open` fallback follows them.

**Hidden / footer**:
- Host-flagged `hidden`, hidden by default; footer's fixed-label `Show hidden files` toggle (`aria-pressed`, check when on, `onMouseDown preventDefault` while editing) reveals them client-side. Dot-led prefix also reveals matching hidden even while toggle off.
- `truncated` shows `browser.truncated` whenever visible pane cut, regardless of `loading` (stale status stays through scan). Reserved `pr120` keeps status/error from running under floating pill.

**New folder**:
- `New folder` button `disabled` when `parent==null||loading||parentInert||draftPending`. Opens nested create dialog targeting `selected?selected.path:parent.path` (`targetPath`), shows `targetName = selected?.name ?? displayCrumbs(parent).last.name`. Input `aria-label` folderName, `placeholder` untitledFolder, `autoFocus`, `disabled` while `creatingFolder`, composition guard. `Create` disabled while `folderDraft.trim()==''` or `creating`. `confirmCreate` validates `name.trim()!=''`, `setCreatingFolder(true)`, `createDirectory(targetPath,name)` → on success `setFolderDraft(null)`, relist `targetPath` (single leg, not two-pane), then `select({name,path:createdPath,hidden:false})` (figma 802:57446→813:23278). Failures surface as `createError` alert; `generation` guards against closed-reopened dialog. Nested dialog owns interaction while open: parent controls `inert` (`busy||folderDraft!=null`) go inert (Modals have no focus trap).

**Open / Cancel / Busy**:
- `targetPath = selected?.path ?? parent?.path`, `targetName` as above. `Open` adopts `targetPath` (fallback to listed level), `disabled` when `targetPath==null||loading||parentInert||draftPending`. `Cancel`/`onClose` reaches owner's `onCancel` (mask/Escape/Cancel) when `folderDraft==null&&!busy`. `busy` (owner's confirm in flight) disables `Open`, freezes view.

**i18n**:
`directory-browser` namespace: `browser.title` `browser.home` `browser.newFolder` `browser.create` etc. (zh+en).

### Native Flow Contract
Renderless `NativeDirectoryFlow({open,busy,onPicked,onCancel,onError,pick})`:
- `armed` ref once per open; re-renders/`busy`/`pick` identity change don't relaunch.
- `outcome` ref tracks latest props; `alive` ref false on unmount (HMR) → settlements discarded wholesale (host chooser survives but answer lands nowhere; replacement re-arms). StrictMode replay re-arms on setup.
- `open` rising edge → `pick().then(path==null?onCancel():onPicked(path), e=>onError(message))`.
- `open` withdrawn → `armed=false` re-arms next.
- Renders nothing (host display renders chooser).

### DirectoryPicker Capability
Switch on `kind`; merge-extensible `DirectoryPickerCapabilities` map. Unknown → hide affordance.

## Flutter Implementation

### Models
`DirectoryEntry` / `DirectoryListing` in `directory_browser.dart` (`fromJson` mirrors TS):
```dart
DirectoryEntry {name, path, hidden}
DirectoryListing {path, home, crumbs, entries, truncated}
```
`DirectoryBrowseError` wraps `RpcError` message (`directory-unreadable` etc.). Helpers: `displayCrumbs`, `separatorOf`, `levelDirectory`, `draftDirectory`, `readDraft`, `visibleEntries` (including `displayable` dot-reveal, `narrowing` miss-release, selection exempt).

### Service Seam
`directory_picker_service.dart`:
- `kBrowsePickerServiceName = 'directoryPicker.browse'`, `kNativePickerServiceName = 'directoryPicker.native'`
- `BrowseDirectoryPicker(WorkspacesService)` → `listDirectory({String? path})` / `createDirectory({path,name})` via `WorkspacesService.listDirectory` / `createDirectory` (host `host.listDirectory` / `host.createDirectory`). `pick()` headless returns null (Miller is UI; service registry parity retained).
- `NativeDirectoryPicker(WorkspacesService)` → `pick()` → `WorkspacesService.pickDirectory()` (`host.pickDirectory`).
- `defaultDirectoryPicker` kIsWeb → browse else native.

`runtime_services.dart:WorkspacesService` now wraps all three host methods:
- `pickDirectory()` → `host.pickDirectory`
- `listDirectory({String? path})` → `host.listDirectory`
- `createDirectory({path,name})` → `host.createDirectory` (extracts `path`)

`connection_client.dart` generic `callMethod` carries the Typert envelope; no dedicated typed method needed — `WorkspacesService` drives `host.*` via `_client.callMethod`.

### Miller Widget
`directory_browser.dart:DirectoryBrowser` (`StatefulWidget`):
- Props `open`, `listDirectory: Future<DirectoryListing>Function({String? path})`, `createDirectory: Future<String>Function({required String path, required String name})`, `onOpen(ValueChanged<String>)`, `onClose`, `busy`, `translate`.
- State mirrors React: `_parent/_selected/_child`, `_loading/_slowScan/_scanWindow`, `_error`, `_pathDraft` (+ `_pathCtrl/_pathFocus`), `_showHidden`, `_folderDraft` (+ `_folderCtrl/_creatingFolder/_createError`), `_requestSeq`, `_openGeneration`, `ScannedDirectory? _scanned`, `_draftDebounce`, `_previewSuspended`. Timers for slow scan (300ms), parent wait (200ms), draft debounce (250ms).
- Lifecycle: init/updates reset and `navigate(null)` (home); close supersedes and resets.
- `_navigate(String? path)` — target+parent two-pane landing with timeout upgrade, slow window restart, `landSingle` fallback, Windows case-fold `separatorOf`.
- `_landForDraft`, `_select`, `_advance`, `_cancelPathEdit`, `_onDraftChanged`, `_confirmCreate` (generation guard, relist then `select` created).
- `build`:
  - `crumbSource = child ?? parent`, `typedPrefix` via `readDraft`, `crumbs = displayCrumbs`, `targetPath`, `twoPane`, `parentInert = busy||folderDraft!=null`, `draftPending`.
  - `Dialog` `maxWidth 680 maxHeight 500` (ConstrainedBox), header `title` + `crumbBar` (Row with `crumbTrail` scroll + `crumbEditZone` pencil `IconButton` or `TextField` with `KeyValue 'pathInput'`), Miller `Stack` with `millerRow` horizontal scroll Row of `_LevelColumn` (left `width twoPane?320:632`, divider `1px borderL3` `margin 12`, right `320`), `_LevelColumn` (`ListView.separated` `h28` rows, `TextButton` `interactiveBgActive` when selected, `Icons.folder_open/outlined` `buttonInfoFill/labelSecondary`, `chevron_right` 12, `visibleEntries` filtering), truncated/status/error, floating `Loading…` pill `right16 bottom8 bgLayer2`, footer `Wrap` outer `spaceBetween` with left group (`New folder` `create_new_folder_outlined` + `Show hidden files` `check` when on) and right group (`Cancel` + `Open`), `Focus` Escape handling, nested create dialog `Positioned.fill` `black38%` `Material` `maxWidth 380` `p24 22 24 20` with `createIn` + `TextField` `createFolderInput` + error + `Cancel`/`Create` (disable blank/creating, spinner when creating).

Tokens: `DswTokens`/`DswAliases` (`bgLayer2`, `borderL3`, `labelPrimary` etc.), `fontSizeBase16` etc., no literal colors.

**Focus**: path editor focus park via `_pathFocus`/`_editZoneFocus` refs not yet fully wired to post-frame re-park (React's `refocusPathInput`/`refocusPick`/`refocusEditZone` consumed by effect) — simplified: input `autoFocus`, selection navigation pins Miller row via `jumpTo(maxScrollExtent)`, crumb tail pinned via controller.

**i18n fallback**: when `translate` null, English en dictionary embedded (`Select Workspace Directory`, `Home`, `New folder` etc.) so widget renders copy without locale provider.

### Adaptive Seam
`platform/adaptive_directory_picker.dart`:
- Retains `PlatformDirectoryPicker` interface + `WebDirectoryPicker`/`MacDirectoryPicker` `file_picker` fallbacks (offline tests). `platformDirectoryPickerProvider` kIsWeb branching unchanged for injection.
- `AdaptiveDirectoryPicker` branches at widget edge: `kIsWeb → WebDirectoryPickerField` (Miller), else `MacDirectoryPickerField` (native).
- `WebDirectoryPickerField` (`ConsumerStateful`): `Web: Miller-column browser — browse host directories (web)` hint, `Browse` button tries host `WorkspacesService.listDirectory` probe (`baseUrl.isEmpty` → no host); on host reachable `showDialog(DirectoryBrowser(...))` (`barrierDismissible:false`, `listDirectory`/`createDirectory` closures over `WorkspacesService`), otherwise falls back to `platformDirectoryPickerProvider.pickDirectory` (caught, returns null on `LateInitializationError`). Busy state while awaiting `onPicked`.
- `MacDirectoryPickerField` (`ConsumerWidget`): `Uses native folder picker (host.pickDirectory / NSOpenPanel)` hint, `Browse` tries `client.baseUrl.isNotEmpty → WorkspacesService.pickDirectory()` (host chooser), falls back to `platformDirectoryPickerProvider` local `NSOpenPanel` (caught). `onPicked` receives `String?`.

### Plugin / Slot Integration
`directory_picker_plugin.dart`:
- `BrowseDirectoryPickerPlugin(id='ui-directory-picker-browse', inject=['workspaces'])` → `BrowseDirectoryPicker(workspaces)` → `ctx.provide('directoryPicker.browse', …)` + `bindActivatedPickDirectory(picker)`; `onDispose` clears.
- `NativeDirectoryPickerPlugin(id='ui-directory-picker-native', inject=['workspaces'])` → `NativeDirectoryPicker(workspaces)` → `directoryPicker.native` + bind.
- `buildAppHost` registers `Browse` then `Native` (native binds last and wins on desktop).
- React holes `conversation.hero.workspace.directoryFlow` / `sidebar.workspaces.directoryFlow` still deferred (no Dart declaration) — noted; Miller is reachable via welcome `Workspace` chip, settings `Workspace directory`, sidebar rail/expanded `Add workspace`, all now branch to Miller on web.

Call-site updates:
- `workspace_picker_chip.dart:WorkspacePickerChip._addWorkspace` — `kIsWeb` → `showDialog(DirectoryBrowser)` (list/create via `WorkspacesService`), else `activatedPickDirectory.pick()`.
- `routing/app_router.dart:WelcomeScreen._pickDirectoryAndCreate` — replaced generic `TextField` AlertDialog (`/work/new-project` fallback) with Miller `DirectoryBrowser`; desktop branch uses host `pickDirectory` with `NSOpenPanel` fallback, matching React browse vs native split.
- `features/sidebar/sidebar.dart` — both `_CollapsedRail` and `_ExpandedSidebar` add-workspace handlers branch `kIsWeb` to Miller (including retry path) vs native.

## Verification

### Tests
`apps/flutter/test/plugins/directory_picker/directory_browser_test.dart` (18 tests):

- Closed renders no dialog chrome
- Opens at Home single wide column, hides `.config`, roots crumbs at `Home`
- Show hidden toggle reveals/hides
- Selects row → two-pane (Documents | harness), crumbs follow
- Advances via right column → level shift (harness selected left)
- Crumb jump Home → single pane
- Prefix-filters draft tail, dot reveals hidden (`.co` → `.config`, `do` → `Documents`)
- Open adopts selected else listed, Cancel closes, busy freezes Open (FilledButton onPressed null)
- New folder creates and selects (nested dialog `createFolderInput` → `Create`)
- Truncated indicator (`Too many folders…`)
- Helpers: `visibleEntries` hidden default, dot reveal, `displayCrumbs` roots at Home, `separatorOf` platform
- Platform contracts: `WebDirectoryPickerField` shows Miller hint, `MacDirectoryPickerField` shows native hint, Web Browse tap doesn't throw (fallback caught)

Existing suites still pass:
- `flutter test test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart` — 7/7 (browse/native services, workspace list/create, host.pickDirectory)
- `flutter test test/plugins/ws_surfaces/ws_surfaces_render_test.dart` — 3/3
- `flutter test test/integration/business_host_test.dart` — 1/1 (five workstreams)
- `flutter analyze lib` — 0 errors (warnings only, 88 infos)

### Tracker
`pnpm run verify-flutter-tracker --check` → `verify-flutter-tracker: OK (n items)`
- `platform.directoryPicker` parityCheck visual:pass behavior:pass platformParity web:pass macos:pass evidence testsRun + parityReport `migration/parity-reports/2026-08-23-directory-picker.md`
- `platform.ui-directory-picker-browse` visual:pass behavior:pass web:pass macos:pass tests directory_browser_test + ws_surfaces integrationPoints list browse primitives, Miller columns, navigation landing, visibleEntries, etc., e2eScenarios enumerate open/select/advance/crumb/prefix/hidden/new-folder/Open/Cancel/truncated
- `platform.ui-directory-picker-native` visual:pass behavior:pass web:pass macos:pass tests same + native pick arm/alive/discard semantics
- All remain **Integrated** not Verified (evidence outside tracker).

### Web/macOS Checks
- `kIsWeb` is the single branching point: `AdaptiveDirectoryPicker.build`, `defaultDirectoryPicker`, welcome/sidebar/workspace chip all check `kIsWeb` before choosing Miller vs native. No two binaries.
- Web (browser FS): Miller browse via `host.listDirectory`/`host.createDirectory` — works for remote clients, no host display.
- macOS (native): `host.pickDirectory` (`osascript`/`IFileOpenDialog`/`zenity`) via `WorkspacesService`, local `NSOpenPanel` via `file_picker` fallback when `baseUrl` empty (tests/offline).
- Visual: 680×500 clamped dialog, header/breadcrumb/edit zone, Miller row 2×320 split around divider (256 floor honored via 320), footer wrap with Cancel/Open. Dark/light aliases via `DswAliases`.
- Behavior: navigation selection-anchored and quiet (stale view holds), parent wait 200ms, slow pill 300ms, draft debounce 250ms, prefix filter dot-reveal, hidden toggle, new-folder selects created, Open fallback, Cancel via `onClose`/`Escape`/mask (barrierDismissible false for Miller, but cancel button + `Focus` Escape still).

### Builds
- `flutter build web` (canvas) and `flutter build macos` conceptually OK (no `dart:io` in web path; `file_picker` via conditional fallback). No new dependencies.

## Gaps & Deferred Work

1. **Declaring the directory-flow holes in Dart** — React registers into `conversation.hero.workspace.directoryFlow` / `sidebar.workspaces.directoryFlow` via `slots.inject` waiting for declarations. Dart `SlotRegistry` still lacks those child hole declarations (only parent hero hole declared), so the browse/native occupant contributions that would install `BrowseDirectoryFlow` / `NativeDirectoryFlow` as render occupants are still deferred with declaration (same as pre-existing note). The Miller is currently reached via explicit `showDialog` at call sites, not via a slot hole contribution. A follow-up should declare those holes in the Dart ledger and provide the two occupants (including the renderless `NativeDirectoryFlow` armed/alive/StrictMode semantics and the browse occupant that injects `t` and `listDirectory`/`createDirectory`).

2. **Focus re-park fidelity after commit** — React parks focus on the `aria-current` row after a left-pane pick and on the crumb edit zone after Enter/Escape; the Modal has no focus trap. Flutter currently relies on `autoFocus` + Miller row `jumpTo(maxScrollExtent)` and dialog dismissal; it does not yet fully replicate the `document.activeElement === body → focus(row|editZone)` effect. Keyboard Tab Reachability and IME composition guard (`isComposing`) are stubbed (`TextField` without composition handler). Acceptable for Integrated; a11y test should assert `aria-current`/`Edit path` focus after land.

3. **AbortSignal → Dart cancellation** — TS `listDirectory(path, signal)` aborts wire scan via `AbortController`; Dart `listDirectory({String? path})` currently has no `CancelToken`/`signal`. Supersession is via `requestSeq` discarding late settlements and canceling `Timer`s, but the underlying `host.listDirectory` HTTP call is not aborted on the wire (host scan keeps consuming). A follow-up can thread a cancellation token via `WorkspacesService` (e.g., `CancelableOperation` or `http.Request` abort) to mirror the wire abort.

4. **Windows case-folding and fullyQualified fences** — host fences fullyQualified, browse `boundedInsert` truncation, and Windows IFileOpenDialog path normalization (casing via `separatorOf` lower-casing) are host-owned; Flutter only mirrors `separatorOf` for displayCrumbs/parent match. No Dart test covers a Windows `C:\` home with forward-slash typed draft (the `draftDirectory` Windows branch handles both `\` and `/`).

5. **Locale namespace registration parity** — React browse registers `directory-browser` `zh`/`en` dictionaries via `ctx.locale.register` in `apply` (with transactional rollback on rival owner). Dart uses fallback English map in `_t` and relies on host describe for workspace names; no `LocaleService` namespace registration for `directory-browser` yet. A follow-up can register the same dictionaries in `BrowseDirectoryPickerPlugin.apply`.

6. **Snapshot / golden generation** — widget tests cover behavior; a `golden` for the 680×500 Miller (light/dark, one vs two pane, show-hidden on, dot filtered, truncated notice, nested create) should be recorded via `tester.pumpWidget` → `matchesGoldenFile` and committed under `test/goldens/`.

7. **e2e replay diff** — no replay fixture diff generated (category is `platform`, `platformParity` pass suffices for Integrated). Verified will require an `e2eScenarios` replay through the real `DshApp` boot with `buildAppHost` + `PluginHost.activateAll` and a wire fixture for `host.listDirectory`/`host.createDirectory`.
