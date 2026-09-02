---
name: stream-contract-analysis
description: Stream contract diff for remote.mux, $events, session/follow, generation/reconnect, heartbeat, auth.
---

# Stream Contract Analysis — Shared Skill

## Streams under audit

- `remote.mux` (`REMOTE_STREAM_MUX_PATH`, `RemoteStreamMuxServer`)
- `$events` / `$events/result` (`REMOTE_EVENT_STREAM_ENDPOINT`, `REMOTE_EVENT_RESULT_ENDPOINT`)
- `session/follow` + `session/control`
- `workspace/follow`
- `feed/follow` (if present)
- Any successor/removed stream

## Extraction

From `packages/api/gateway/src/stream-protocol.ts`, `packages/api/gateway/src/stream-server.ts`, `packages/client/connection/**`, `packages/host/**`:

- `endpoint` (`/api/events.mux`, `/api/events.host`, `session/follow`, …)
- `open payload` (ticket, `clientId`, `agentId`)
- `ready` frame (`ready { host: {home}, clientId, generation }`)
- `streamId` / `eventId` / `clientId` semantics
- `waterfall` schema, `result`/`outcome` schema
- `heartbeat` (`websocketHeartbeatIntervalMs` 30000)
- `reconnect` (jittered backoff, generation increment)
- `generation` (`connection generation` + `stream generation`)
- `auth` (`browser cookie` + `bearer full` + `ws-ticket` single-use)
- `error codes` (`NOT_FOUND`, `INTERNAL`, `UNAUTHORIZED`, `FORBIDDEN`, `TypertGatewayErrorCode`)

Emit:

```
migration/upstream-sync/stream-contract-current.json
migration/upstream-sync/stream-contract-previous.json
migration/upstream-sync/stream-diff.json
```

via `scripts/upstream-sync/stream-extractor.ts` (`git ls-tree` filtered + `git show`).

## Diff kinds

- `added` / `removed` / `renamed` (path changed)
- `changed` (heartbeat, frame shape, auth, generation)
- `frame added/removed` (`RemoteEventInvocationFrame`, `RemoteEventReadyFrame`, `TypertRemoteEventFrame`, `ServerRequest`)

Each `stream-diff.json` entry: `id, kind, field, oldValue, newValue, severity, description`.

**Never** consider a stream compatible merely because the endpoint name stayed the same. Compare payload shape, generation semantics, and auth. A path-stable frame change is still `P0`/`P1`.

## Severity

- **P0:** endpoint removed/renamed, auth tightened, generation semantics changed (Flutter `connection_controller.dart` + `remote_mux_client.dart` will break).
- **P1:** new frame, new error code, heartbeat change.
- **P2:** additive frame field (compat risk).
- **P3:** doc-only.

## Flutter coupling

Flutter `ConnectionController` owns `host.describe + both streams` handshake, `events.mux`/`events.host` WebSocket (`ws://`/`wss://?ticket=`), generation rotation, `abortEventStreams()`, `fetchWsTicket()` single-use, `needsReauth` on 401/403. Any stream change → audit those files.

## Commands

```
pnpm upstream:diff   # stream-diff.json
pnpm upstream:report # markdown + stream endpoints table
```
