# Migration Rework System v1.1 — Design Spec

Date: 2026-08-21
Status: Approved design, pending implementation plan
Scope: Migration infrastructure only (`migration/`, `.opencode/agents/migration/`, `.opencode/skills/`, `.agents/skills/`, `scripts/`). No changes under `packages/`.

## 1. Problem

The React → Flutter migration tracker reports 75/75 `Verified`, but verification criteria were too weak: items were promoted on screen existence and widget tests while runtime contracts, event flow, plugin/slot mechanics, streaming, reconnect, and backend integration were never proven. Known concrete failures:

- Live session pump incomplete: sending a prompt requires a refresh to see assistant output.
- `api.connection`, `state.session`, `screen.conversation` marked `Verified` despite the above.
- No tracker rows for `ui-slots`, `modules`, `ui-brand-official`, runtime services, projections, pending interactions, compaction, or streaming as first-class responsibilities.
- Bad source mappings in the tracker (e.g., `component.ui-primitives.Markdown` points at `TerminalBlock.tsx`).
- The stated gate `pnpm run verify-flutter-tracker --check` does not exist; the process could not enforce its own contract.

Root cause: migration, integration, and verification were collapsed into one status field that any agent could advance.

## 2. Goals

1. Separate **Audit → Migration → Integration → Verification** into distinct lifecycle states with partitioned write authority.
2. Make the migration contract **mechanically enforceable** via a real executable gate (`verify-flutter-tracker`).
3. Record parity honestly (multi-state, not boolean) across runtime, streaming, reconnect, platform dimensions.
4. Re-audit the real browser-half architecture (including packages outside `packages/client`) and rewrite the tracker from that inventory.
5. Concentrate `Verified` authority in a Gatekeeper that verifies evidence external to the tracker.

Non-goals: executing P0 implementation work (live connection pump, session runtime) in this engagement; changing any Harness backend/package; creating a second parallel tracker framework.

## 3. Tracker schema v1.1

File: `migration/migration-tracker.json` (extended in place; no v2 file).

### 3.1 Lifecycle

```
Not Started → Audited → In Progress → Migrated → Integrated → Verified
```

Definitions (binding — agents and the validator enforce them):

- `Audited`: React source fully analyzed by the React Codebase Auditor — exports, dependencies, runtime contracts, events, slots recorded; source mapping validated against the repository.
- `Migrated`: Flutter implementation exists, is **structurally complete for the audited responsibility**, and passes package-level compilation and unit/widget tests. More than "a file exists"; less than any integration claim.
- `Integrated`: real Harness services, events, state, and platform dependencies are wired (Riverpod providers, connection/session/event infrastructure, APIs); works without production synthetic substitution; `integrationPoints[]` recorded.
- `Verified`: independent Gatekeeper-reviewed evidence (tests, replay diff, parity reports) proves parity. Old `Tested` state folds into Verified's evidence requirements.

Legacy mapping: old `Analyzed` → `Audited`; old `Tested` evidence becomes part of the Verified bundle.

### 3.2 Item fields

```jsonc
{
  "id": "component.ui-primitives.Markdown",
  "category": "screen|component|route|state|api|theme|animation|dialog|form|platform|runtime|protocol|slot",
  "source": "packages/client/ui-primitives/src/MarkdownText.tsx",
  "reactPackage": "ui-primitives",
  "responsibility": "What this item owns (one sentence)",
  "flutterTarget": "apps/flutter/lib/src/widgets/primitives/markdown_text.dart",
  "replacementType": "direct|adapter|custom|not-applicable",
  "notApplicableReason": "",              // required iff replacementType == "not-applicable"
  "status": "Not Started|Audited|In Progress|Migrated|Integrated|Verified",
  "owner": "react-codebase-auditor",      // stage agent accountable for current status
  "reviewer": "migration-gatekeeper",     // set for Verified items
  "dependsOn": ["theme.tokens"],
  "blockedBy": null,
  "integrationLevel": ["ui"],             // subset of ui|state|runtime|protocol|platform
  "integrationPoints": [],                // required for Integrated+
  "runtimeMode": "live|replay|offline",   // declared execution mode of the Flutter target
  "parityCheck": {
    "visual":    "not-applicable|missing|partial|pass|fail",
    "behavior":  "not-applicable|missing|partial|pass|fail",
    "runtime":   "not-applicable|missing|partial|pass|fail",
    "streaming": "not-applicable|missing|partial|pass|fail",
    "reconnect": "not-applicable|missing|partial|pass|fail"
  },
  "platformParity": { "web": "pass", "macos": "partial" },   // values use the same five-state enum
  "tests": ["apps/flutter/test/..."],
  "e2eScenarios": [],                     // required for runtime/protocol-category items
  "evidence": {                           // required for Verified; paths point OUTSIDE the tracker
    "testsRun": "", "parityReport": "", "replayDiff": "",
    "approvedBy": "", "approvedAt": ""
  },
  "legacyVerified": false,
  "legacyVerification": {                 // present iff legacyVerified
    "previousStatus": "Verified",
    "previousEvidence": [],
    "demotedAt": "",
    "demotionReason": ""
  },
  "notes": ""
}
```

