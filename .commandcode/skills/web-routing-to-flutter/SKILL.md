---
name: web-routing-to-flutter
description: Use when mapping the Cordis slot composition graph (no URL router) to Flutter navigation — slots → GoRouter/Navigator 2.0 routes or shell branches, preserving session scoping and deep-link behavior.
---

# Web Routing to Flutter

Map the web slot tree (no URL router) to Flutter routing.

## Sources of truth

* `packages/client/AGENTS.md:children = declaration + authorization`, slot names `domain.entry.hole` (`tool.call.toolview`)
* `packages/client/ui-layout/src/client/AppFrame.tsx` — `root → sidebar|conversation|details|shell.overlay`
* `packages/client/ui-sidebar`, `ui-workspace`, `ui-conversation`, `ui-trajectory`, `ui-subagent` — session-scoped navigation
* `packages/client/web/src/seed.ts`, `boot.ts` — web boot shell

## Concept mapping

| Web | Flutter |
|-----|---------|
| Cordis slot graph (declarative, hot-reloadable) | `GoRouter` `ShellRoute` tree + per-feature `Route` registrations |
| `renderSlot('sidebar', {collapsed, width})` | `ShellRoute(builder: (ctx, state, child) => AppFrame(sidebar: Sidebar(...), child: child))` |
| Session-aware slots (`session` scope + `useSession`/`sessionId`) | Route param `:sessionId` + `sessionProvider(sessionId)` — strict vs `session-maybe` entries mirror `StatefulShellBranch` |
| `conversation.chat.node` `ConversationNodeDefinition` | `GoRoute(path: '/sessions/:id/chat/:nodeId')` or embedded `Navigator` keyed by node |
| `shell.overlay` | `Overlay` / `RootNavigator` dialog route |
| `ui-subagent` child transcript states | Nested `ShellRoute` with separate `Navigator` key |

## Workflow

### 1. Dump slot graph

```sh
grep -R "children\|SlotMap\|renderSlot" packages/client --include="*.ts" --include="*.tsx" -n | head -n 120
cat packages/client/ui-layout/src/client/columns.ts
```

Produce `migration/routing-graph.md` — slot → Flutter route table.

### 2. Choose router shape

* Primary: `GoRouter` with `StatefulShellRoute` for 3-col AppFrame (sidebar persistent, center branch, details branch) — mirrors `AppFrame` keeping occupants mounted (`detailsCol` width 0 but mounted).
* Alternative for overlay: `Navigator 2.0` `RouterDelegate` if GoRouter shell insufficient.

### 3. Session scoping

* Route `/` redirects to `/sessions/:currentId` if `current` exists, else blank state (like `detailsSession` blank guard `AppFrame.tsx:94`).
* Switching session updates route without remounting sidebar: `context.go('/sessions/$id')` while `AppFrame` stays mounted, details auto-closes on `current` change (`AppFrame.tsx:102`).

### 4. Implement

```dart
// apps/flutter/lib/src/routing/app_router.dart
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (ctx, state, navShell) => AppFrame(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', redirect: ...) ]),
          StatefulShellBranch(routes: [GoRoute(path: '/sessions/:sid', builder: ...) ]),
        ],
      ),
      GoRoute(path: '/sessions/:sid/trajectory', builder: (ctx,s) => TrajectoryScreen(...)),
    ],
  );
});
```

### 5. Verify

* Deep link: `flutter test` drives `router.go('/sessions/$id')` and expects correct branch active
* Back/forward preserves shell state (sidebar width not reset)
* Web deep link works: `flutter build web` + browser `pushState` test

## Anti-patterns

* Do not invent URL routes where web has none — route is a projection of slot state, not a new information architecture
* Do not mount `AppFrame` per route — single shell mounted at root
* Do not store route transient in global singleton — route state is provider state derived from `GoRouterState`
