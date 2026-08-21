---
name: web-component-to-flutter
description: Use when converting web React components (Cordis slots, PropsRuntime/PropsRenderSlots/PropsStore, CSS Modules) into idiomatic Flutter widgets while preserving props contract, composition, and UX.
---

# Web Component to Flutter

Convert `packages/client/ui-*` React components into Flutter widgets idiomatically.

## Sources of truth

* `packages/client/AGENTS.md:Slot and props discipline`, `Conversation Node discipline`, `Export discipline`
* Source component: `packages/client/<name>/src/client/*.tsx` + `*.module.css`
* `packages/client/ui-primitives/src/*` — atoms to port first
* `packages/client/ui-layout/src/client/AppFrame.tsx` — layout contract example

## Component model mapping

| Web (React + Slots) | Flutter |
|---------------------|---------|
| `ctx.slots.register({name, children, store, inject}, Component)` | `Widget` with explicit child slots as `Widget?` params or `Slot` builder typedefs |
| `PropsRuntime<K>` (`useSession`, `useSessions`, `useWorkspaces`) | `WidgetRef` / `ConsumerWidget` reading `Provider`/`Notifier` for sessions |
| `PropsRenderSlots<S>` (`renderSlot('sidebar', {collapsed, width})`) | Named child builders: `sidebarBuilder: (collapsed, width) => Widget` |
| `PropsStore<H>` (`useStore`/`actions.*`) | `StateNotifier`/`Notifier` from `createXXXStore` → `flutter_riverpod` `NotifierProvider` |
| `inject` face (plain data + callbacks + `hooks` compartment) | Constructor-injected services + `hooks` → `Listenable`/`Stream` providers |
| CSS Modules + `clsx` | `ThemeExtension` + conditional Dart branches |
| `// @vitest-environment jsdom` spec | `flutter test` widgetTest with `pumpWidget` |

## Workflow

### 1. Read contract

```sh
cat packages/client/<name>/src/client/*.tsx
cat packages/client/<name>/src/client/slots.ts 2>/dev/null
cat packages/client/<name>/src/*.module.css 2>/dev/null
cat packages/client/<name>/tests/*.client.spec.tsx | head -n 120
```

Identify: props shares, child slots, store actions, inject dependencies, render branches.

### 2. Design Flutter API

* Name: `DsButton`, `DsModal`, `ConversationComposer`, `ToolCallTree` — prefix `Ds` for design system
* Constructor params mirror the four shares, not raw `ctx`
* Child slots become `WidgetBuilder` or `Widget?` — never `ReactNode` passthrough
* Store → `lib/src/features/<feature>/<feature>_controller.dart` (`Notifier`)

### 3. Implement widget

```dart
// apps/flutter/lib/src/widgets/primitives/ds_button.dart
class DsButton extends ConsumerWidget {
  const DsButton({required this.label, required this.onPressed, this.variant});
  final String label; final VoidCallback? onPressed; final DsVariant? variant;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    // no literal colors
  }
}
```

* Pure build: no subscription machinery in leaf — reads `ref.watch(provider)` only
* Use `LayoutBuilder`/`CustomPainter` where web used `ResizeObserver`/`rAF`

### 4. Ports

* Keep file mapping 1:1 for parity checks: `Button.tsx` → `ds_button.dart`
* Export via `lib/src/features/<feature>/widgets.dart` barrel; do not expand public API without need (mirrors `Export discipline`)

### 5. Verify

* `flutter analyze` + `flutter test` mirrors `pnpm run test:gui` for that component
* Golden vs web screenshot (see `flutter-ui-visual-check`)

## Anti-patterns

* Do not translate JSX to `Html` — rewrite layout in Flutter primitives
* Do not bundle a component's store as global singleton — pass handle via provider constructor, shared only inside one `apply` scope equivalent
* Do not hand-write a `StatefulWidget` subscription mirroring `useSyncExternalStore` — route through provider
