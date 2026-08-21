---
name: migration-mode
description: Use when entering or operating Migration Mode — systematic, incremental, trackable Flutter migration with Migration Tracker as the single source of truth. Never assume completion from build success alone.
---

# Migration Mode

Third development mode alongside Plan Mode and Build Mode, responsible for converting the web frontend into Flutter (Web + macOS) incrementally and reversibly.

## Existing workflow

* **Plan Mode** — analyze requirements, architecture, dependencies, strategy. Read-only; no major code changes.
* **Build Mode** — implement planned changes and produce working code.
* **Migration Mode** — systematically convert the existing frontend into Flutter. Analyzes the full frontend, maintains a live tracker, and migrates item-by-item with parity and test evidence.

## Entry conditions

Migration Mode starts **only after** Frontend Analysis (`$web-codebase-analysis`) has populated `migration/migration-tracker.json`:

```sh
dsh --mode migration
migration:analyze        # Frontend Analyzer Agent
migration:status         # Tracker Agent
```

If tracker is empty or stale (`Analyzed` count < file count), re-run analysis before any implementation.

## Core principle

> **Incremental, trackable, reversible — build success ≠ migrated.** Completion is tracker-determined: every screen, component, interaction, and behavior discovered during analysis must reach `Verified`.

## Tracker contract

File: `migration/migration-tracker.json` (machine) + `migration/TRACKER.md` (human projection, generated).

Schema per item:

```json
{
  "id": "component.ui-primitives.Button",
  "category": "screen|component|route|state|api|theme|animation|dialog|form|platform",
  "source": "packages/client/ui-primitives/src/Button.tsx",
  "flutterTarget": "apps/flutter/lib/src/widgets/primitives/ds_button.dart",
  "status": "Not Started|Analyzed|In Progress|Migrated|Tested|Verified",
  "dependsOn": ["theme.tokens"],
  "blockedBy": null,
  "parityCheck": {"visual": false, "behavior": false},
  "tests": ["apps/flutter/test/primitives/button_test.dart"],
  "notes": ""
}
```

Lifecycle: `Not Started → Analyzed → In Progress → Migrated → Tested → Verified`

* `Not Started` → `Analyzed`: Frontend Analyzer Agent
* `Analyzed` → `In Progress` → `Migrated`: Flutter Migration Agent (via `$flutter-feature-migration`)
* `Migrated` → `Tested`: Migration QA Agent (`$flutter-test-generation`) + Flutter Web/macOS Agents
* `Tested` → `Verified`: UI Parity Agent (`$flutter-parity-check` + `$flutter-ui-visual-check`) with `visual && behavior`

`Verified` requires **all** of: `flutter analyze`, `flutter test --coverage` (per-file 100% in scope), `flutter build web`, and parity report `PASS`.

## Mode workflow

### 1. Analyze

Run `$web-codebase-analysis` → tracker `Analyzed` + `migration/analysis.md`.

Verify: every `packages/client/**/*.{tsx,ts,css}` and `apps/web/**/*` mapped, slot graph dumped.

### 2. Plan

Migration Planner Agent → `migration/plan.md` with phased DAG and blocker list.

Phases: 0 Foundation (tokens, Riverpod, Typert Dart, `apps/flutter` scaffold) → 1 Primitives/Shell → 2 Conversation/Tool → 3 Overlays/Settings → 4 Platform/Parity.

### 3. Migrate (per item)

```
Tracker: Analyzed → In Progress
  → css-to-flutter + web-component-to-flutter + web-state-to-flutter + api-to-dart + responsive-web-to-flutter
  → flutter build web, flutter analyze
  → Tracker: Migrated
  → flutter-test-generation → Tracker: Tested
  → flutter-parity-check → Tracker: Verified (only if PASS)
```

Each change updates tracker atomically (Tracker Agent). Keep `apps/web` bootable; gate Flutter serving behind `dsh.web.flutter` flag.

### 4. Verify continuously

```sh
migration:status   # remaining / blocked / verified counts
migration:verify <id>
pnpm run verify-flutter-tracker --check  # zero orphan
```

### 5. Exit criteria

Mode exits when `Verified == total` and `migration/parity-reports/*` all PASS. Archiving moves `migration/migration-tracker.json` final snapshot to `.agents/notes/`.

## Invocation

* Agent mode prefix: `migration` (ask via `$migration-mode`)
* Tracker commands: `migration:status`, `migration:analyze`, `migration:verify`
* Review: `$migration-code-review` blocks `Verified` without evidence

## Anti-patterns blocked

* Advancing status without evidence
* Editing backend/provider logic to fit Flutter (frontend-only unless compat Config field)
* Deleting `apps/web` before `Verified == total`
* Silent skip of Analyzer when tracker stale
