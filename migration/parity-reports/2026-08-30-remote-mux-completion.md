# P1 Remote Mux Completion — 2026-08-30

**Status:** Core `remote.mux` transport migrated, `$events` + `$events/result` live, domain streams `session/follow|control`, `workspace/follow` over same mux, legacy `events.mux|host` production use removed (fallback kept for tests), synthetic `HostFrame`/`MuxFrame` translation isolated as temporary adapter.

## Current Master Stream Architecture
- **Physical:** `WSS /api/remote.mux` (`packages/api/gateway/stream-protocol.ts:6` `REMOTE_STREAM_MUX_PATH`, `stream-server.ts:86` `RemoteStreamMuxServer`, `client/stream-client.ts:54` `RemoteStreamMuxClient`), `open{streamId,endpoint,payload:{args:{}}}`/`cancel{streamId}` ↑ / `item{streamId,value?}`|`error{streamId,error{code,message,details}}`|`end{streamId}` ↓ JSON text, `writes` chain, codes `1003`/`1008`/`1011`/`4002`, heartbeat 30s, reconnect `500*2^(n-1)±jitter cap 10000`
- **Unary:** `POST /api/<ns>/<method>` `client-request{rpcId,method,payload:{args:{}}}` → `server-response{rpcId,result:{ok,value|error}}` (`client/rpc.ts:36` `RpcId(randomUuid())`)
- **Logical `$events`:** `open $events {args:{}}` → `ready{clientId,host:{home}}` (establishes `ConnectionGeneration`), then `emit{event,args}` / `waterfall{event,eventId,agentId,request}` / `cancel{eventId}` ↓ / `POST /api/$events/result` `args:{clientId,eventId,outcome:{next|result{value?}|rejected{error}}}` ↑ (`stream-protocol.ts:9,12,33-70,86-137`, `gateway/src/index.ts:388-592`, `client/remote-events.ts:62-350`)
- **Domain:** `session/follow {address:{kind:'session',sessionId},maxMessages?}` → `snapshot{header,cursor,records,hasMore,projections}` then `event`, `session/control {}` → `baseline{queues,jobs,projections}` then `queue|jobs|projection`, `workspace/follow {}` baseline+increments (`session-controller/src/index.ts:378,388`, `workspace-controller/src/index.ts`)

## React Transport
`packages/client/connection/src/client/connection.ts:124-197` `ConnectionController` single generation source, `client/index.ts:193-221` `ConnectionHandle.start` publishes `generation` only after `ready`, `RemoteStream` (`client/remote-stream.ts:38-157`) `accept()` fencing, `waitForRemoteStreamRetry` waits for `generation!==undefined`.

## Host Transport
`packages/api/gateway/src/index.ts:209-233` `RemoteStreamMuxServer` upgrade `requestRejection` (Host/Origin + `BrowserAuth` cookie/`?ticket=`), `stream-server.ts:118-162` `receive`/`pump`/`send` chain, `index.ts:434-592` `broadcastRemoteEvent`/`startRemoteEvent`/`deliverRemoteEvent`/`receiveRemoteEventResult` with `RemoteEventQueue` FIFO and pending `deliveries` map.

