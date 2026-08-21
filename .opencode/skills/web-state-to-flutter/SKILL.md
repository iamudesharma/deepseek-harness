---
name: web-state-to-flutter
description: Use when migrating web frontend state (Cordis slot stores, runtime object layer, inject hooks, session/event windows) to Flutter state management (Riverpod/Notifier, ChangeNotifier) with the same visibility and lifecycle guarantees.
---

# Web State to Flutter

Migrate `defineStore`, `createXXXStore`, `runtime` object layer, and inject `hooks` to Flutter.

## Sources of truth

* `packages/client/AGENTS.md:Reactive read`, `Stores: read props.useStore, write props.actions.*`
* `packages/client/runtime/src/*` — `SessionManager`, `Session`, `ConnectionController`, notifier (`markDirty`/`markFrameDirty`)
* `packages/client/*/src/client/stores.ts` — store factories
* `packages/client/ui-renderer/src/client/*` — hook binding (`SessionProvider`, uSES adapter)

## Mapping

| Web | Flutter |
|-----|---------|
| `createFooStore()` factory + `register({store})` | `class FooController extends Notifier<FooState>` + `final fooProvider = NotifierProvider<FooController, FooState>(FooController.new)` |
| `props.useStore(selector)` | `ref.watch(fooProvider.select((s)=>...))` |
| `props.actions.*` | `ref.read(fooProvider.notifier).doAction()` |
| `useSession`/`useSessions`/`useWorkspaces` (standing seats) | `sessionProvider`, `sessionsProvider`, `workspacesProvider` globally seeded (like `PLATFORM_MODULES`) |
| Inject `hooks` compartment (bare observables) | `StreamProvider` / `ValueListenableProvider` — never pass `Stream` as widget prop |
| Object-layer `Session` event window (no React imports) | `StateNotifier`/`Notifier` in `lib/src/core/session/` — still zero widget import, pure Dart |

## Workflow

### 1. Audit store

```sh
grep -R "create.*Store\|defineStore" packages/client --include="*.ts" -n
cat packages/client/<name>/src/client/stores.ts
cat packages/client/runtime/src/client/sessions/*.ts | head -n 120
```

For each factory record: state shape, actions, owning slot, scope (global vs entry), persistence (session log vs ephemeral).

### 2. Port factory

```dart
// apps/flutter/lib/src/features/layout/layout_controller.dart
class LayoutState { final double sidebar; final double details; final bool narrowExpanded; }
class LayoutController extends Notifier<LayoutState> {
  @override LayoutState build() => const LayoutState(sidebar: 280, details: 360, narrowExpanded: false);
  void setSidebar(double v) => state = state.copyWith(sidebar: v);
  void setDetails(double v) => state = state.copyWith(details: v);
  void setNarrow(bool v) {} // mirror setNarrow(sidebarCollapsed) logic from AppFrame.tsx
}
final layoutProvider = NotifierProvider<LayoutController, LayoutState>(LayoutController.new);
```

* Factory must remain invocable independently for tests: `LayoutController()` + `container.read(layoutProvider.notifier)` — mirrors `createXXXStore().create()` in tests

### 3. Wire lifecycle

* Business data (sessions, frames, connection) lives in `lib/src/core/*`, never in widget `State`
* Visible streaming uses `markFrameDirty` analogue: `ref.notifyListeners` batched via `Future.microtask` for structural, immediate for visible chunks
* Dispose: provider autoDispose matches fiber disposal; verify with HMR-safety analogue (`container.dispose` removes contribution)

### 4. Three-channel discipline (AGENTS.md)

* Parent knows → owner params at call site (`renderSlot` → builder args)
* Only component knows → local `StatefulWidget` `setState`
* Shared/remount-surviving → provider (declared at register site)

### 5. Verify

* Unit: `container = ProviderContainer()` + drive actions + `expect(container.read(provider), ...)`
* Widget: `ProviderScope` with overrides, pump, assert visible behavior, not class names
* Harness: dispose container, expect no leaks

## Anti-patterns

* Do not create singleton global stores via `static` — pass handle via `ProviderScope` overrides to share across `register` equivalents
* Do not mirror external snapshot into local `State` — use `ref.watch`
* Do not put model-visible session log writes in UI layer — route through `SessionManager` Dart port
