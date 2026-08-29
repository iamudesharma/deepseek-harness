# Flutter remote selection restore: validate against direct host reads, gate bootstraps in order

- **Date:** 2026-08-25
- **Status:** implemented
- **Kind:** architecture
- **Area:** apps/flutter (remote connection), Phase 5

## Decision

Phase 5's "restore previously selected workspace/session after app restart" is wired as three ordered steps in the root widget (`app_plugins.dart` `_buildRoot`):

1. `connectionTargetBootstrapProvider` — restore the persisted `RemoteTarget` from SharedPreferences before any live pump reads `connectionTargetProvider`.
2. `sessionBootstrapProvider` — hydrate `SessionsState` from `session.list`.
3. `selectionRestoreProvider` — validate persisted selection ids against fresh host data, then apply them to the existing single state system (`selectedWorkspaceProvider`, `sessionsProvider.setCurrent`).

Two ordering rules are load-bearing:

- `connectionBootstrapProvider` no-ops while the target bootstrap is still loading. Without this gate the first handshake races the prefs read: it connects loopback once, then tears down and reconnects when the target flips to `RemoteTarget`.
- `selectionRestoreProvider` awaits `sessionBootstrapProvider.future` before applying selections because `SessionsController.setAll` preserves `current` only when the id already exists in `byId`, and `setCurrent` silently ignores unknown ids. Restoring before hydration loses the selection.

Validation reads `workspace.list` / `session.list` directly from `ConnectionClient`, not through `workspaceListProvider`: that provider falls back to synthetic `kWorkspaceOptions` on transport failure, which would validate selections against fake workspaces. A stale id is cleared from storage and reported (`SelectionRestoreOutcome.sessionMissing`) so the sessions screen can show a clean "previous session unavailable" message instead of fabricating a row.

## Consequences

- Persisted ids are never trusted without host confirmation; transport errors retain keys for retry via provider invalidation after reconnect.
- Widget tests without a SharedPreferences mock hit `connectionTargetBootstrapProvider`; it catches the missing-plugin error and keeps `LocalTarget`, so default desktop/web behavior is byte-identical.
- Removing a paired computer clears token, target, and both selection keys together (`devices_screen.dart`).