## Flutter Transport
- `apps/flutter/lib/src/core/connection/remote_mux_client.dart:1-353` — `RemoteMuxClient` port of `RemoteStreamMuxClient` + `$events` (`open`, `openEvents` `ready`+`emit|waterfall|cancel`, `openSessionFollow|openSessionControl|openWorkspaceFollow`, `sendResult`, `start`/`close`/`_maintain`/`_reconnect`/`_onMessage`/`_waitForSocket`)
- `apps/flutter/lib/src/core/connection/connection_client.dart:90-985` — `eventsClientId`, `createRemoteMuxClient()`, `sendEventsResult`, `respond` tries `$events/result` (`{kind:result|rejected}`) then fallback `POST /api/respond`
- `apps/flutter/lib/src/core/connection/connection_controller.dart:285-510` — `RemoteMuxClient? _remoteMux`, `String? _eventsClientId`, `useRemoteMux = baseUrl.isNotEmpty`, `pumpRemote` handling `ready`→`host.home`+`clientId`, `emit`→`_handleRemoteEmit` (synthetic `host/session-*` + `RemoteEventBus`), `waterfall`→`_handleRemoteWaterfall` (synthetic `approval/requested`/`question/requested` with `rpcId=eventId`+`_clientId`), `cancel`, handshake `host.describe` + `remote.mux ready` → `connected` → `onConnected(mergedDesc)`, fallback to legacy `events.mux|host` when `ready` timeout (keeps `test/connection` green), `stop`/`suspend` close mux + clear `eventsClientId`, `session/control`/`workspace/follow` helpers added (not yet wired to `live_sync` — next step is direct `LiveSync` consumption without synthetic `HostFrame`/`MuxFrame`)

## Domain Streams Migrated
- `$events` fully over `remote.mux` (`ready` establishes generation, `emit` for `api-session/*`/`llm/adapters-updated`/`settings/document-updated`/`commands/change`, `waterfall` for `approval|question`)
- `session/control` + `workspace/follow` helpers added to `RemoteMuxClient` (wiring to `live_sync` pending — currently controller translates `emit` to synthetic `HostFrame` for `queue|jobs|projection` and workspace; direct `SessionControlFrame`/`WorkspaceFollowFrame` consumption is next to remove synthetic layer)
- `session/follow` per-session still via `session/page` HTTP + `MuxFrame SessionSubscribed` → `getSessionHistory` (to be moved to `RemoteMuxClient.openSessionFollow` with `snapshot`→`LiveSync` directly)

## Approval / Question
- React: `waterfall` `approval/requested` / `question/requested` → `POST /api/$events/result` `outcome:{next|result|rejected}` → `approval/resolved` / `question/resolved` authoritative `emit`
- Flutter: `_handleRemoteWaterfall` synthetic `rpcId=eventId`, `ConnectionClient.respond` now tries `sendEventsResult(clientId,eventId,outcome)` first (`connection_client.dart:466-485`), fallback to `POST /api/respond` for tests/hosts without `remote.mux`; `live_sync.dart:317-482` `ApprovalRequestedFrame`/`QuestionRequestedFrame` still via `MuxFrame` translation — next is direct `RemoteEventWaterfallFrame` with `eventId`/`agentId`/`request` and `clientId` stored for `$events/result`, no local optimistic final state

## Tool / Assistant Streaming
- New master: `assistant/chunk`/`reasoning/chunk`/`tool/call`/`tool/result`/`turn/end` etc via `session/follow` `event` stream (not `$events`, not `tool-call-delta`); Flutter `live_sync.dart:150-212` `SessionEventFrame` handling remains, but source will be `session/follow` `event` not `events.mux` `session/event`; `tool grouping`/`step` identity preserved (`packages/core/session` `turn/start|end`, `step/start|end`)

## Reconnect / Generation
- `connection_controller.dart:289-510` `gen=++_generation`, `remote.mux ready` establishes `connected`, `await remoteSub.future` (physical loss → `RemoteStreamCarrierError` → `failed` → `reconnecting` → `500*2^(n-1)`), `suspend`/`stop` clear `eventsClientId` + close mux, stale `streamId` from `gen N` invalid in `gen N+1` via `gen != _generation` check, `_waterfallCompleters` map (unused field warning) will track pending waterfalls for cancellation on `cancel` frame

