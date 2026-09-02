---
name: react-flutter-parity
description: Feature-by-feature React vs Flutter comparison — API, request/response, state, event, stream, fallback, current-value, ordering, localization, lifecycle.
---

# React/Flutter Parity — Shared Skill

## Principle

React (`packages/client/**`, `apps/web/**`, `packages/api/**`) is the **behavioral reference**. For every feature, record the React owner vs Flutter owner.

## Per-feature matrix

For each important surface (especially `session list/create/page/follow/control`, `workspace`, `models`, `agent presets`, `permissions`, `queue`, `tools`, `trajectory`, `subagents`, `approvals`, `questions`, `attachments`, `settings`, `commands`):

| Field | React | Flutter |
|---|---|---|
| Host API | `session/list` etc. | `ConnectionClient._postTypert` / `callMethod` |
| Request | `{address, throughSeq}` shape | Dart `requestShape` |
| Response | `{items, records, projections}` | `fromJson` / `_unwrapValue` |
| Model | `SessionSummary`, `HistoryEntry`, `SettingsNamespaceView` | `SessionSummary`, `HistoryEntry`, `SessionProjectionsBlock` |
| State | `use*Store`, `liveSync`, `projection` | `Riverpod` provider |
| Current-value | `snapshot.cursor` (`throughSeq`) | `LiveHistory.acceptedSeq` or `snapshot.cursor` |
| Event | `session/event`, `settings/updated` | `events.mux` consumer |
| Stream | `events.mux`/`events.host`/`session/follow` | `RemoteMuxClient` + `ConnectionController` generation |
| Error handling | `TypertRemoteFailure` | `RemoteMethodException` / `RemoteAuthException` |
| Fallback | `retry`, `reconnect` | `backoff`, `needsReauth` |
| Ordering | `updatedAt desc`, `queue FIFO` | same |
| Timestamp | `updatedAt` ISO | same (not “now”) |
| Localization | `locale-owned` | `locale-owned` |
| Lifecycle | `useEffect` + `onOpen` handshake | `onOpen` + generation |

## Extraction

- **React:** `scripts/upstream-sync/react-extractor.ts` → `react-contract.json` (surfaces from `packages/client/ui-*`, `apps/web`, `packages/client`; known surfaces `session.list`, `session.page` with `throughSeq`, `settings.describe` List handling).
- **Flutter:** `scripts/upstream-sync/flutter-extractor.ts` → `flutter-contract.json` (333 Dart files, 135 call sites; each has `file:line`, `api`, `wireEndpoint`, `requestShape`, `responseDecoder`, `provider`, `eventConsumer`, `streamConsumer`, `model`, `currentValueSource`).

Compare via `scripts/upstream-sync/impact-analyzer.ts` → `parity.json`:

```
PASS | MISSING | OUTDATED | INCOMPATIBLE | REMOVED | UNKNOWN
```

Dot→slash is **OUTDATED/INCOMPATIBLE**, not PASS. Example: Flutter `session.attachment` (dot) vs React `session/attachment` (slash) → `INCOMPATIBLE P0`. `subagent/* → subagents/*` → `pluralization P0`.

## Architectural mismatches (semantic, not compiler)

Detect even when code compiles:

- Wrong `request wrapper` (`{args:}` vs `{request:}`)
- Wrong `response decoder` (`List` vs `Map` for `settings/describe`)
- Stale `model` (`message timestamp` rendered as “now” while Host returns `updatedAt`)
- Wrong `workspace mapping` (synthetic workspace when Host has `workspace/list`)
- Wrong `cursor source` (Fabricated `-1` sentinel vs `snapshot.cursor`)
- Wrong `provider state` (`agentPreset selected` event ignored → `STATE/PARITY MISMATCH`)
- Incorrect `ordering`/`reconnect`/`projection` handling

## Output

`migration/upstream-sync/parity.json` + `migration/upstream-sync/flutter-impact.json` (`P0`/`P1`/`P2`/`P3`, `affectedFiles`, `requiredAction`, `status`).

`pnpm upstream:impact` and `pnpm upstream:report` render the tables.

## Severity

- **P0:** blocks runtime (cursor, auth, endpoint 404)
- **P1:** feature broken/degraded (tool card, queue, trajectory)
- **P2:** compat risk (new optional field ignored)
- **P3/UNKNOWN:** informational — **UNKNOWN must be classified** before merge.
