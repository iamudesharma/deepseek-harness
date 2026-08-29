---
name: migration-mode
description: Use when entering or operating Migration Mode v1.1 — systematically rework the Flutter migration on the honest tracker contract with partitioned write authority. Never advance status without its owning agent; never infer parity from the tracker.
---

# Migration Mode v1.1

Third development mode alongside Plan Mode and Build Mode. Converts the browser-half frontend into Flutter (Web + macOS) on an enforceable contract: the tracker is the source of truth, the executable gate enforces it, and only the Gatekeeper may call an item `Verified`.

## Entry conditions

Migration Mode v1.1 starts **only after** the React Codebase Auditor has produced `migration/audit/*.md` (11 inventories) and the tracker satisfies `pnpm run verify-flutter-tracker --check`. If inventories are missing or stale, re-run the audit before any migration work.

## Core principle

> Incremental, trackable, reversible — `Verified` means the Gatekeeper proved parity from evidence outside the tracker, not that a screen exists.

## Tracker contract

File: `migration/migration-tracker.json` (machine) + `migration/TRACKER.md` (generated projection).

Item fields (see design spec section 3.2): `id`, `category` (screen/component/route/state/api/theme/animation/dialog/form/platform/runtime/protocol/slot), `source`, `reactPackage`, `responsibility`, `flutterTarget`, `replacementType` (direct/adapter/custom/not-applicable + notApplicableReason), `status` (below), `owner`, `reviewer`, `dependsOn`, `blockedBy`, `integrationLevel` (subset of ui/state/runtime/protocol/platform), `integrationPoints` (required >= Integrated), `runtimeMode` (live/replay/offline), `parityCheck` (visual/behavior/runtime/streaming/reconnect each not-applicable/missing/partial/pass/fail), `platformParity` {web,macos}, `tests`, `e2eScenarios` (required for runtime/protocol @ Integrated+), `evidence` (testsRun/parityReport/replayDiff/approvedBy/approvedAt; complete only at Verified), `legacyVerified`/`legacyVerification`, `notes`.

Synthetic fallback policy: `live` forbids synthetic adapters; `replay` allows fixtures; `offline` allows declared `adapter-of:` adapters only.

## Lifecycle

```
Not Started → Audited → In Progress → Migrated → Integrated → Verified
```

- `Audited` — React source analyzed by the React Codebase Auditor; source mapping validated; scope expanded beyond `packages/client` (extensions, api remotes, interaction, boot, web). You alone write this.
- `Migrated` — Flutter code structurally complete for the audited responsibility and passing package-level compile + unit/widget tests (more than "a file exists").
- `Integrated` — wired to real Harness services/events/state/platform via Riverpod and extracted contracts; no production synthetic substitution; `integrationPoints` recorded.
- `Verified` — sole authority of the Migration Gatekeeper (see `migration-gatekeeper`), granted only from evidence living outside the tracker (test output, replay diffs, parity reports). Old `Tested` folds into this evidence bundle.

Write authority is partitioned: Auditor=Audited, Package Migration=Migrated, Integration-stage agents=Integrated, **only Gatekeeper=Verified**. The Tracker Agent performs atomic bookkeeping of decisions already made and never determines correctness.

## Mode workflow

### 1. Audit (React Codebase Auditor)

Run `$react-codebase-auditor` → 11 inventories under `migration/audit/` + every `source` mapping validated. The tracker lists every browser-half package and every package under `Migrated` has an honest `responsibility`.

### 2. Plan (Migration Planner Agent)

Migration Planner → `migration/plan.md` phased DAG ordered P0 (live connection, session/workspace/projection/interaction runtimes, ConversationNode assembly, streaming, reconnect, tool lifecycle, contracts) → P1 (slots/plugins, references, input triggers, subagents, plans/questions/permissions, settings semantics) → P2 (primitives polish, brand, a11y, virtualization, visual regression). Respects `dependsOn` edges and records blockers.

### 3. Migrate (per item, Package Migration Agent)

```
Audited → In Progress → Migrated
  via $css-to-flutter + $web-component-to-flutter + $web-state-to-flutter + $api-to-dart + $responsive-web-to-flutter + $react-perfect-translator
```

Stop at Migrated — never claim integration. Every change updates the tracker atomically via the Tracker Agent. Keep `apps/web` bootable; Flutter served behind `dsh.web.flutter`.

### 4. Integrate (Flutter Integration + stage agents)

Wire migrated code into the real runtime/event/slot/plugin/platform layer via `$riverpod-runtime-integration` and the protocol skills. Each item records `integrationPoints` when it reaches `Integrated`.

### 5. Verify (Gatekeeper-owned)

`$migration-qa` + `$e2e-replay` + `$flutter-ui-visual-check` + Platform Agents generate evidence in `migration/parity-reports/`. The Gatekeeper reviews the bundle outside the tracker (`parityCheck: pass` is a claim, not proof) and advances to `Verified` only when the completion gates hold.

```sh
pnpm run verify-flutter-tracker --check    # every tracker edit
pnpm run verify-flutter-tracker --strict   # completion claims: demands at least one Verified path
```

### 6. Exit criteria

All hold jointly: tracker schema valid and no orphans, every required responsibility audited and mapped, every Migrated item compiles, every Integrated item uses real Harness contracts, runtime/streaming/reconnect/interaction parity pass, E2E replay pass, visual pass, Web and macOS platform parity pass, no production synthetic fallback, Gatekeeper approval.

## Agents and skills

- Agents (18): `react-codebase-auditor`, `migration-planner`, `flutter-migration`, `ui-parity`, `flutter-web`, `flutter-macos`, `migration-tracker`, `migration-qa`, `dependency-mapping`, `runtime-parity`, `protocol-event`, `conversation-engine`, `tool-integration`, `slot-plugin`, `flutter-integration`, `e2e-replay`, `migration-gatekeeper`, `react-perfect-translator` (under `.opencode/agents/migration/` and mirrored in `.agents/agents/migration/`).
- Skills: `$web-codebase-analysis`, `$css-to-flutter`, `$api-to-dart`, `$web-component-to-flutter`, `$web-state-to-flutter`, `$web-routing-to-flutter`, `$responsive-web-to-flutter`, `$flutter-feature-migration`, `$platform-compatibility`, `$flutter-parity-check`, `$flutter-ui-visual-check`, `$migration-code-review`, `$flutter-test-generation`, `$migration-mode` plus the ten v1.1 domain skills (`$harness-api-contract-extraction`, `$session-eventmap-analysis`, `$stream-frame-analysis`, `$conversation-node-analysis`, `$tool-topology-analysis`, `$slot-plugin-migration`, `$riverpod-runtime-integration`, `$semantic-parity-replay`, `$dependency-mapping`, `$tracker-validation`).

All skills mirrored between `.opencode/skills/` and `.agents/skills/`.

## Anti-patterns blocked

- Advancing status without its owning agent; `migration-tracker` inventing correctness.
- `parityCheck: pass` in JSON without an external artifact the Gatekeeper verified.
- Editing backend/provider logic to fit Flutter (frontend-only unless a compat Config field).
- Deleting `apps/web` before joint exit criteria.
- Silent skip of the audit when the tracker is stale.
