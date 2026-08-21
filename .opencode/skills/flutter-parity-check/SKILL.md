---
name: flutter-parity-check
description: Use when comparing the original web frontend with the Flutter implementation — identifies visual and behavioral differences in layout, interaction, data, and platform behavior and gates tracker status Tested → Verified.
---

# Flutter Parity Check — UI Parity Skill

Compare web vs Flutter and report deltas; gates `Migrated → Tested → Verified`.

## When to use

* After `flutter-feature-migration` marks `Migrated`
* On demand `migration:verify <item>`
* CI parity gate before `Verified`

## Sources of truth

* Web baseline: `pnpm run build && pnpm run test:web:built` snapshots, Playwright e2e `apps/web/tests/*.e2e.ts`
* Flutter candidate: `apps/flutter` build + `flutter test` goldens + `integration_test/*`
* Tracker: `migration/migration-tracker.json` `parityCheck`

## Dimensions

| Dimension | Web witness | Flutter witness | Pass criteria |
|-----------|-------------|-----------------|---------------|
| Layout | Screenshot at 1200×800, 768×800, 400×800 | Same via `integration_test` + `golden` | Pixel diff < 0.1% or approved diff |
| Behavior | `test:gui` + `test:web` user actions | `pumpWidget` + `tap`/`drag` + provider state | Same state transitions, same callback invoked |
| Data | Session event window, `session/event` stream | Dart `sessionProvider` snapshot | JSON-equivalent, `rpcId` rule intact |
| Platform | Manual / Playwright on Chrome | `kIsWeb` vs `macOS` overrides | No functional gap |

## Workflow

### 1. Collect witnesses

```sh
# Web
pnpm run build && DSH_SNAPSHOT=replay pnpm run test:web -- -t "<scenario>"
# Flutter web
flutter build web --no-pub && flutter test --update-goldens
flutter test test/goldens/<feature>_test.dart --platform chrome
```

For each tracker item with `Migrated` or `Tested`:

* Render web component via `createXXXStore().create()` fixture or real `apps/web` boot
* Render Flutter via `ProviderScope` with same fixture provider overrides

### 2. Compare

* Visual: `goldenFileComparator` + optional `pixelTest` (see `flutter-ui-visual-check`)
* Behavioral: drive identical gesture sequence (e.g., `DragHandle` drag 100px → expect `setSidebar` called with delta), compare store states
* Data: fetch `GET /api/sessions/:id/events` vs Dart `sessionProvider` list — must deserialize identically

### 3. Report

Emit `migration/parity-reports/<item>.md`:

```md
## item: component.ui-primitives.Button
Status: FAIL
- Layout: PASS (0.02% diff)
- Behavior: FAIL — hoverCard not dismissed on outside click (web: Modal dismisses, flutter: stays)
- Data: PASS
Bloccers: ["fix HoverCard dismiss"]
```

Update tracker:

```json
{ "id": "...", "status": "Tested", "parityCheck": { "visual": true, "behavior": false } }
```

Only `visual:true && behavior:true` → `Verified`.

### 4. Re-run loop

Fix flagged widget (`flutter-feature-migration` again), re-verify, update report.

## Verification

* Every `Migrated` item has a parity report before `Verified`
* No `Verified` with `behavior:false`
* CI fails if any `Migrated` item lacks report for >1 day (staleness)

## Anti-patterns

* Do not approve visual diff without inspecting — golden update requires `DSH_SNAPSHOT=refresh` analogue review
* Do not compare only screenshots — behavior (drag, focus, keyboard) must be exercised
* Do not treat build success as parity — tracker is the gate (`AGENTS.md:Core Migration Principle`)
