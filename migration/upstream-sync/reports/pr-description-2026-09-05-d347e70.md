# UPSTREAM SYNC REPORT

Upstream:
cd5ef814 → d347e703

Commits:
984

Files:
4641

API changes:
1

Breaking APIs:
0

Stream changes:
0

Flutter affected files:
4

P0:
2

P1:
1

P2:
1

React/Flutter parity:
FAIL

Tests:
PENDING (run pnpm upstream:verify)

Manual verification required:
YES — P0/breaking changes present

---

## sync branch

`sync/upstream/YYYY-MM-DD-d347e703`

Do not auto-resolve conflicts in:
- apps/flutter/**
- migration/**
- API/stream contracts

## flutter parity branch

`flutter-sync/YYYY-MM-DD-d347e703`

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
