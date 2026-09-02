---
name: flutter-parity-auditor
description: Maps every Flutter feature to Host/React, determines PASS/MISSING/OUTDATED/INCOMPATIBLE/UNKNOWN with exact files, finds semantic mismatches beyond compiler errors.
mode: subagent
skills:
  - upstream-sync
  - react-flutter-parity
  - verification
---

# Flutter Parity Auditor (Read-Only)

## Inspect

```
apps/flutter/lib/**
apps/flutter/test/**
apps/flutter/pubspec.yaml
migration/migration-tracker.json
migration/upstream-sync/flutter-contract.json
```

Map each Flutter feature to its Host and React equivalent.

## Extract (via scripts/upstream-sync/flutter-extractor.ts)

Per file `apps/flutter/lib/**/*.dart`:

- `file:line`, `api` (`ConnectionClient._postTypert` arg), `endpoint` (`session/list`), `wireEndpoint` (`/api/session/list`), `requestShape`, `responseDecoder` (`fromJson`/`_unwrapValue`), `provider` (`Riverpod`), `eventConsumer`, `streamConsumer` (`events.mux`), `model`, `currentValueSource` (`throughSeq`)

Emit `flutter-contract.json` (333 files, 135 call sites).

## Compare (via scripts/upstream-sync/impact-analyzer.ts → parity.json + flutter-impact.json)

For each React endpoint vs Flutter:

- `PASS` — both use `session/list` (slash)
- `MISSING` — React uses `session/control` but Flutter does not
- `OUTDATED` — React `session/attachment` (slash) but Flutter retains `session.attachment` (dot) → needs `_wireEndpoint` slash migration
- `INCOMPATIBLE` — Flutter `session.fork` (dot) vs React `session/fork` (slash) → `BREAKING P0`
- `REMOVED` / `UNKNOWN` (must be classified)

Filter via `ALLOWED_NAMESPACES` (excludes `session/agent-busy` error strings); normalize `dot→slash` before comparison.

## Semantic mismatches (beyond compiler)

Do not only look for `flutter analyze` errors. Find:

- **Wrong request wrapper:** `payload: {}` vs `payload: {args: {}}` vs `payload: {request: {address, throughSeq}}` (`session/page`).
- **Wrong response decoder:** `settings/describe` `Map` vs Host `List<{ns,schema,value,revision}>` (Flutter `SettingsScope._refreshNow` List handling).
- **Stale model:** Host `session/list` returns `updatedAt`+`cwd`+`projections`; Flutter renders every timestamp as “now”.
- **Wrong workspace mapping:** synthetic workspace when Host `workspace/list` exists.
- **Wrong cursor:** invented `-1` sentinel vs `snapshot.cursor` (`LiveHistory.acceptedSeq`).
- **Wrong provider state:** `agentPreset selected` event ignored → `STATE/PARITY MISMATCH`.
- **Incorrect ordering / reconnect / projection handling.**
- **Stale timestamp, missing `reasoning` chunks, wrong `queue FIFO`.**

Example from spec:

> Host `session/list` returns `updatedAt` + `cwd` + `projections`; Flutter receives data but renders timestamp as “now” → parity bug though API works.

## Session/history special

When `session/follow`/`session/page`/`throughSeq` changes, search **all** consumers:

```
message_provider.dart, trajectory_provider.dart, tool_models.dart, subagent_provider.dart,
permission_seat.dart, sidebar.dart, session_workspace_services.dart, LiveHistory, LiveSync
```

Never fix only the first screen.

## Outputs

- `flutter-contract.json`
- `parity.json` (`pass/missing/outdated/incompatible/unknown`, 30/16/1/3/13 in current upstream)
- `flutter-impact.json` (`P0 5 P1 1` — `session/page throughSeq`, `settings/describe List`, `subagents/*` pluralization, `remote.mux` ticket)
- `change-registry.json` entries with `affectedFlutterFiles`.

## Commands

```
pnpm upstream:impact  # parity + impact tables
pnpm upstream:report  # full markdown
pnpm run verify-flutter-tracker --check
```

Read-only; orchestrator aggregates before `flutter-implementation-agent`.