New categories `runtime`, `protocol`, `slot` exist because prior schema had no home for those responsibilities.

### 3.3 Demotion of the legacy 75

All 75 `Verified` items become `Audited` with `legacyVerified: true` and a filled `legacyVerification` block preserving previous evidence and demotion reason ("New v1.1 evidence requirements"). The Gatekeeper may re-promote quickly where prior evidence still satisfies v1.1 gates — without pretending unproven claims were proven.

### 3.4 Synthetic fallback policy

- **Production (`runtimeMode: "live"`)**: synthetic fallback forbidden.
- **Replay/test (`runtimeMode: "replay"`)**: fixtures allowed.
- **Offline/demo (`runtimeMode: "offline"`)**: synthetic adapter allowed only when explicitly declared via `replacementType: "adapter"` plus a note.

The validator rejects any `live` item whose evidence or notes indicate synthetic substitution of a Harness contract.

## 4. Write-authority model

```
React Codebase Auditor                      → writes Audited
Package Migration (+ translator skills)     → writes Migrated
Flutter Integration, Runtime Parity,
Protocol/Event, Tool Integration,
Slot/Plugin                                 → write Integrated
Migration QA, E2E Replay, Platform Agents,
Visual Parity                               → produce evidence (no status writes)
Migration Gatekeeper                        → sole writer of Verified (and demotions)
Migration Tracker Agent                     → atomic bookkeeping of decisions already made;
                                              never determines correctness, never invents status
```

Anti-circularity rule: the Gatekeeper **never infers evidence from tracker fields**. `parityCheck.streaming == "pass"` in the JSON is a claim, not evidence. Evidence lives outside the status field: test command + output, replay fixture + diff, source references, parity report files under `migration/parity-reports/`.

Parallel workstreams own disjoint tracker id prefixes; all tracker writes are atomic single-file updates.

## 5. Agent roster (18)

Location: `.opencode/agents/migration/*.yaml` (existing convention).

### 5.1 Evolved (9)

| File | New identity | Mandate delta |
|---|---|---|
| `frontend-analyzer.yaml` → renamed `react-codebase-auditor.yaml` | **React Codebase Auditor** | Produces the 11 M0 inventories; validates every source mapping against the repo; owns `Audited`; audit scope includes packages outside `packages/client`. All `$frontend-analyzer` invocation references updated in the same change |
| `flutter-migration.yaml` | Package Migration Agent | Stops at `Migrated`; structural completeness + package-level tests required |
| `react-perfect-translator.yaml` | unchanged | Component-level translation executor |
| `flutter-web.yaml` | Platform Web Agent | Adds keyboard, window, deep-link, history, focus mandates; produces platform evidence |
| `flutter-macos.yaml` | Platform macOS Agent | Same, desktop side |
| `ui-parity.yaml` | Visual Parity Agent | Explicitly gated: runs only after `Integrated`; feeds evidence |
| `migration-planner.yaml` | unchanged | Phased DAG ordered P0 → P1 → P2 |
| `migration-qa.yaml` | Migration QA (test executor) | **Loses verdict power**: generates/runs three-tier tests, emits evidence; cannot write statuses beyond flagging failures |
| `migration-tracker.yaml` | Tracker Agent | Atomic bookkeeping only |

### 5.2 New (9)

