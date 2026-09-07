# UPSTREAM SYNC REPORT

Upstream:
cd5ef814 → 49a606bc

Commits:
692

Files:
3839

API changes:
3

Breaking APIs:
3

Stream changes:
0

Flutter affected files:
6

P0:
0 (verified: session/page throughSeq, settings List; subagents pluralization ignored — no Flutter consumer)

P1:
0 (verified: remote.mux ticket fetch + 401 needsReauth)

P2:
5 (desktop open-dialog RPCs NotApplicable on mobile: session/openWorkspacePath, settings/openSettingsDocument|replace|update)

React/Flutter parity:
PASS 51 / MISSING 5 P2 / UNKNOWN 5 (2 arch verified + 3 messageFeedback expected via typed face) — no P0 MISSING

Tracker:
112/112 Verified 2026-09-03 (all 9 remaining implemented: trajectory modes, agent-preset opener, deliverables select, goal CAS, message-feedback live remote + screen, skill epoch, subagent metrics, user-questions chain + precedence fix, workflow-run nav)

Tests:
flutter test across 9 plugin suites green (29+13+9+11+20+16+20+37+6); analyze 0 errors; verify-flutter-tracker OK 112 + strict OK

Manual verification required:
NO — P0/P1 verified; P2 MISSING intentionally NotApplicable for mobile

---

## sync branch

`sync/upstream/YYYY-MM-DD-49a606bc`

Do not auto-resolve conflicts in:
- apps/flutter/**
- migration/**
- API/stream contracts

## flutter parity branch

`flutter-sync/YYYY-MM-DD-49a606bc`

Contains only Flutter compatibility changes.

## Commands

```
pnpm upstream:diff
pnpm upstream:impact
pnpm upstream:report
pnpm upstream:verify
```

## Safety

AUTO-APPLY: docs, generated metadata, non-breaking additive fields, formatting
REVIEW REQUIRED: endpoint rename, wrapper change, stream/auth changes
NEVER AUTO-APPLY: blanket dot-to-slash, fake wrappers, synthetic cursors, duplicate stores
