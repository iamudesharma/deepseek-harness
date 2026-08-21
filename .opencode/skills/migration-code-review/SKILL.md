---
name: migration-code-review
description: Use when reviewing migration PRs — verifies tracker completeness, parity, incremental reversibility, preservation of backend/provider logic, and Flutter idioms; blocks Verified without evidence.
---

# Migration Code Review — Migration Tracking Review Skill

Reviews migration changes for correctness, completeness, and tracker integrity.

## Sources of truth

* `migration/migration-tracker.json` — authoritative completion; build success alone never equals migrated (`AGENTS.md:Core Migration Principle`)
* `packages/client/*` + `apps/web` — web contracts being replaced
* `apps/flutter/**` — Flutter replacement
* `AGENTS.md` + `packages/AGENTS.md` + `packages/client/AGENTS.md` — Cordis, export, slot, store, theming rules
* `flutter-parity-check` / `flutter-ui-visual-check` reports

## Blocking checks (must pass for `Verified`)

1. **Tracker completeness:** every touched web file maps to tracker item; no orphan `packages/client/**/*` remains `Not Started` after its PR merges — query `grep -L` against tracker `source` fields.
2. **Status gate:** `Migrated` requires `flutter analyze` + `flutter test` + `flutter build web` green; `Verified` requires `parityCheck.visual && parityCheck.behavior` both true plus `flutter-test-generation` coverage for scope.
3. **No backend drift:** `git diff --stat` shows `apps/flutter` + `migration/*` + small `host/webserver` compat only; no `core/*`, `llm/*`, `session/*` logic changes unless tracker links the compatibility reason.
4. **Idiomatic Flutter:** tokens via `Theme`/`DswTokens`, `ConsumerWidget` for shared state, no `dart:html`, no global singleton stores, GoRouter shell not per-route AppFrame.
5. **Reversible:** `apps/web` still builds (`pnpm run build:web`); Flutter under `apps/flutter` via `dsh.web.flutter` flag does not delete web entry.
6. **Exports:** no new public barrel export without consumer; test files import `src/*` directly.

## Manual checks

* Slot → route → session scope preserved (strict vs maybe)
* Store lifecycle: dispose removes contribution (HMR-safety analogue)
* Platform branching uses `kIsWeb` / `Platform` at widget edge, not two forks
* Docs: `migration/TRACKER.md` and any changed `packages/*/README.md` updated
* Prose: `dsh-prose-standard` on all new docs/JSDoc/strings

## Procedure

```sh
git status --short --branch
pnpm --silent run change-scope --base <verified-base> --head <head>
cat migration/migration-tracker.json | python3 -c "import json,sys; t=json.load(open('migration/migration-tracker.json')); print(len(t))"
flutter analyze
flutter test --coverage --coverage --include="apps/flutter/lib/src/features/<scope>/**/*.dart"
cat migration/parity-reports/<item>.md
```

Report one inline defect per location + one PR-level synthesis; separate blockers vs suggestions.

## Anti-patterns flagged

* `throw UnimplementedError()` left after `Migrated`
* Literal `Color(0x...)` outside tokens
* `import 'dart:html'` breaking macOS
* Bypassing sub-skills (CSS→widget without token mapping)
