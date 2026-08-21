# Migration Mode — DeepSeek Harness → Flutter (Web + macOS)

Mode 3 of the workflow: **Plan → Build → Migration**. See skill `$migration-mode` for operational detail.

## Modes

| Mode | Goal | Mutations |
|------|------|-----------|
| Plan | Analyze requirements, architecture, dependencies | Read-only, no major code changes |
| Build | Implement planned changes | Working code |
| Migration | Convert web frontend to Flutter incrementally | Flutter code + tracker updates |

## Why Migration Mode exists

Flutter migration must be **incremental, trackable, reversible**. Build success alone never proves completeness; only the Migration Tracker does.

## Tracker

* Machine: `migration/migration-tracker.json` (see `$migration-code-review`)
* Human: `migration/TRACKER.md` (generated projection)
* Parity reports: `migration/parity-reports/<id>.md`

## Quickstart

```sh
# 1. Analyze (Frontend Analyzer Agent)
dsh --mode migration
migration:analyze

# 2. Plan
migration:status

# 3. Migrate one item
migration:implement component.ui-primitives.Button

# 4. Verify
migration:verify component.ui-primitives.Button
flutter analyze && flutter test && flutter build web

# 5. Status
migration:status
```

## Exit

`Verified == total` + all parity reports PASS → archive snapshot.

## Skills & Agents

* Skills: `.agents/skills/{web-codebase-analysis,css-to-flutter,api-to-dart,web-component-to-flutter,web-state-to-flutter,web-routing-to-flutter,responsive-web-to-flutter,flutter-feature-migration,platform-compatibility,flutter-parity-check,flutter-ui-visual-check,migration-code-review,flutter-test-generation,migration-mode}` (mirrored in `.opencode/skills/`)
* Agents: `.agents/agents/migration/{react-codebase-auditor,migration-planner,flutter-migration,ui-parity,flutter-web,flutter-macos,migration-tracker,migration-qa,dependency-mapping,runtime-parity,protocol-event,conversation-engine,tool-integration,slot-plugin,flutter-integration,e2e-replay,migration-gatekeeper}.yaml` (mirrored in `.opencode/agents/migration/`)

Both paths loaded by `opencode` via `.opencode/opencode.json` (`skill.paths`, `agent.paths`) and by `claude` via `.claude/skills → ../.agents/skills`.
