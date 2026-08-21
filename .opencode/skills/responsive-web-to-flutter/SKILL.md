---
name: responsive-web-to-flutter
description: Use when making migrated Flutter widgets adaptive across Flutter Web browser sizes and Flutter macOS window sizes — replaces CSS ResizeObserver/rAF/viewport logic with Flutter LayoutBuilder, MediaQuery, and breakpoint tokens.
---

# Responsive Web to Flutter

Make Flutter Web/macOS widgets responsive, replacing CSS viewport mechanics with Flutter.

## Sources of truth

* `packages/client/ui-layout/src/client/AppFrame.tsx:99-142` — `viewport`, `ResizeObserver` + rAF, `SIDEBAR_AUTO_COLLAPSE=768`, concession solver `computeColumns`
* `packages/client/AGENTS.md:Styling` — global sheets vs component sheets
* `docs/web-styling.md` — breakpoint tokens

## Workflow

### 1. Capture web responsive contract

```sh
grep -R "ResizeObserver\|innerWidth\|viewport\|SIDEBAR_\|computeColumns\|@media" packages/client --include="*.ts" --include="*.tsx" --include="*.css" -n
```

For each, record: breakpoint value, concession rule, auto-collapse behavior, drag re-expand override (`stores.ts` narrowExpanded).

### 2. Map to Flutter

| Web | Flutter |
|-----|---------|
| `window.innerWidth` + `ResizeObserver` on `frameRef` | `LayoutBuilder` (frame box) + `MediaQuery.sizeOf(context)` (window) |
| `requestAnimationFrame` throttle | `SchedulerBinding.instance.addPostFrameCallback` / `WidgetsBinding` frame |
| `@media` breakpoint | `Breakpoint` enum + `Responsive` extension on `BuildContext` |
| `gridTemplateColumns: ${sidebar}px 1fr ${details}px` | `CustomMultiChildLayout` or `Row` with `SizedBox(width:)` + `Expanded` |
| `SIDEBAR_AUTO_COLLAPSE` narrow → rail | `LayoutBuilder` narrow flag → `NavigationRail` |

```dart
// apps/flutter/lib/src/theme/breakpoints.dart
abstract class Breakpoints {
  static const sidebarCollapse = 768.0;
}
extension Responsive on BuildContext {
  bool get isNarrow => MediaQuery.sizeOf(this).width < Breakpoints.sidebarCollapse;
}
```

### 3. Preserve drag & concession

* Port `computeColumns(viewport, sidebarPreference, details)` to Dart pure function, unit-tested with same cases as `ui-layout/tests/app-frame.client.spec.tsx`
* Drag handles: `GestureDetector(onHorizontalDragUpdate)` with pointer capture equivalent, delta from origin, no easing while dragging (`AppFrame.module.css` pause)

### 4. Verify

* `flutter test` widget tests pump at `Size(400,800)` vs `Size(1200,800)` and assert collapsed vs expanded
* `flutter test` golden at 3 breakpoints
* macOS: resize window via `tester.binding.window.physicalSizeTestValue` and assert concession

## Anti-patterns

* Do not use `MediaQuery` only for frame-local sizing — use `LayoutBuilder` for column box
* Do not hardcode pixel values outside tokens
* Do not drop rAF throttling — Flutter frame callbacks are the equivalent