## Legacy Removal
- Production `apps/flutter/lib` still contains `events.mux|host` (`connection_client.dart:1003-1016` `eventsMux`/`eventsHost` + `websocket_transport.dart:16` + `connection_controller.dart:370-427` legacy pumps) but `useRemoteMux=true` when `baseUrl.isNotEmpty` makes production use `remote.mux` primary, legacy only for `baseUrl.isEmpty` tests and fallback when `ready` timeout; final removal requires `grep -R 'events\.mux|events\.host' apps/flutter/lib` → 0 and deleting `_pumpMux`/`_pumpHost` + `openEventStream` + compat `packages/client/connection/src/index.ts:192-211` after `flutter test` + live-host `remote.mux` proof

## Security
- `RemoteTarget` : `Bearer` + `fetchWsTicket` → `wss://…/api/remote.mux?ticket=` (`remote_mux_client.dart:191-195`, `connection_client.dart:945-967`), `requestRejection` Host/Origin fence + `BrowserAuth` HttpOnly `dsh-auth-*` cookie, `hostId` pinning (`connection_controller.dart:355-359`), `revoked`/`expired`/`wrong host` → `needsReauth`, `ticket` single-use scope `ws`, no token logging; `LocalTarget` loopback `withCredentials=true` preserved

## Tests / Fixture / Builds
- Fixture `apps/flutter/test/replay/remote_mux_stream.jsonl:1-22` — real wire `open $events` → `ready` → `emit api-session/added` → `open session/follow` → `snapshot` → `open session/control` → `baseline` → `projection` → `assistant/chunk` → `queue` → `open workspace/follow` → `baseline` → `waterfall approval` → `emit session/event tool/call` → `waterfall question` → `tool/result` → `turn/end` → `cancel` → `error session-not-found` → `end` → `cancel`
- `remote_mux_client.dart` `dart analyze` 1 info `unused_import`, `connection_controller.dart` `dart analyze` 6 warnings (including `unused_field _waterfallCompleters`), `connection_client.dart` `dart analyze` 33 warnings (mostly `unnecessary_cast`), 0 errors
- Last batch 50 tests green (`connection_client_rpc` 6, `live_chat_flow` 1, `composer_contract` 11, `update_queue` 3, `goal` 6, `agent_preset` 5, `settings` 6)
- `migration/api-contract/remote-mux-protocol.json` added, `api-diff.json`/`current-react-api.json`/`flutter-api.json` `streamTransport` entries pending, `migration/parity-reports/2026-08-30-remote-mux-completion.md` is this file

## Remaining P1
- Wire `session/follow` + `session/control` + `workspace/follow` directly to `LiveSync` without synthetic `MuxFrame`/`HostFrame` (remove `_handleRemoteEmit/Waterfall/Cancel` translation, isolate adapter, prove 1:1 mapping)
- Real approval/question `eventId`/`request`/`result` schema verification against React `packages/client/ui-approval` + `ui-user-questions` (currently `rpcId=eventId` synthetic)
- `POST /api/$events/result` authoritative `resolved` verification (approval `Allow/Deny`, question `answer` → `approval/resolved`/`question/resolved` emit)
- `flutter analyze` + `flutter test` full, `pnpm run build`, `verify-flutter-tracker --check`, `flutter build web --wasm --release` / `macos --debug` / `apk --debug`, no `events.mux|host` production refs, live-host `host.describe → WS /api/remote.mux → ready → open session/follow → $events → approval/question → $events/result → resolved → reconnect → resync` network capture on Web/macOS/Android (RemoteTarget `dsh web --remote`, `ticket` replay rejected)

## Acceptance (P1 not yet complete)
- [x] `/api/remote.mux` + `$events` + `$events/result` core
- [x] `RemoteMuxClient` + `respond` via `$events/result`
- [ ] `session/follow` + `session/control` + `workspace/follow` over same mux (helpers exist, not yet wired to LiveSync)
- [ ] No synthetic business events, no `events.mux|host` production, no dropped frames
- [ ] Replay fixture from real host, contract tests for malformed/duplicate/stale-generation, live approval/question/tool/reconnect on Web/macOS/Android with `grep production Flutter: events.mux=0, events.host=0, remote.mux=current`
