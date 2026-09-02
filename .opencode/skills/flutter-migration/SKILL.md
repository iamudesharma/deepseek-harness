---
name: flutter-migration
description: Minimal correct Flutter parity change — Host + React verified, focused tests, no duplicate runtime/store, no speculative abstraction.
---

# Flutter Migration — Shared Skill

## Authority

- **Host** is authoritative for APIs, streams, models, events.
- **React** (`packages/client/**`, `apps/web/**`) is the behavioral reference.
- Flutter (`apps/flutter/lib/**` + `apps/flutter/test/**`) adapts.

Do not redesign working architecture. Do not create duplicate `session store`, `workspace store`, `runtime`, or second DSH.

Respect existing: `ConnectionTarget`, `ConnectionClient`, `ConnectionController`, `RemoteMuxClient`, `LiveSync`, `SessionManager`, `Riverpod`, `SecureTokenStore`.

## Process (per feature)

1. **Read Host contract** (`migration/upstream-sync/api-contract-current.json`, `stream-contract-current.json`, `packages/**` source).
2. **Read React reference** (`react-contract.json`, `packages/client/**`, `apps/web/**`).
3. **Read Flutter current** (`flutter-contract.json`, `apps/flutter/lib/**` call site).
4. **Read existing tests** (`apps/flutter/test/**`).
5. **Identify first divergence** (contract → implementation, not symptom).
6. **Implement minimal correct parity change** (single behavior, no speculative abstraction).
7. **Add regression tests** (unit/widget/contract).
8. **Verify:** `pnpm upstream:impact` → `pnpm upstream:verify` (`flutter analyze`, `flutter test`, `verify-flutter-tracker --check`).

## Examples

- **React:** `settings/describe` returns `{namespaces: List<{ns,schema,value,revision}>}`.
  **Flutter:** `SettingsScope._refreshNow` assumed `Map`.  
  → Fix `_refreshNow` to handle `List<Map>`, `Map`, fallback `doc[ns]`; add `namespace` getter + `mutateBatch` fence.

- **React:** `session/page` requires `throughSeq` from `session/follow` snapshot.  
  **Flutter:** invents `-1` sentinel.  
  → `getSessionHistory` requires `throughSeq` (`LiveHistory.acceptedSeq`), no probe.

- **Host:** `subagent/list → subagents/list` (pluralization).  
  **Flutter:** no subagent consumer yet.  
  → Audit `tool_models.dart`, `subagent_provider.dart`; no blanket rename.

## Branch discipline

- `sync/upstream/YYYY-MM-DD-<shortsha>` = Host sync only.
- `flutter-sync/YYYY-MM-DD-<shortsha>` = Flutter compat only (no unrelated product/UI work).

## Verification

- `flutter analyze`, `flutter test` (focused P0/P1), `verify-flutter-tracker --check`, `pnpm build` / `pnpm typecheck` as applicable.
- Contract tests when `api-diff.json` or `stream-diff.json` changes.

## Anti-patterns

- Blanket `replaceAll('.', '/')` across Dart files.
- Fabricated `throughSeq`/`cursor`.
- Synthetic `session`/`workspace` data when Host has it.
- Duplicate `Riverpod` stores or second event loop.
