---
name: sync-upstream
description: Permanent upstream sync + Flutter parity — detects upstream/master drift, audits Host/API/stream/React/Flutter, builds parity matrix, merges Host, implements Flutter compat, verifies, commits, pushes, PR (single entry point).
agent: upstream-sync-orchestrator
---

# /sync-upstream — Permanent Upstream Sync

**You are invoking `upstream-sync-orchestrator`. Do not implement the workflow yourself; delegate and sequence per that agent.**

## Repositories

- **Fork (our):** `https://github.com/iamudesharma/deepseek-harness.git` (`master` — Host fork; `feat/*` / `flutter-sync/*` for Flutter)
- **Upstream:** `https://github.com/deepseek-ai/deepseek-harness.git` (`master`)
- **Flutter:** `apps/flutter/`
- **Host authoritative:** sessions, workspace, tools, filesystem, model providers, credentials, agent runtime, session event log, projections, approvals, questions, queues, commands (Node+Cordis+DSH)
- **React:** `packages/client/**` + `apps/web/**` is the behavioral reference

## What the orchestrator will do (13 phases)

**Do not run write-capable agents concurrently.** Read-only auditors (`api-contract-auditor`, `stream-contract-auditor`, `react-reference-auditor`, `flutter-parity-auditor`) may run concurrently; `flutter-implementation-agent` only after audit aggregation; `verification-agent` after implementation.

- **A.** Observe repository state: `git remote -v`, `git status --porcelain` (dirty → report, never `reset --hard`), read `migration/upstream-sync/upstream-state.json`.
- **B.** Fetch upstream: `git fetch upstream --prune`, `git rev-parse upstream/master` vs `origin/master`, `behindBy`/`aheadBy`/`merge-base`.
- **C.** Analyze upstream changes: `git log` + `git diff --name-status --find-renames` + `scripts/upstream-sync/classifier.ts` (`HOST/API/CORE`…).
- **D.** Host/API/streams: `pnpm upstream:diff` → `api-contract-current.json`/`-previous.json`/`api-diff.json` + `stream-contract-*.json`/`stream-diff.json` (each entry `OLD/NEW/TYPE/SEVERITY/SOURCE/REACT IMPACT/FLUTTER IMPACT/RECOMMENDED ACTION`; no blanket dot→slash).
- **E.** React: `react-contract.json` (surfaces from `packages/client/ui-*`, `apps/web`).
- **F.** Flutter: `flutter-contract.json` (`apps/flutter/lib/**` call sites).
- **G.** Compatibility matrix: `pnpm upstream:report` → `parity.json` (`PASS/MISSING/OUTDATED/INCOMPATIBLE/REMOVED/UNKNOWN`), `flutter-impact.json` (`P0/P1/P2/P3`, `affectedFiles`), `change-registry.json` (`Detected→Verified`), `reports/YYYY-MM-DD-upstream-sync.md`.
- **H.** Merge Host: `sync/upstream/YYYY-MM-DD-<shortsha>` from `origin/master`, `git merge upstream/master` (classify conflicts: `SAFE HOST-ONLY` may resolve; `SEMANTIC API`/`FLUTTER`/`MIGRATION FILE`/`SECURITY` → stop, never overwrite `apps/flutter/**` or `migration/**`).
- **I.** Resolve safe conflicts only (docs/metadata, non-breaking additive schema when tests prove compat).
- **J.** Flutter sync branch: `flutter-sync/YYYY-MM-DD-<shortsha>` from `sync/...` (only Flutter compat changes).
- **K.** Implement Flutter parity: delegate to `flutter-implementation-agent` **one feature at a time**, `P0` first, then `P1`, then `P2`; every `UNKNOWN` classified; minimal correct change per `flutter-migration` skill (no duplicate runtime/store, respect `ConnectionTarget`/`ConnectionController`/`LiveSync`).
- **L.** Verify: delegate to `verification-agent` → `pnpm upstream:verify` (`pnpm build`, `typecheck:contracts-ready`, `lint`, `flutter analyze`, `flutter test`, `flutter build web --wasm --release`/`macos --debug`/`apk --debug`, `verify-flutter-tracker --check`); focused `P0`/`P1` tests; classify failures `PRODUCT/TEST/ENVIRONMENT/UPSTREAM/FLUTTER/TOOLCHAIN` with evidence.
- **M.** Commit/push/PR: regenerate manifests, `parity.json` `Verified` gate, commit (`chore(sync): …`), push `sync/...` + `flutter-sync/...`, create PR only when `create_pr:true` (body from `reports/pr-description-*.md`), **never auto-merge**.

## Safety (and host/connection/model specials)

See `upstream-sync` skill: no blanket dot→slash, no fabricated `throughSeq`/`cursor`/`payload`, no parsing human errors, no duplicate stores, no silent semantic resolution, no `reset --hard`/`clean -fd` without authorization, no secrets in reports. When `session/follow`/`session/page`/`throughSeq` changes, audit **all** consumers (`message_provider.dart`, `trajectory_provider.dart`, `tool_models.dart`, `subagent_provider.dart`, `sidebar.dart`, `session_workspace_services.dart`). When `workspace/*` changes, compare `workspace/list`+`follow`+`session/list`+`projections`+`workspaceId`/`sessionIds`/`cwd`/`title` + React grouping vs Flutter.

## CLI that backs you

You (the orchestrator) delegate to the permanent tooling in `migration/upstream-sync/`:

```
pnpm upstream:check   # drift?
pnpm upstream:diff    # api-diff.json + stream-diff.json + file-classification.json
pnpm upstream:impact  # parity + flutter-impact
pnpm upstream:report  # full report + change-registry + dated markdown
pnpm upstream:sync    # sync branch + pr-description
pnpm upstream:verify  # gates
```

Existing state is preserved (`upstream-state.json` etc.; dated reports never overwritten).

## Inputs you control

- `create_pr` (default `true` via `workflow_dispatch` inputs; `schedule` → report + artifacts, optional branch/PR)
- `verify` (default `true`)

## Security

Sanitize `API keys`, `Bearer tokens`, `cookies`, `WS tickets`, `device private keys`, `passwords` from reports.

## After you finish

Return `agents created`, `skills created`, `command created`, `workflow changes`, `CLI integration`, `current upstream SHA`, `current fork SHA`, `detected changes`, `P0/P1/P2/P3/UNKNOWN`, `React/Flutter parity`, `test results`, `limitations`. Do **not** merge upstream, modify Flutter production code, or bump versions during initial infra validation.

---

**Run now.** Fetch `upstream/master`, compare `origin/master` vs `upstream/master`, run `pnpm upstream:report` (read-only), regenerate `migration/upstream-sync/reports/latest.md`, and summarize `WHAT/WHY/WHERE/WHICH FLUTTER CODE/WHICH REACT CODE/WHAT NEEDS TO BE IMPLEMENTED/WHAT VERIFIED/WHAT NEEDS HUMAN REVIEW`.
