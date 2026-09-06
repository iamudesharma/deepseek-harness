# Agent Note: Flutter console terminal panel over the terminal Remote namespace

Status: implemented

English | [中文](2026-09-04-flutter-terminal-panel.zh.md)

## Problem

The `ctx.remote.terminal` namespace had a tested Host owner and typed Flutter wire faces, but no surface: the only terminal UI in Flutter was read-only output cards. A panel that drives host shells needed an emulator for output fidelity, a bridge onto the line-mode verbs, and a home in the plugin/routing composition — without duplicating runtime state or inventing a contract outside the generated descriptors.

## Decision

`plugins/terminal/` is a `ui-terminal` plugin in the established shape: `terminal` locale dictionaries (zh source of truth, key-identical en), a session-header action (`conversation.session.header.actions`, id `terminal`, order 21, trailing the `job-list` entry), and a `/sessions/:sid/terminal` route beside the jobs screen. The console pool is host-global. On the desktop shell the action toggles an in-session dock instead of navigating (see the [dock note](2026-09-05-in-session-terminal-dock.md)); the route remains the mobile and deep-link surface, and its session id scopes sibling-screen consistency plus the cwd new sessions spawn in.

- The emulator is the maintained `xterm` pub package (v4) rather than a hand-rolled VT layer: one `Terminal` buffer per session (2000-line scrollback), `TerminalView` with an alias-mapped `TerminalTheme`, and keystrokes arriving exclusively through `Terminal.onOutput` — the view never echoes locally, which is exactly what a line-mode bridge needs.
- The bridge is explicit about the seam: printable text appends to a pending line with local echo, backspace erases, Enter submits one `terminal/send` and paints the settled viewport, Ctrl+C signals SIGINT without submitting, and escape sequences are swallowed because the host has no cursor-addressing verb to carry them. The emulator still renders every output byte (colors, `\r` progress frames) with full fidelity. Session exit marks the tab closed; a manual refresh reads the scrollback tail (no follow stream exists yet, as recorded).
- `TerminalSessionsNotifier` owns the pool: `terminal/list` snapshots preserve live buffers, opens paint the MOTD and select, closes drop the buffer. Failures surface inline per session plus a dismissible banner.
- The commands catalog gains a `terminal` entry for palette discovery.

Consciously deferred: continuous keystroke streaming, PTY resize, and a reconnect-safe follow stream (all need backend capabilities the bounded line-mode seam does not expose); per-device pools (Remote verbs carry no caller identity).

## Alternatives considered

- Hand-rolled VT renderer over the alias palette — rejected: the maintained `xterm` package deletes owned code and tests, and only the input bridge is genuinely bespoke to the line-mode seam.
- A WebSocket keystroke/output stream — rejected: the host exposes bounded line-mode verbs only; streaming needs backend capabilities the seam does not expose, so it is recorded as deferred rather than half-built.
- Per-device console pools — rejected: Remote verbs carry no caller identity, so the pool cannot be scoped per device without a contract change.

## Consequences

- Output fidelity is limited to what the bridge paints: colors and `\r` progress frames render fully, but cursor-addressing keys do nothing because no verb can carry them.
- Scrollback beyond the settled viewport is manual — refresh reads the tail — and there is no follow stream, so live output stops at the last submission.
- The host-global pool shows the same tab list on every device; buffers live client-side and survive rebuilds, and the next `terminal/list` paints `[closed on host]` into buffers the host no longer reports.

## Verification

- `test/plugins/terminal/terminal_bridge_test.dart` (6): MOTD paint and selection, type-echo plus Enter-submit painting the viewport, backspace and arrow swallowing, Ctrl+C signaling without sending, exit marking, close/refresh buffer handling — all against a scripted HTTP host.
- `test/api/connection_client_rpc_test.dart` (+6): every verb's envelope (`args.request`) and result shape against the scripted host.
- `test/plugins/terminal/terminal_plugin_test.dart` (2): header-action order with teardown, dictionary key parity.
- `test/plugins/terminal/terminal_screen_test.dart` (2): empty-pool auto-open (unnamed, no name field) and the opener row spawning a second unnamed session. It uses an answering fake, not sockets: real `HttpServer` round-trips stall under `testWidgets`' fake-async zone (plain-`test` scripted hosts are unaffected), so socket coverage stays in the bridge and rpc tests by design.
- `test/plugins/terminal/terminal_dock_test.dart` (3): dock reveal, session-cwd auto-open, and hide/reveal idempotence (see the [dock note](2026-09-05-in-session-terminal-dock.md)).
- `flutter analyze` clean on changed files; full `flutter test` green except the pre-existing HEAD failures.
