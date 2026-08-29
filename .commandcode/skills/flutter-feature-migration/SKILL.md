---
name: flutter-feature-migration
description: Use when implementing any frontend feature in Flutter — orchestrates component, CSS, state, routing, and API sub-skills to produce idiomatic, parity-preserving Flutter widgets inside the tracker lifecycle.
---

# Flutter Feature Migration — Core Migration Skill

Convert any web UI component/feature into Flutter while preserving functionality and UX.

## When to use

* Tracker item status `Analyzed` → `In Progress` → `Migrated`
* After `web-codebase-analysis` seeded the item
* Before `flutter-parity-check` / `flutter-test-generation`

## Ordering

1. Primitives before composites (`ui-primitives` → `ui-layout` → `ui-conversation`)
2. Theme + tokens before widgets (`css-to-flutter`)
3. State stores alongside widgets (`web-state-to-flutter`)
4. API clients before consumers (`api-to-dart`)
5. Routing last within feature (`web-routing-to-flutter`)
6. Responsive tweaks throughout (`responsive-web-to-flutter`)

## Workflow

### 1. Claim tracker item

```sh
cat migration/migration-tracker.json | grep -A5 '"id": "<name>"'
# set status In Progress via Tracker Agent or manually
```

Record `dependsOn` — block if deps not `Migrated`.

### 2. Decompose with sub-skills

| Aspect | Delegate to |
|--------|-------------|
| Styling/tokens | `css-to-flutter` |
| React component → Widget | `web-component-to-flutter` |
| Zustand/store → Riverpod | `web-state-to-flutter` |
| Slot graph → GoRouter | `web-routing-to-flutter` |
| API/RPC → Dart client | `api-to-dart` |
| Breakpoints/resize | `responsive-web-to-flutter` |

### 3. Implement in `apps/flutter/`

```
apps/flutter/lib/src/features/<feature>/
  <feature>_screen.dart
  widgets/<widget>.dart
  <feature>_controller.dart  // Riverpod Notifier
  theme/<feature>_theme.dart // if needed
apps/flutter/lib/src/widgets/primitives/  // atoms
apps/flutter/lib/src/core/session/        // shared object layer
apps/flutter/lib/src/theme/dsw_tokens.dart
apps/flutter/test/features/<feature>/
```

* Use `ConsumerWidget`/`ConsumerStatefulWidget`, never raw `StatefulWidget` for shared state
* Tokens via `Theme.of(context)` / `DswTokens`, no literal colors
* Keep 1:1 source mapping for parity tool

### 4. Preserve contracts

* Export only what `apply` equivalent needs (barrel respects `Export discipline`)
* Tests use `ProviderContainer` factories, not singletons
* Business data stays in `lib/src/core`, not widget State

### 5. Advance tracker

Update `migration/migration-tracker.json`:

```json
{ "id": "...", "status": "Migrated", "flutterTarget": "apps/flutter/lib/src/features/...", "notes": "Migrated, pending tests" }
```

### 6. Hand off

Trigger `flutter-parity-check` + `flutter-test-generation`; Tracker Agent will move `Migrated → Tested → Verified` only after those pass.

## Verification before marking Migrated

* `flutter analyze` green
* `flutter test` for feature passes
* `flutter build web --no-pub` succeeds
* No `// TODO` or stub `throw UnimplementedError()` remains

## Anti-patterns

* Do not assume build success = migrated — tracker + parity decide
* Do not change backend APIs to fit widget — frontend migration only
* Do not bypass sub-skills for speed — incremental parity is reversible
