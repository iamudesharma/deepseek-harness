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
5

P1:
1

P2:
0

React/Flutter parity:
FAIL

Tests:
PENDING (run pnpm upstream:verify)

Manual verification required:
YES — P0/breaking changes present

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