| File | Agent | Owns |
|---|---|---|
| `dependency-mapping.yaml` | Dependency Mapping Agent | npm → pub inventory; maintained-pub / adapter / custom / not-applicable decisions |
| `runtime-parity.yaml` | Runtime Parity Agent | ConnectionRuntime, SessionRuntime, WorkspaceRuntime, ProjectionRuntime, PendingInteractionRuntime in Flutter |
| `protocol-event.yaml` | Protocol/Event Agent | SessionEventMap fidelity, event ordering, mux/host frames, reconnect/generation semantics, RPC contract extraction from TS source |
| `conversation-engine.yaml` | Conversation Engine Agent | ConversationNode assembler, streaming tail, turn/step grouping, compaction, retry, snapshots |
| `tool-integration.yaml` | Tool Integration Agent | Tool lifecycle/topology/call-result pairing split from rendering; ToolPresentationRegistry; recursive subCalls |
| `slot-plugin.yaml` | Slot/Plugin Agent | DshSlotRegistry, capability registry, feature contribution lifecycle |
| `flutter-integration.yaml` | Flutter Integration Agent | Riverpod/routing/shell wiring; advances `Migrated → Integrated` |
| `e2e-replay.yaml` | E2E Replay Agent | Replays identical event streams against React and Flutter; semantic diff reports |
| `migration-gatekeeper.yaml` | Migration Gatekeeper | Sole `Verified` authority; reviews external evidence bundles; owns promotions/demotions |

## 6. Skill roster

New skills (mirrored to both `.opencode/skills/` and `.agents/skills/`, matching existing duplication convention):

1. `harness-api-contract-extraction` — extract API/RPC contracts from TS definitions into Dart; hand-invented contracts forbidden.
2. `session-eventmap-analysis` — analyze `SessionEventMap`/event streams; required-on-read semantics, ignorable envelope.
3. `stream-frame-analysis` — mux/host frame analysis, connection generations, reconnect/gap recovery.
4. `conversation-node-analysis` — ConversationNode assembly pipeline (definitions, contexts, view builders, snapshots).
5. `tool-topology-analysis` — call/result pairing, recursive subCalls, lifecycle-vs-render ownership split.
6. `slot-plugin-migration` — slot registry / capability registry migration patterns.
7. `riverpod-runtime-integration` — runtime → Riverpod wiring; no-synthetic-fallback rule.
8. `semantic-parity-replay` — replay fixture construction + React-vs-Flutter semantic diff methodology.
9. `dependency-mapping` — npm → pub decision framework.
10. `tracker-validation` — tracker schema/evidence validation; documents the `verify-flutter-tracker` gate.

Updated skills: `migration-mode` (v1.1 lifecycle, new authority model, real gate), `migration-code-review` (enforces v1.1 gates).

## 7. Executable gate: `verify-flutter-tracker`

Files: `scripts/verify-flutter-tracker.ts` + co-located `scripts/verify-flutter-tracker.spec.ts` (repo gate convention: validator + vitest spec proving each acceptance path rejects an invalid case).

`package.json`:

```jsonc
{
  "scripts": {
    "verify-flutter-tracker": "tsx scripts/verify-flutter-tracker.ts"
  }
}
```

Modes:

```sh
pnpm run verify-flutter-tracker            # validate + report
pnpm run verify-flutter-tracker --check    # CI mode: nonzero exit on any violation
pnpm run verify-flutter-tracker --strict   # additionally requires ≥1 Verified path integrity end-to-end
```

Checks (each backed by a spec case):

1. Schema validity: required fields, enum membership (status, category, replacementType, parity enums, runtimeMode).
2. `source` path exists in the repository; `reactPackage` resolves to a real package directory.
3. `flutterTarget` exists on disk once `status >= Migrated`; below `Migrated`, planned paths are allowed.
4. `notApplicableReason` non-empty iff `replacementType == "not-applicable"`.
5. Status transition validity: no skips incompatible with recorded evidence (e.g., `Verified` without `integrationPoints`).
6. `integrationPoints[]` non-empty for `Integrated`+.
7. `evidence` complete for `Verified` (all five subfields; referenced files exist).
8. Parity dimensions present and enum-valid; `runtime`/`streaming`/`reconnect` required for `runtime`/`protocol` categories.
9. `platformParity` present for screen/platform-affecting categories.
10. `e2eScenarios[]` present for `runtime`/`protocol` categories at `Integrated`+.
11. No orphan tracker ids: every `dependsOn` id exists; every `flutterTarget` file belongs to exactly one item.
12. No duplicate ids; every `owner`/`reviewer` references a known agent id from §5.
13. No `Verified` without Gatekeeper evidence (`approvedBy == migration-gatekeeper`).
14. No production synthetic fallback: `runtimeMode == "live"` items must not declare adapter substitutions of Harness contracts.
15. `legacyVerified` items carry a complete `legacyVerification` block.

