# Agent Note: Migration rework v1.1 — honest tracker contract

Status: implemented

[English](2026-08-21-migration-rework-v1.1.md)

## Problem

The React → Flutter migration tracker reported 75/75 `Verified`, but the verification criteria could not support that claim. Migration, integration, and verification were collapsed into one status field that any agent could advance, so screens were promoted on existence while runtime contracts were never proven: the live session pump required a refresh to show assistant output while `api.connection` and `screen.conversation` read `Verified`; `ui-slots`, `modules`, `ui-brand-official`, projections, pending interactions, compaction, and streaming had no tracker rows at all; and at least one source mapping was wrong (`component.ui-primitives.Markdown` pointed at `TerminalBlock.tsx`). The stated gate `pnpm run verify-flutter-tracker --check` did not exist, so the process could not enforce even its own written contract.

## Decision

Rework the migration program on an enforceable contract (spec: `docs/superpowers/specs/2026-08-21-migration-rework-v1.1-design.md`; plan: `docs/superpowers/plans/2026-08-21-migration-rework-v1.1.md`):

1. **Lifecycle** becomes `Not Started → Audited → In Progress → Migrated → Integrated → Verified`. `Migrated` means structurally complete with package-level tests; `Integrated` means real Harness services/events wired without production synthetic substitution; `Verified` means independent Gatekeeper-reviewed evidence.
2. **Write authority is partitioned**: Auditor writes `Audited`, Package Migration writes `Migrated`, integration-stage agents write `Integrated`, and only the Migration Gatekeeper writes `Verified` or demotions. The Tracker Agent performs atomic bookkeeping of decisions already made and never determines correctness.
3. **The gate is real**: `scripts/verify-flutter-tracker.ts` (+ vitest spec) validates schema enums, path existence, status rules (integration points, evidence bundles, live-mode adapter declarations, legacy blocks), and cross-references; `--check` for every edit, `--strict` (≥1 Verified path) for completion claims.
4. **Parity is multi-state** (`not-applicable|missing|partial|pass|fail`) across visual/behavior/runtime/streaming/reconnect plus per-platform dimensions — booleans could not represent "UI present, streaming missing".
5. **Evidence lives outside the tracker**: test output, replay fixtures/diffs, parity reports under `migration/parity-reports/`. A `parityCheck: pass` field is a claim, never proof; the Gatekeeper must not infer from tracker fields.
6. **Synthetic fallback policy**: forbidden in `live` runtimeMode, allowed as fixtures in `replay`, declared `adapter-of:` adapters only in `offline`.
7. **All 75 legacy rows demoted to `Audited`** with `legacyVerification` blocks preserving prior evidence and demotion reason, so genuinely complete items can be re-promoted quickly under the new gates without pretending unproven claims were proven.
8. **M0 re-audit** produced 11 inventories under `migration/audit/` covering packages, runtime services, slots, API contracts, events, conversation nodes, primitives, platform, dependencies, plugin lifecycle, and interactions — scope explicitly beyond `packages/client` (extensions client runners, interaction, boot, web). The audit added 37 rows (112 total) and corrected the Markdown mapping.

## Alternatives considered

- **Fresh v2 tracker file**: rejected — two ledgers to reconcile invites drift; the existing file extended in place keeps one source of truth.
- **Fresh 13-agent build per the original directive letter**: rejected — ~60% overlap with existing agents/skills would recreate the duplicate-framework problem the directive itself prohibited; existing roles evolved instead.
- **Keeping booleans for parity**: rejected — the actual state ("conversation UI visually present, connection partial, streaming missing") is inexpressible in booleans, which is how the false baseline happened.

## Consequences

Migration status is now mechanically checkable (`pnpm run verify-flutter-tracker --check`) and completion claims require `--strict` plus Gatekeeper approval backed by external evidence. The cost: every previously "Verified" item must re-earn its status through the new gates, so short-term progress metrics look worse before they become trustworthy. The Flutter implementation work itself (live connection pump, session runtime, ConversationNode assembly) remains future work under P0; this change rebuilt the measurement system, not the app.
