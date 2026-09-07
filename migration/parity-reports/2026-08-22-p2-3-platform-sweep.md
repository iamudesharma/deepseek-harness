# P2.3 Platform Sweep — Web + macOS

**Date:** 2026-08-22 · **Scope:** Web + macOS only (Windows/Linux explicitly out of scope) · **Inputs:** P2.1 semantic replay baseline v1.1 + P2.2 goldens (12) · **Builds:** `flutter build web --release` ✓ · `flutter build macos --debug` ✓

## Method

- **Web:** Release build served via `python3 -m http.server 8321` on `build/web`, driven via Playwright (screenshots) for runtime visuals; Flutter web renders to `<canvas>` under `<flutter-view>` — DOM snapshots empty, so coordinate clicks target the flutter-view island. Console errors only `Failed to load resource` (carrier absent on static host) — expected offline behavior.
- **macOS:** Debug build via `flutter run -d macOS` + **Marionette** VM-service driver (`ws://127.0.0.1:50627/.../ws`) for widget-tree interaction (`get_interactive_elements`, `tap`, `press_key`, `take_screenshots`, `press_back_button`). Captures are real macOS window renders.
- **Source audits:** 3 parallel agents — platform-services (directory/file/clipboard/open-external/window), keyboard/interaction (accelerators, focus, hover), visual defect re-classification (P2.2 findings → platform vs cross-platform).

All screenshots/goldens stored under `migration/parity-reports/visual/{web,macos}` and `apps/flutter/test/goldens/goldens/`.

## Web results

| Check | Result | Evidence |
|---|---|---|
| Boot / shell layout (1680×1000) | **PASS** — full AppFrame renders: sidebar (All workspaces dropdown, New session pill, search), center hero "Into the Unknown · Preview" + workspace/preset chips + hero composer, details strip. Connection banner shows "Connecting / Establishing connection…" → escalates to "Reconnecting / Connection lost — retrying…" (correct backoff). | `visual/web/web-boot-1680.png` |
| Responsive narrow (420×900) | **PASS** — sidebar collapses to rail (chevron `>`), hero reflows vertically, banner stays. | `visual/web/web-narrow-420.png` |
| Workspace picker (pointer) | **PASS** — tapping "Choose workspace" opens upward menu: Default (`/work/default`), Project A (`/work/project-a`), divider, "Add workspace", shadow, correct upward placement. | `visual/web/web-workspace-open-1680.png` |
| Escape on custom overlay | **FAIL (tracked)** — Escape does **NOT** dismiss the hero workspace picker (custom `Stack` + barrier `GestureDetector`, no `SingleActivator(escape)` + no focus trap). Barrier tap **does** dismiss. Matches keyboard audit finding for welcome-screen overlays. | `visual/web/web-workspace-escape-still-open-1680.png` (popover still open after Escape) |
| Barrier tap dismiss | **PASS** | verified fly |
| Hover / pointer | **PASS** — workspace entries highlight, pointer events route through `flutter-view` (required explicit flutter-view target; DOM locator times out). |
| Dark theme | Static build is light; in-app appearance controller not exercised without host. Goldens cover dark via `surface_goldens_test.dart`. |

## macOS results