Exit code 0 only when all applicable checks pass; violations print with item id + check number.

## 8. M0 re-audit

Executed by the React Codebase Auditor after the system lands. Output: `migration/audit/*.md` — eleven inventories:

1. `client-package-inventory.md`
2. `runtime-service-inventory.md`
3. `slot-inventory.md`
4. `api-contract-inventory.md`
5. `event-inventory.md`
6. `conversation-node-inventory.md`
7. `primitive-inventory.md` (validates actual exports; fixes mappings like Markdown → `MarkdownText`)
8. `platform-inventory.md`
9. `dependency-inventory.md`
10. `plugin-lifecycle-inventory.md` (modules, plugin injection/loading/lifecycle, client runner, dynamic client packages)
11. `interaction-inventory.md` (approval, ask-user, permission, plan review collaboration plane)

Audit scope — everything participating in the browser/frontend runtime, not only `packages/client`:

```
packages/client/**
packages/extensions/*client*          (cordis-client-runner, ui-cordis)
packages/api remotes surfaces
packages/interaction
packages/boot
host/browser contracts
apps/web
```

Each inventory cites real files/packages and feeds tracker rows.

Tracker rewrite procedure: add missing rows (~40+ expected: ui-slots, modules, brand-official, runtime services, projections, pending interactions, streaming, compaction, plugin lifecycle, interaction plane), fix bad source mappings, apply §3.3 demotion, regenerate `TRACKER.md`.

## 9. Completion gates

Migration completes only when ALL hold:

```
Tracker schema valid                    AND no orphan targets
AND all required React responsibilities audited
AND all required packages mapped
AND all Migrated items compile
AND all Integrated items use real Harness contracts
AND runtime parity PASS                 AND streaming parity PASS
AND reconnect parity PASS               AND interaction parity PASS
AND E2E replay PASS                     AND visual parity PASS
AND Web/macOS platform parity PASS
AND NO production synthetic fallback
AND Gatekeeper approval
```

`pnpm run verify-flutter-tracker --strict` is the mechanical floor for the first two and the evidence-shape checks.

## 10. Engagement acceptance (this spec's implementation)

1. 18 agent YAMLs valid and loadable; evolved agents' prompts encode new mandates; `frontend-analyzer.yaml` renamed to `react-codebase-auditor.yaml` with all `$frontend-analyzer` references updated.
2. 10 new skills + 2 updated skills present in both skill directories, format-consistent with existing SKILL.md files.
3. `scripts/verify-flutter-tracker.ts` + spec exist; `pnpm run verify-flutter-tracker --check` runs clean against the rewritten tracker; spec proves each check rejects an invalid case.
4. Tracker rewritten to v1.1: all 75 legacy items demoted with `legacyVerification` blocks, sources corrected, missing packages added.
5. 11 audit inventories exist under `migration/audit/`, each citing real repository files.
6. `migration-mode` and `migration-code-review` skills document v1.1; `TRACKER.md` regenerated.
7. Agent Note written per repo convention (`.agents/notes/`).
8. Repo hygiene: `pnpm run typecheck` and the new script's vitest spec pass; files end with exactly one trailing newline.

## 11. Testing plan

- `scripts/verify-flutter-tracker.spec.ts`: vitest unit tests over fixture trackers, one rejecting case per check (§7.1–15) plus passing cases; follows existing `scripts/*.spec.ts` patterns.
- Skill/agent validation: YAML parse check + frontmatter presence (can ride inside the tracker spec or a small companion spec).
- M0 inventories: verified by citation checks (every cited path exists) — enforced by the Auditor workflow, spot-checked during review.
