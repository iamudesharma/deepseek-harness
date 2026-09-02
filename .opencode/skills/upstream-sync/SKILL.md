---
name: upstream-sync
description: Permanent upstream synchronization rules — Host authoritative, React behavioral reference, Flutter adapts, no blanket dot-slash, no fabricated cursors.
---

# Upstream Sync — Shared Skill

## Mandatory rules

1. **Upstream:** `https://github.com/deepseek-ai/deepseek-harness.git` (`master`)
2. **Fork:** `https://github.com/iamudesharma/deepseek-harness.git` (`master`)
3. `master` is Host synchronization responsibility; Flutter synchronizes separately.
4. Host is authoritative for APIs, streams, models, events, auth.
5. React (`packages/client/**`, `apps/web/**`) is the behavioral reference.
6. Flutter (`apps/flutter/**`) adapts to current Host contract; never becomes a second DSH runtime.
7. **Never blanket replace dot → slash.** Each `settings.describe → settings/describe` is an explicit migration (`api-diff.json` `dot-to-slash`).
8. **Never fabricate request fields** — compare `request`/`response`/`model`/`event`/`state`/`stream`/`auth` per spec Phase 19.
9. **Never fabricate cursors.** `session/page` requires authoritative `throughSeq` from `session/follow` snapshot (`LiveHistory.acceptedSeq`); no synthetic `-1` sentinel.
10. **Never parse human-readable server errors as protocol data.**
11. **Never silently discard an upstream change.** Every change → `migration/upstream-sync/change-registry.json` (`Detected→Audited→Planned→Migrated→Integrated→Verified→Ignored (reason)`).
12. **UNKNOWN requires explicit classification** — blocks final parity.
13. **P0 blocks final parity** (runtime-breaking); **P1** feature-breaking; **P2** compat risk; **P3** informational.
14. **Security changes require review** (`credentials`, `auth`, `remote-access`, `browser-credentials`).
15. **Stream protocol changes require contract analysis** (`remote.mux`, `$events`, `session/follow`, `session/control`, `workspace/follow`, heartbeat, generation, reconnect).
16. **Request changes require model/provider audit.**
17. **Response changes require model/provider audit.**
18. **Event changes require LiveSync audit.**
19. **UI behavior changes require React/Flutter parity audit.**
20. **No release/version change during synchronization.**

## Machine-readable state

Maintain (never destroy history; dated reports):

```
migration/upstream-sync/
  upstream-state.json
  api-contract-current.json / api-contract-previous.json / api-diff.json
  stream-contract-current.json / stream-contract-previous.json / stream-diff.json
  react-contract.json
  flutter-contract.json
  flutter-impact.json
  change-registry.json
  parity.json
  file-classification.json
  reports/YYYY-MM-DD-upstream-sync.md
```

## CLI

All phases are executable via the permanent tooling (see `packages/AGENTS.md`):

```
pnpm upstream:check   # Phase 0-1: upstream drift?
pnpm upstream:diff    # Phase 2-4: API/stream diff
pnpm upstream:impact  # Phase 7-8: Flutter impact
pnpm upstream:report  # Phase 9-10: full report + registry
pnpm upstream:sync    # Phase 11-12: sync/upstream/YYYY-MM-DD-<sha> + flutter-sync/... + pr-description
pnpm upstream:verify  # Phase 13-14: build/typecheck/verify-flutter-tracker/flutter analyze
```

## Branch model

```
upstream/master
  ↓  (fetch + merge, no auto-resolve for apps/flutter/**, migration/**, contracts)
our/master (Host fork)
  ↓  (validated)
flutter integration branches (e.g., feat/conversation-gen-ai-ui, flutter-sync/YYYY-MM-DD-<sha>)
```

`sync/upstream/YYYY-MM-DD-<shortsha>` = Host sync; `flutter-sync/YYYY-MM-DD-<shortsha>` = Flutter compat only.

## Safety

**AUTO-APPLY:** docs, generated metadata, formatting, genuinely additive schema when tests prove compat.

**REVIEW REQUIRED:** endpoint rename, removal, split, wrapper, response shape, stream, auth, model type, event semantics.

**NEVER AUTO-APPLY:** blanket replacement, guessed payload, fabricated cursor, fake fallback, security downgrade, silent conflict resolution.

## Special consumers

When `session/follow` or `session/page` changes, search **all** consumers:

```
message_provider.dart, trajectory_provider.dart, tool_models.dart, subagent_provider.dart,
permission_seat.dart, sidebar.dart, session_workspace_services.dart, LiveHistory, LiveSync
```

When `workspace/*` changes, compare `workspace/list` + `workspace/follow` + `session/list` + projections + `workspaceId`/`sessionIds`/`cwd`/`title` + React grouping vs Flutter.

When `llm/*` changes, compare provider list, configurable list, credentials, settings, `modelCatalog`, `selectModel`, reasoning effort, image capability.

## Security hygiene

Never log `API keys`, `Bearer tokens`, `cookies`, `WS tickets`, `device private keys`, `passwords`. Sanitize payloads in reports.
