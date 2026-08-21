# Migration Mode v1.1 — DeepSeek Harness → Flutter (Web + macOS)

Mode 3 of the workflow: **Plan → Build → Migration**. See skill `$migration-mode` for operational detail and the v1.1 design spec (`docs/superpowers/specs/2026-08-21-migration-rework-v1.1-design.md`) for the binding contract.

## Modes

| Mode | Goal | Mutations |
|------|------|-----------|
| Plan | Analyze requirements, architecture, dependencies | Read-only, no major code changes |
| Build | Implement planned changes | Working code |
| Migration | Rework the web→Flutter migration on the v1.1 contract | Flutter code + tracker updates + audit inventories |

## Why Migration Mode exists

The original 75/75 `Verified` baseline was unsound: migration, integration, and verification were collapsed into one status any agent could advance. v1.1 separates them — **Audited → Migrated → Integrated → Verified** with partitioned write authority, multi-state parity, evidence outside the tracker, and an executable gate.

## Tracker

* Machine: `migration/migration-tracker.json` (v1.1 schema; see `$tracker-validation`)
* Human: `migration/TRACKER.md` (generated projection)
* Audit: `migration/audit/*.md` (11 M0 inventories)
* Parity reports: `migration/parity-reports/<id>.md`

## Lifecycle

```
Not Started → Audited → In Progress → Migrated → Integrated → Verified
```

Write authority: Auditor=Audited · Package Migration=Migrated · Integration-stage agents=Integrated · **Gatekeeper only=Verified**. The Tracker Agent performs atomic bookkeeping of decisions already made.

## Quickstart

```sh
# 0. Gate (after ANY tracker edit)
pnpm run verify-flutter-tracker --check

# 1. Audit (React Codebase Auditor) — 11 inventories under migration/audit/
# 2. Plan (Migration Planner) — P0/P1/P2 DAG in migration/plan.md
# 3. Migrate one item (Package Migration Agent) — stops at Migrated
# 4. Integrate (Flutter Integration + stage agents) — records integrationPoints
# 5. Verify (QA/E2E/Platform produce evidence; Gatekeeper alone sets Verified)
pnpm run verify-flutter-tracker --strict   # completion claims require ≥1 Verified path
```

## Exit

ALL jointly: schema valid + no orphans · responsibilities audited & mapped · Migrated items compile · Integrated items use real Harness contracts · runtime/streaming/reconnect/interaction parity PASS · E2E replay PASS · visual PASS · Web/macOS parity PASS · no production synthetic fallback · Gatekeeper approval.

## Skills & Agents

* Skills: `.agents/skills/{web-codebase-analysis,css-to-flutter,api-to-dart,web-component-to-flutter,web-state-to-flutter,web-routing-to-flutter,responsive-web-to-flutter,flutter-feature-migration,platform-compatibility,flutter-parity-check,flutter-ui-visual-check,migration-code-review,flutter-test-generation,migration-mode,harness-api-contract-extraction,session-eventmap-analysis,stream-frame-analysis,conversation-node-analysis,tool-topology-analysis,slot-plugin-migration,riverpod-runtime-integration,semantic-parity-replay,dependency-mapping,tracker-validation}` (mirrored in `.opencode/skills/`)
* Agents: `.agents/agents/migration/{react-codebase-auditor,migration-planner,flutter-migration,ui-parity,flutter-web,flutter-macos,migration-tracker,migration-qa,dependency-mapping,runtime-parity,protocol-event,conversation-engine,tool-integration,slot-plugin,flutter-integration,e2e-replay,migration-gatekeeper}` + `react-perfect-translator` (mirrored in `.opencode/agents/migration/`)

Both paths loaded by `opencode` via `.opencode/opencode.json` (`skill.paths`, `agent.paths`) and by `claude` via `.claude/skills → ../.agents/skills`.
