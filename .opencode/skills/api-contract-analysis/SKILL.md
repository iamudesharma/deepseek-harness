---
name: api-contract-analysis
description: Exact API contract diff — endpoint, request/response, model, error, auth, transport. Breaking is semantic, not name-only.
---

# API Contract Analysis — Shared Skill

## Scope

Inspect **current** upstream and **previous** upstream revisions:

```
packages/api/**   packages/client/**   packages/host/**   packages/preset/**
packages/interaction/**   packages/core/**   packages/typert/**   packages/session/**   packages/settings/**   packages/workspace/**   packages/llm/**   packages/subagent/**   packages/goal/**   packages/skill/**   packages/credentials/**
```

## Extraction

For each `TypertRemoteService` (`extends TypertRemoteService` or `bindTypertRemote(this, serviceKey, {namespace})`) and `@Remote`/`@RemoteScope` method:

- `namespace` (wire), `serviceKey` (Cordis), `operation` (`exportName ?? method`), `endpoint` (`<namespace>/<operation>`), `wireEndpoint` (`/api/<endpoint>`), `method`, `exportName`, `mode` (`unary` vs `stream`), `sourceFile:line`
- `request schema` (first arg type, `request` vs `args` wrapper), `response schema` (return type, `RemoteResult<T>` unwrap), `argument names`, `required fields`, `optional fields`, `enums`, `return types`, `errors` (`TypertRemoteFailure` codes), `authorization` (`none`/`browser`/`bearer-full`/`bearer-limited`), `transport` (`typert/unary`|`typert/stream`|`websocket`)

Emit:

```
migration/upstream-sync/api-contract-current.json
migration/upstream-sync/api-contract-previous.json
```

via `pnpm upstream:diff` / `scripts/upstream-sync/api-extractor.ts` (`git grep -l @Remote` + `git show`).

## Diff taxonomy (each is a distinct record)

- `added` / `removed`
- `dot-to-slash` (e.g., `settings.describe → settings/describe` — explicit, not blanket)
- `namespace-rename` / `operation-rename`
- `pluralization` (e.g., `subagent/list → subagents/list`)
- `split` (e.g., `llm.providers → llm/listProviders + llm/listConfigurableProviders` — **not** a rename)
- `merged`
- `request-wrapper` (`payload: {...}` vs `payload: {args: {...}}` vs `payload: {request: {...}}`)
- `response-wrapper` (`{items}` vs `{value}` vs `{_list}`)
- `required-field` / `optional-field` / `enum` / `type` / `nesting`
- `transport` (`unary → stream`) / `authorization` (`browser → bearer-full`)

Each `api-diff.json` entry has:

```
id, kind, oldEndpoint, newEndpoint, oldValue, newValue, severity (P0/P1/P2/P3), description, sourceFiles
```

**Breaking** = `P0` (endpoint removed/renamed without compat, wrapper change, type narrowing, required field added, auth tightened). **Never** assume a rename is only a rename — compare `endpoint` + `request` + `response` + `model` + `event` + `state` + `stream` + `auth` + `tests` separately (Phase 19).

## Severity

- **P0:** removes/renames `session/*`, `settings/*`, `workspace/*`, `remote/*` without fallback; breaks `session/page throughSeq` or `settings/describe` List shape.
- **P1:** degraded feature (e.g., `llm/listConfigurableProviders` split, new optional field ignored).
- **P2:** additive (new endpoint, new optional enum value) — may be `AUTO-APPLY` if tests green.
- **P3:** informational (doc, new `P3` endpoint not used by Flutter).

## Host authority

Host schema (`packages/**`) is authoritative. React is the **behavioral** reference; Flutter must adapt. Do not invent compat shims.

## Workflow

```
pnpm upstream:diff   # populates api-diff.json + file-classification.json
pnpm upstream:report # full parity + registry
```

Every entry → `change-registry.json` with `migrationStatus: Detected→Audited→Planned→Migrated→Integrated→Verified→Ignored(reason)`.