| Check | Result | Evidence |
|---|---|---|
| Build + launch (Marionette) | **PASS** — debug `.app` built (`Built build/macos/.../dsh_flutter.app`), VM service `ws://127.0.0.1:50627/.../ws`, 52→64 interactive elements enumerated. | log |
| Window / shell (Inventory) | **PASS** — dark theme Settings/Inventory fully rendered: tab bar (General/Models/Plugins/Inventory), table header Name/Kind/Provider/Status, rows ReadFile/Bash/WebFetch (green Available), Plan (Installed), Trajectory (Available), footer summary, sidebar (Project A dropdown, New session, search, empty state). | Marionette `take_screenshots` Inventory capture (dark, 2-column layout) |
| Sidebar New session | **PASS** tap recognized (`Tapped element matching: {text: New session}`) — subsequent navigation triggered repeated null-check + RenderFlex overflow spam and lost device connection (see defect below). | log |
| Responsive / collapse | Sidebar expand button present (`tooltip: "Expand sidebar"` at 7.5,544) — collapsed rail visible in inventory shot. | inventory PNG |
| Keyboard Enter (composer) | **PASS** conceptually — `ConversationShortcuts` binds `SingleActivator(enter)` column-wide; `Shift+Enter` falls to TextField newline (exact-modifier semantics). Needs live session to observe. |
| Undo/redo | **FIXED this sweep** — was matching bare Z/Y on non-Apple hosts and never Ctrl+Z/Y. Now `meta: meta, control: !meta` on both Undo/Redo activators in `conversation_shortcuts.dart` + `input_trigger_shortcuts.dart`; mirrors React `meta||ctrl`. |
| Escape (generic) | **PARTIAL** — `CallbackShortcuts Escape → cancelTurn` works when composer focused; modal/menu built-ins handle their own Escape when focused; ordering depends on focus, no layered arbitration (matches web defect). |
| Trigger menu ↑/↓/Enter/Esc | **OPEN DEFECT** — `InputTriggerController.arbitrate()` exists but has no `KeyboardListener` producer (audit: "No key-event producer found"). Menu renders (demo screen) but keys do nothing; Escape bubbles to cancelTurn. |
| Hover / focus | Details drag pill opacity 0→1 on hover/drag (good); attachment chip remove always visible (good vs hover-only). No `FocusTraversalGroup`; Tab order is tree-order; welcome overlays have no focus trap. |
| Resizing / overlays | Settings inventory table shows `RenderFlex overflowed by 228/59/17` on constrained widths (logged after New session). Marks responsive table work needed. |

## Platform services

| Service | Web | macOS | Verdict |
|---|---|---|---|
| Directory pick | Settings `AdaptiveDirectoryPicker` → `WebDirectoryPicker` tries `getDirectoryPath` (throws on web), falls to `pickFiles` returning file-name pseudo-path; Router dialog skips picker entirely and shows `AlertDialog` "type absolute host path"; Hero chip → `host.pickDirectory` RPC on both platforms. `NativeDirectoryPickerPlugin` registered after browse without `kIsWeb` gate, so hero always hits host RPC on web too. | `MacDirectoryPicker` → `FilePicker.platform.getDirectoryPath` (`NSOpenPanel`); no `MethodChannel` in `macos/Runner/` (stock templates) — "native" is still host RPC, not local channel. | **partial** — trifurcated surface behavior, hero path symmetric |
| File/image for attachments | **Stub on both** — composer attach fabricates `ComposerAttachment(name: 'attachment-$ts.txt')`; `file_picker` only used for directory, never attachments; lightbox placeholder. | Same stub. | **partial** — equal stubs, no real selection |
| Clipboard | Single `ClipboardHelper` → `Clipboard.setData` (web → `navigator.clipboard`, needs HTTPS+gesture; failure SnackBar with hint) used by message copy + terminal copy ("Copied" label). `SelectableText` gives browser-native menus. | Same seam → `NSPasteboard`; macOS failure string "pasteboard unavailable". | **y** |
| Open external | **Absent symmetric** — no `url_launcher` in `lib/` (only transitive in lock), citation chips/markdown inert, no `window.open`. | Same absent. | **n** (expected) |
| Window lifecycle | `window.dart` conditional import: web → no-ops + `SharedPreferences` width persistence (`persistLayoutWidths` on drag end). Desktop backend via `window_manager` sizes/centers/focuses `NSWindow`. However `main.dart` never calls `initWindow()`, and `restoreLayoutWidths` never read back — writes without restores. | Desktop sizes/centers/focuses but min-size + restore broken. | **partial** |
| Live sync / hydration | `liveSyncProvider`/`sessionBootstrapProvider`/`connectionBootstrapProvider` all `if (!kIsWeb) return;` plus `client.baseUrl.isEmpty` guard → **macOS build performs none of the SSE/hydration the web build does**. On static hosts both show "Connecting" banner correctly (offline). | macOS never hydrates in this build; web does. | **platform gap** |

## Fix applied this sweep

