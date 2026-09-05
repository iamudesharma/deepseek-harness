# Agent Note: Native application menu bar (macOS)

Status: implemented

## Problem

The Flutter Mac app had no native menu bar: view toggles, the command
palette, and the console terminal lived only in session-header and canvas
controls, where Mac users never look for them. The Swift side
(`MainFlutterWindow.swift`) is stock, and touching native code means
entitlement and Pod changes; pure-Dart `PlatformMenuBar` renders as the
real app menu on macOS and stays inert elsewhere — exactly the
Flutter-only constraint.

## Decision

`DshMenuBar` in `widgets/layout/menu_bar.dart` wraps the desktop
`AppFrame` (the mobile shell is unaffected): a View menu (Toggle Sidebar
on ⌥⌘S; Command Palette on ⌘K) and a Terminal menu (Open Console
Terminal, Background Jobs). The menus surface only existing capabilities
— route navigation and `layoutProvider.toggleSidebar()` — and disable
(rather than hide) session destinations without a current session.
Accelerators dodge composer text keys: ⌘K is meaningless in a plain text
field (the Slack quick-switcher precedent), ⌥⌘S avoids the ⌘B bold
conflict, and the terminal entry deliberately has none so it never steals
keys from xterm focus.

Consciously deferred: a global hotkey (new dependency plus system
permission), Dock badges/notifications (native code or a
`flutter_local_notifications` entitlement and Pod change), and a ⌃`
terminal summon (conflicts with xterm focus).

## Verification

- `test/widgets/menu_bar_test.dart`: menu structure (View/Terminal),
  terminal entry labels, enabled with a session, disabled without one,
  content passthrough.
- `flutter analyze` clean on changed files.
