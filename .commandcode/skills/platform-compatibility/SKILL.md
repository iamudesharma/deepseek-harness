---
name: platform-compatibility
description: Use when handling platform differences across Flutter Web and Flutter macOS — web CanvasKit/Wasm, responsive/breakpoints, and macOS windowing, menus, keyboard/mouse, file pickers, and desktop layout.
---

# Platform Compatibility — Flutter Web + macOS Skill

Ensure migrated Flutter app works correctly on both Flutter Web (browser) and Flutter macOS (desktop).

## When to use

* Any feature that renders differently web vs macOS
* Windowing, navigation, input, file-system, or layout behavior
* Before marking tracker item `Tested`

## Split guidance

| Concern | Flutter Web | Flutter macOS |
|---------|-------------|---------------|
| Rendering | CanvasKit vs HTML renderer, Wasm, font loading | Native Skia/Impeller |
| Layout | Browser viewport, URL `pushState`, `ResizeObserver` | `NSWindow` frame, `MethodChannel` window_manager, unlimited resize |
| Input | `PointerEvent` capture already in web, touch vs mouse | Keyboard shortcuts (`Meta` vs `Ctrl`), right-click, hover, drag |
| File | `<input type=file>`, `FileReader` | `NSOpenPanel` via `file_picker` / `file_selector` (`ui-directory-picker-native` vs `browse`) |
| Nav | Deep link via URL | Window title, menu bar, dock |
| Build | `flutter build web --wasm` | `flutter build macos` + entitlements, notarization |

## Workflow

### 1. Classify platform sensitivity

```sh
grep -R "window\|navigator\|ResizeObserver\|pointerCapture\|clipboard\|file" packages/client --include="*.ts" --include="*.tsx" -n | head -n 50
```

Tags: `web-only`, `macos-only`, `adaptive`.

### 2. Implement adaptive widget

```dart
// apps/flutter/lib/src/platform/adaptive.dart
bool get isWeb => kIsWeb;
bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

// apps/flutter/lib/src/widgets/adaptive_directory_picker.dart
Widget build(BuildContext context) =>
  kIsWeb ? WebDirectoryPicker() : MacDirectoryPicker();
```

* Prefer `kIsWeb` / `Platform` branching inside widget, not two widgets duplicated
* Abstract with `PlatformPicker` interface injected via Provider (mirrors host/provider seam)

### 3. macOS specifics

* Window: `window_manager` or `bitsdojo_window` for custom chrome; persist `sidebar`/`details` widths via `SharedPreferences` (mirrors `AppFrame` store)
* Keyboard: `Shortcuts` + `Actions` with `LogicalKeySet(LogicalKeyboardKey.meta, ...)` on macOS vs `control` on web
* Menu: `PlatformMenuBar` with `PlatformMenuItem`
* Mouse: `MouseRegion` + `Listener` for hover-reveal of `DragHandle` (`AppFrame.module.css` hover)

### 4. Web specifics

* Use `flutter build web --wasm` and verify `canvaskit` assets load; check `pwa_manifest` if PWA needed (`apps/web/tests/pwa-manifest.e2e.ts` parity)
* Responsive: `LayoutBuilder` for frame, `MediaQuery` for window — see `responsive-web-to-flutter`
* SSE fallback: `EventSource` polyfill vs `fetch` streaming chunk

### 5. Verify matrix

```sh
flutter build web --no-pub && flutter build macos --no-pub
flutter test -d integration_test --platform chrome  # web
flutter test -d integration_test --platform macos   # desktop
```

Widget tests pump with `debugDefaultTargetPlatformOverride = TargetPlatform.macOS` and `kIsWeb` override via `debugIsWeb` test binding where needed.

## Anti-patterns

* Do not use `dart:html` directly — use `package:web` or `flutter` abstractions so macOS still compiles
* Do not hardcode `Meta` only — web `Ctrl` vs macOS `Meta` must branch
* Do not ship two apps — one Flutter project with `platform` conditionals
