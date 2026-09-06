# Agent Note: In-session terminal dock with session-cwd auto-attach

Status: implemented

English | [中文](2026-09-05-in-session-terminal-dock.zh.md)

## Problem

The console terminal panel shipped as a full-page route: the session-header action always navigated away from the conversation, and opening a session prompted for an optional name and spawned a new host session at the deployment workspace root — never at the directory the chat session runs in. A user inside a session had to leave the conversation, invent a label, and still landed in the wrong directory.

## Decision

The session-header terminal action toggles a docked terminal panel (`TerminalDock`) seated at the bottom of the conversation column, above the composer, instead of navigating. On the mobile shell (width <768) the action keeps the full-screen route, where a fixed-height dock does not fit.

- Revealing the dock auto-opens one unnamed console session at the owning chat session's working directory (`SessionSummary.cwd`, threaded through the existing `terminal/open` `cwd` parameter — no host change). An existing pool is shown as-is; re-revealing never multiplies sessions (`TerminalSessionsNotifier.ensureOpen`). A hidden dock spawns nothing.
- Every client open is unnamed: the host registry mints identity and the tab label falls back to the untitled string. The route's opener row lost its name field too.
- The full-screen route, tab strip, toolbar, and emulator view are shared with the dock through `ui/terminal_views.dart`. The route remains the mobile and deep-link surface and auto-opens the empty pool as well.

Consciously deferred: feeding user-run console commands into the session log so the model can see and run them. Model-visible inputs require a session event (model-visible ⟺ logged), so this needs a dedicated event contract — future work, not silently absent.

## Alternatives considered

- Keeping the route as the only surface, with a preselected default name — rejected: it still leaves the conversation and still opens at the workspace root rather than the session's directory.
- Per-session terminal pools keyed by chat session id — rejected: the console pool is host-global by contract (the `console` owner), and per-device caller identity is already a recorded deferral in the [terminal panel note](2026-09-04-flutter-terminal-panel.md).

## Consequences

- The pool stays host-global: two chat sessions on one host share the tab list, and the dock shows it as-is. The auto-open targets the cwd of the session that first revealed the dock, so cwd matching is per reveal, not per tab. Re-opening the dock in another folder reuses the same pool and shows the previous session's buffer — close the tab (×) to drop it.
- If the session cwd lies outside the console sandbox root, the host spawn fails into the dock's inline error banner; there is no silent fallback to the workspace root.
- Ctrl+C signals even while a foreground send is in flight (previously the busy guard swallowed it and the toolbar button was disabled, leaving no way to stop a long command). Ctrl+L clears the visible display and keeps the pending line; other control keys stay swallowed by the line-mode bridge.
- The toolbar status is busy-aware: the animated dot plus "running" appear only while a foreground send is in flight; an idle shell shows a static dot with "ready", and tab dots match. Previously every live session chased "running" forever, which read as a stuck command.
- `ls` column layout follows the host pty width (160 cols); the narrower emulator view wraps it. Use `ls -1` for one entry per line. Long-running foreground commands (`npm run dev`) hold the line-mode send until they exit — Ctrl+C stops them; serve-forever processes belong in the background.

## Verification

- `test/plugins/terminal/terminal_dock_test.dart` (3): hidden renders nothing and spawns nothing; reveal auto-opens an unnamed session with the session cwd in the header; the hide control collapses the dock and re-revealing does not re-open.
- `test/plugins/terminal/terminal_screen_test.dart` (2): empty-pool auto-open (unnamed, no name field) and the opener row spawning a second unnamed session.
- `test/plugins/terminal/terminal_bridge_test.dart` (+2): Ctrl+C delivers SIGINT while a foreground send is still in flight; Ctrl+L clears the display locally, keeps the pending line, and issues no host call.
- `test/plugins/terminal/terminal_dock_test.dart` (+1): toolbar reads "ready" idle, "running" busy, "exited (0)" closed.
- `flutter analyze` clean on changed files; the terminal suites green.