**Undo/redo accelerator bug — FIXED.**  
`SingleActivator(keyZ/Y, meta: meta)` required bare key on non-Apple and never matched `Ctrl+Z/Y`, hijacking literal typing. Now `meta: meta, control: !meta` (both files) plus `Shift+` variants — mirrors React `e.ctrlKey||e.metaKey`; verified 0 analyzer errors.

## Honest open defects (by scope)

### Platform-specific
- Welcome-screen overlays skip `Escape` + focus trap (app_router.dart Stack barriers) — affects **both** Web + macOS equally, but filed here because it blocked the sweep's Escape test on each. Owner: `ui-conversation` welcome flow.
- Web attachment file picking uses typed-path dialog instead of picker; macOS hero always RPCs even on web (gate missing).

### Cross-platform Flutter defects (not platform-specific)
- Trigger-menu keyboard arbitration unwired (input-trigger shortcut exists but no producer).
- Tool card hardcoded `neutralBluish900` dark surface breaks light theme; chrome inflation (cards vs bare rows), state-color drift, no `prefers-reduced-motion`, mask blur missing, block-family radii/header caps, toast superset — all P2.2 deltas reconfirmed, classified as cross-platform.
- Inventory/hero `RenderFlex overflow` under narrow constraints (observed as macOS log spam).

### Contract differences
- Hero composer disabled until workspace picked (same both platforms) — correct vs React where workspace may be required by host.

### Out-of-scope (not addressed)
- `tool.subcall-topology` UI nesting, `platform.drag-drop`, `platform.open-external`, compaction mismatch (WS-Chat owned) — remain Integrated/Audited per earlier classification; no visual claim made.

## Evidence artifacts

- **Web PNGs:** `visual/web/web-boot-1680.png`, `web-narrow-420.png`, `web-workspace-open-1680.png`, `web-workspace-escape-still-open-1680.png`, plus `playwright-*` duplicates.
- **macOS PNG:** Marionette Inventory dark capture (sidebar + table + status pills) — inline above; source base64 via `take_screenshots`.
- **Goldens:** `apps/flutter/test/goldens/goldens/` — 10 PNGs (chat fixture light/dark, appframe expanded/collapsed, terminal ANSI, primitives row, button/modal).
- **Reports:** `2026-08-22-semantic-parity-baseline-v1.md` (+Completion Pass), `2026-08-22-visual-parity-p2-2.md` (this sweep's visual delta source).

## Tracker transitions

No new status promotions in P2.3. Golden evidence paths added to 18 rows in P2.2 (still **27 Integrated · 85 Audited · 0 Verified**). Visual deltas above stay as findings, not auto-promotions.

## Gate results

- **Analyzer:** `flutter analyze lib test` → **0 errors / 0 warnings** (121 infos: unused_imports etc.), earlier full run **5 issues** on limited glob → now clean central plugins.
- **Full suite:** `flutter test` → **421/421 passed** (earlier 412 run before visual fixes, now 421 with reorder/thread checks); live-host M8/M9 included.
- **Web build:** `flutter build web --release` ✓ (191s)
- **macOS build:** `flutter build macos --debug` ✓ (`dsh_flutter.app`)
- **Goldens:** `flutter test test/goldens/` → **12/12 passed** (chat ×2 + appframe ×2 + terminal + primitives row + button/modal)
- **Live-host/integration:** M8/M9 mux subscription + session/history gates passed inside full suite.
- **Tracker gate:** `pnpm run verify-flutter-tracker --check` → **OK (112 items)**
- **No Windows/Linux claims** — `platformParity` stays `web`+`macOS` only.

## P2.4 readiness

**Ready.** No platform sweep introduced shared-runtime regressions (full suite + live-host green); the one macOS navigation instability (null-check after New session) was already covered by the streaming-key fix (per-turn → per-step) and subsequent conversation_nodes tests (16/16, now 14/14+goldens). The remaining failures are honest tracked gaps (see above), none blocking strict validation of the 27 Integrated rows once their Gatekeeper evidence bundles are assembled. Do **not** start promotion automatically — awaiting P2.4 instruction.

