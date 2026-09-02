---
name: stream-contract-auditor
description: Audits stream contracts — remote.mux, $events, session/follow/control, workspace/follow, heartbeat/generation/reconnect/auth/frames — detects added/removed/reshaped/security changes.
mode: subagent
skills:
  - upstream-sync
  - stream-contract-analysis
---

# Stream Contract Auditor (Read-Only)

## Inspect

- `remote.mux` (`REMOTE_STREAM_MUX_PATH`, `RemoteStreamMuxServer`, `packages/api/gateway/src/stream-server.ts`)
- `$events` / `$events/result` (`REMOTE_EVENT_STREAM_ENDPOINT`, `REMOTE_EVENT_RESULT_ENDPOINT`, `packages/api/gateway/src/stream-protocol.ts`)
- `session/follow` / `session/control` (`packages/api/session-controller/**`, `packages/session/**`)
- `workspace/follow` (`packages/api/workspace-controller/**`, `packages/workspace/**`)
- `feed/follow` if present
- Any successor/removed stream

Plus `packages/client/connection/**`, `packages/host/remote-access/**`, `packages/host/webserver/**`.

## Extract (via scripts/upstream-sync/stream-extractor.ts)

Per rev emit:

```
migration/upstream-sync/stream-contract-current.json
migration/upstream-sync/stream-contract-previous.json
```

Fields:

- `endpoints[]` (`name`, `path` `/api/events.mux`, `/api/events.host`, `session/follow`, kind `websocket`/`sse`)
- `frames[]` (`RemoteEventInvocationFrame`, `RemoteEventReadyFrame`, `RemoteEventEmitFrame`, `RemoteEventCancellationFrame`, `TypertRemoteEventFrame`, `ServerRequest`, `RemoteEventHostInfo`)
- `features` (`heartbeatMs` 30000, `reconnect` jittered backoff, `generation` connection+stream, `authentication` browser cookie + bearer + ws-ticket single-use, `errorCodes` NOT_FOUND/INTERNAL/UNAUTHORIZED/FORBIDDEN)

## Compare

Produce `stream-diff.json` (`id, kind, field, oldValue, newValue, severity, description`):

- `endpoint` added/removed/renamed
- `open payload` (ticket, `clientId`, `agentId`)
- `ready` frame (`host.home`, `clientId`, `generation`)
- `streamId`/`eventId`/`clientId` semantics
- `waterfall` schema / `result`/`outcome` schema / `cancel`
- `heartbeat` / `reconnect` / `generation` / `auth` / `error codes`
- `frame` added/removed/reshaped

**Never** consider a stream compatible merely because the endpoint name stayed the same. Path-stable payload/shape change is still `P0`/`P1`.

## Severity

- **P0:** endpoint removed/renamed, `ready`/`emit` frame reshaped, `ws-ticket`/`bearer` auth tightened, generation semantics changed → Flutter `ConnectionController` + `RemoteMuxClient` break (401→`needsReauth`, generation rotation, `abortEventStreams`).
- **P1:** new frame, new error code, heartbeat change.
- **P2/P3:** additive/informational.

## Flutter coupling

Flutter `ConnectionController` owns `host.describe + both streams` handshake, `events.mux`/`events.host` `wss://…?ticket=` , generation, `suspend`/`resume`. Any change → audit `apps/flutter/lib/src/core/connection/**`.

## Outputs

- `stream-contract-current.json`, `stream-contract-previous.json`, `stream-diff.json`
- `change-registry.json` entries (`category: STREAM`)

## Commands

```
pnpm upstream:diff   # stream-diff.json
pnpm upstream:report # stream endpoints table
```

Read-only; orchestrator aggregates before `flutter-implementation-agent` runs.
