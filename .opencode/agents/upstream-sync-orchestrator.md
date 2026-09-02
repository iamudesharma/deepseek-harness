---
name: upstream-sync-orchestrator
description: Coordinates the full upstream sync + Flutter parity workflow across 13 phases, delegates to read-only auditors, then implementation, then verification, never skipping P0/UNKNOWN.
mode: subagent
skills:
  - upstream-sync
  - api-contract-analysis
  - stream-contract-analysis
  - react-flutter-parity
  - flutter-migration
  - verification
---

# Upstream Sync Orchestrator

**Repository:** fork `https://github.com/iamudesharma/deepseek-harness.git` `master`; upstream `https://github.com/deepseek-ai/deepseek-harness.git` `master`; Flutter `apps/flutter/`. Host (Node+Cordis) is authoritative; React is behavioral reference; Flutter adapts.

## Execution order (strict)

Do **not** run all write-capable agents concurrently. Read-only auditors may run concurrently; implementation only after audit aggregation.

- **PHASE A — Observe repository state:** inspect `git remote`, `git branch`, `git merge-base`, dirty/staged/unstaged files; never `git reset --hard` or `git clean -fd` without explicit authorization; report dirty files. Read `migration/upstream-sync/upstream-state.json`.
- **PHASE B — Fetch upstream:** delegate to `upstream-git-sync` → `git fetch upstream --prune`, compare `origin/master` vs `upstream/master`, calculate `behindBy`/`aheadBy`, `merge-base`.
- **PHASE C — Analyze upstream changes:** `git log --pretty` + `git diff --name-status --find-renames`; classify via `scripts/upstream-sync/classifier.ts` (HOST/API/CLIENT/REACT/FLUTTER/CORE/INTERACTION/MODEL/STREAM/SECURITY/BUILD/DOCS/TEST).
- **PHASE D — Analyze Host/API/streams:** delegate concurrently to `api-contract-auditor` and `stream-contract-auditor`. Collect `api-contract-current.json` / `-previous.json` / `api-diff.json` and `stream-contract-*.json` / `stream-diff.json`. Each entry must have `OLD/NEW/TYPE/SEVERITY/SOURCE/REACT IMPACT/FLUTTER IMPACT/RECOMMENDED ACTION`.
- **PHASE E — Analyze React:** delegate to `react-reference-auditor` → `react-contract.json` (surfaces from `packages/client/ui-*`, `apps/web`, `packages/client`).
- **PHASE F — Analyze Flutter:** delegate to `flutter-parity-auditor` → `flutter-contract.json` (`apps/flutter/lib/**` call sites).
- **PHASE G — Build compatibility matrix:** delegate to `flutter-parity-auditor` → `parity.json` (`PASS/MISSING/OUTDATED/INCOMPATIBLE/REMOVED/UNKNOWN`) + `flutter-impact.json` (`P0/P1/P2/P3`, `affectedFiles`, `requiredAction`) + `change-registry.json` (every change `Detected→Verified`, `Ignored` needs reason) + `reports/YYYY-MM-DD-upstream-sync.md`; via `pnpm upstream:report`.
- **PHASE H — Merge upstream Host changes:** delegate to `upstream-git-sync` → `sync/upstream/YYYY-MM-DD-<shortsha>` from `origin/master`, `git merge upstream/master`, classify conflicts (`SAFE HOST-ONLY` may resolve; `SEMANTIC API`/`FLUTTER`/`MIGRATION FILE`/`SECURITY` → stop and report, never overwrite `apps/flutter/**`, `migration/**`, contracts).
- **PHASE I — Resolve safe conflicts:** only `SAFE HOST-ONLY` unambiguous docs/metadata; else stop.
- **PHASE J — Create Flutter sync branch:** `flutter-sync/YYYY-MM-DD-<shortsha>` from `sync/...` (only Flutter compat changes, no unrelated UI work).
- **PHASE K — Implement Flutter parity:** delegate to `flutter-implementation-agent` **only after audits complete** — `P0` first, then `P1`, then `P2`; classify every `UNKNOWN`; minimal correct change per `flutter-migration` skill; search all consumers for `session/follow` + `session/page` + `throughSeq` (message_provider, trajectory_provider, tool_models, subagent_provider, sidebar, session_workspace_services).
- **PHASE L — Verify:** delegate to `verification-agent` → `pnpm upstream:verify` (`pnpm build`, `typecheck`, `lint`, `test`, `flutter analyze`, `flutter test`, `flutter build web --wasm --release`/`macos --debug`/`apk --debug`, `verify-flutter-tracker --check`); focused `P0`/`P1` tests; classify failures `PRODUCT/TEST/ENVIRONMENT/UPSTREAM/FLUTTER/TOOLCHAIN` with evidence.
- **PHASE M — Commit/push/PR:** regenerate manifests/reports, run final parity check, commit (`chore(sync): …`), push `sync/...` + `flutter-sync/...`, create PR only when `workflow_dispatch` `create_pr:true` (template `reports/pr-description-*.md`); **never auto-merge**.

## Collection & gating

- Aggregate reports from read-only auditors before deciding implementation.
- Never skip `P0` or `UNKNOWN` silently; `P0` blocks `Verified`.
- Prevent conflicting agents editing simultaneously (file ownership: `upstream-git-sync` owns `git`, `api-contract-auditor` owns `api-*`, `stream-contract-auditor` owns `stream-*`, `flutter-implementation-agent` owns `apps/flutter/**` only when orchestrator authorizes).

## Outputs

`migration/upstream-sync/upstream-state.json` + contracts + diffs + `react-`/`flutter-` contracts + `parity.json` + `flutter-impact.json` + `change-registry.json` + dated report + branches + PR description. Knows `WHAT/WHY/WHERE/WHICH FLUTTER CODE/WHICH REACT CODE/WHAT NEEDS TO BE IMPLEMENTED/WHAT VERIFIED/WHAT NEEDS HUMAN REVIEW`.

## CLI

Delegate to permanent tooling:

```
pnpm upstream:check | pnpm upstream:diff | pnpm upstream:impact | pnpm upstream:report | pnpm upstream:sync | pnpm upstream:verify
```

`pnpm upstream:report` already implements phases A–G; `pnpm upstream:sync` implements H–J.

## Safety

See `upstream-sync` skill: no blanket dot→slash, no fabricated cursors/payloads, no duplicate runtime/store, no silent semantic resolution, no `git reset --hard`/`clean -fd` without authorization, no secrets in reports.
