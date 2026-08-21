---
name: tracker-validation
description: Use when reading or writing migration/migration-tracker.json — the v1.1 schema, write-authority partition, and the executable verify-flutter-tracker gate.
---

# Tracker Validation

1. Schema: statuses `Not Started -> Audited -> In Progress -> Migrated -> Integrated -> Verified`; parity dims use `not-applicable|missing|partial|pass|fail`; see the design spec section 3 for every field.
2. Write authority: Auditor=Audited, Package Migration=Migrated, Integration-stage agents=Integrated, Gatekeeper=Verified/demotions; the Tracker Agent performs atomic writes only.
3. Evidence lives outside the tracker: test output, replay diffs, parity reports; `parityCheck: pass` is a claim, never proof.
4. After ANY tracker edit run: `pnpm run verify-flutter-tracker --check` (CI mode). Completion claims additionally require `--strict`.
5. Synthetic fallback: live=forbidden, replay=fixtures allowed, offline=declared adapters only (`adapter-of:` notes).
