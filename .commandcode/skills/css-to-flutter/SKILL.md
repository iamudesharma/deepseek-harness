---
name: css-to-flutter
description: Use when converting web CSS, design tokens, and styling into idiomatic Flutter theming — maps CSS Modules, --dsw-* tokens, and global sheets to ThemeData, ColorScheme, TextTheme, and widget-level styling without literal colors.
---

# CSS to Flutter — Styling Migration Skill

Convert web styling (`packages/client/ui-theme/src/styles/`, CSS Modules, `--dsw-*` tokens) into Flutter theming.

## Sources of truth

* `docs/web-styling.md` — token and sheet authority
* `packages/client/ui-theme/src/styles/*` — global tokens `--dsw-*`
* `packages/client/*/src/**/*.module.css` — per-component semantic aliases, `clsx`
* `AGENTS.md` (root): no literal colors in feature components; tokens only

## Workflow

### 1. Extract tokens

```sh
grep -roh "\-\-dsw-[a-z0-9-]*" packages/client --include="*.css" | sort -u
cat packages/client/ui-theme/src/styles/*.css
```

Map each token to Flutter:

| Web | Flutter |
|-----|---------|
| `--dsw-bg-*`, `--dsw-surface` | `ColorScheme.surface` / `background` |
| `--dsw-text-*`, `--dsw-fg` | `ColorScheme.onSurface` / `TextTheme` |
| `--dsw-border-*`, `--dsw-divider` | `DividerTheme` / `Border` |
| `--dsw-accent-*`, `--dsw-primary` | `ColorScheme.primary` |
| Spacing scale (`--dsw-space-*`) | `EdgeInsets`, `SizedBox`, `Gap` |
| Radius / elevation | `ShapeBorder`, `Elevation` |
| Typography (`--dsw-font-*`) | `TextTheme` + `GoogleFonts`/bundled font |

Centralize in `apps/flutter/lib/src/theme/dsw_tokens.dart` and `apps/flutter/lib/src/theme/app_theme.dart`:

```dart
abstract class DswTokens {
  static const surface = Color(0xFFF8F5F0);
  static const surfaceDark = Color(0xFF1A1A1A);
  static const spaceXs = 4, spaceSm = 8, spaceMd = 16;
}
ThemeData buildLightTheme() => ThemeData(colorScheme: ColorScheme.light(...), textTheme: ...);
```

### 2. Convert CSS Modules

* Each `.module.css` file → widget-local styling: `Container.decoration`, `TextStyle`, `BoxDecoration`
* Preserve semantic aliases; do not inline literal colors — always reference `Theme.of(context).colorScheme` or `DswTokens`
* `clsx` conditional classes → Dart ternary / `if` in `build`

### 3. Responsive & layout tokens

* Grid tracks from `ui-layout/AppFrame.tsx:computeColumns` → `LayoutBuilder` + `CustomMultiChildLayout`
* Breakpoints `SIDEBAR_AUTO_COLLAPSE` → `MediaQuery` breakpoint constants in `tokens.dart`

### 4. Verify

* `flutter analyze` — no literal `Color(0x...)` outside `dsw_tokens.dart`
* Widget golden: web screenshot vs Flutter screenshot (via `flutter_parity_check`)

## Anti-patterns

* Do not copy CSS strings into Flutter (`Html` widget, `flutter_html`)
* Do not use Tailwind or component library that reintroduces literal colors
* Do not define per-widget theme — resolve through `ThemeData` extensions
