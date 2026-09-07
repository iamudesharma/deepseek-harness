# API Contract Resync — React ↔ Host ↔ Flutter Reconciliation

**Date:** 2026-08-30
**Author:** OpenCode (Muse Spark) — 7-agent parallel reconciliation + manual evidence pass
**Baseline commits:**
- `master` at `cd5ef8148158c3a752a658978873241fdf8e2bbc` (Merge PR #3248 release dsh-0.1.2-alpha.1)
- Flutter branch `feat/conversation-gen-ai-ui` at `4f2038e343 fix: update tracker reactPackage for moved runtime sources`
- Merge-base `cd5ef81481` — Flutter branch contains current master (`git branch --contains` shows both)
- Working tree dirty: `apps/flutter/lib/src/core/connection/connection_client.dart`, `packages/client/connection/src/api-request-trust.ts`, `packages/client/connection/src/browser-auth.ts`, `packages/client/connection/src/index.ts`, `packages/client/connection/src/rpc-host.ts`, `packages/host/webserver/src/index.ts` (6 files, 261 insertions, 22 deletions) — partial slash-migration + compat stubs already applied, not yet committed.

---

## 1. Current Architecture (2026-08-30 master)

### 1.1 Three planes, one Gateway

```
React component
  → ctx.remote.<namespace>.<method>(args, signal)    // Typert Client facade (api/gateway/client/index.ts: ClientRemoteService)
  → connection.rpc.call('/api', '<ns>/<method>', {args}, signal) // client/connection/client/rpc.ts: createWebConnectionRpc POST
  → fetch POST https://host:port/api/<ns>/<method>   // {type:'client-request', rpcId, method, payload:{args:{...}}}
  → node:http WebServer prefix /api → HostConnectionService.sharedFetchHandler → TypertGateway.intercept('/api', claimsEndpoint, dispatchRpc)
  → Gateway.prepareInvocation strict descriptor lookup (typert/registry) → Reflect.apply(service[impl], decodedArgs)
  ← {type:'server-response', rpcId, result:{ok:true,value}|{ok:false,error:{code,message,details}}}
  ← ConnectionRpcResult validated → RemoteResult to caller
```

Streaming variant replaces `fetch POST` leg with `WSS /api/remote.mux` multiplex (`api/gateway/stream-protocol.ts: REMOTE_STREAM_MUX_PATH='/api/remote.mux'`).
Event forwarding rides same mux as logical stream `$events` (`REMOTE_EVENT_STREAM_ENDPOINT='$events'`) with uplink `POST /api/$events/result` for waterfall outcomes.

**Invariant:** `endpoint = "<namespace>/<method>"` (slash, not dot). `payload = {args:{<wireField>:JsonValue}}` exactly one key `args` (gateway/index.ts:945-959). `ENDPOINT_SEGMENT_PATTERN /^[A-Za-z0-9_$.-]+$/`.

### 1.2 Host WebServer is a dumb carrier

`packages/host/webserver/src/index.ts: WebServer` exposes `register(prefix|exact)`, `registerUpgrade`, `registerFallback`, `tapIndex`. No harness semantics. `/api` handler is owned by `client-connection` plugin (`packages/client/connection/src/index.ts: apply`), which fences via `isTrustedApiRequest` + `BrowserAuth` then delegates to `HostConnectionService`.

### 1.3 Legacy ApiProxy is gone

`packages/host/apiproxy` does **not exist** in current tree (R3 §0). `git log --oneline -- packages/host/apiproxy` shows final removals: `4f00a8b82a refactor(api): remove ApiProxy package`, `ce3391e280 retire migrated unary routes`, `fd7f2065b2 remove settings and credentials RPCs`. Its contract is now `api/gateway` + `client/connection`.

### 1.4 Trust & auth sequence (R2 §7)

1. WebServer longest-prefix dispatch
2. `isTrustedApiRequest` (loopback ∪ trustedHosts, sec-fetch-site, Origin)
3. `BrowserAuth.isAuthenticated` else 401
4. CORS preflight 204 with `Access-Control-Allow-*`
5. `rpcFetchHandler` validates `content-type: application/json`, `clientRequestSchema`, `method===endpoint`
6. Gateway `claimsEndpoint` strict local OR hasSeen OR SRC fallback

---

## 2. API Layers (classification required before any dot→slash change)

Per the task's critical warning, each API is classified by owner, not by name:

| Owner | Wire carrier | Example | How to identify |
|---|---|---|---|
| **A. Typert Remote (unary)** | `POST /api/<ns>/<method>` via Gateway | `session/prompt`, `settings/describe`, `llm/listProviders` | Has `@Remote` decorator on `TypertRemoteService` subclass (`packages/llm/llm/src/index.ts:461 @Remote listProviders`, `packages/api/session-controller/src/index.ts:208 @Remote('list')`) |
| **B. API Proxy** | — | *none* — retired 2026-08-10 (`docs/api-gateway.md`) | No business Remote uses it; remaining `connection.rpc.handle(channel≠/api)` path exists but unused |
| **C. Session/event streaming** | `WSS /api/remote.mux` logical streams + `$events` | `session/follow`, `session/control`, `workspace/follow`, `$events`, `$events/result` | `@Remote({mode:'stream'})` or `TypertGatewayService` upgrade for `/api/remote.mux` |
| **D. HostFrame/MuxFrame protocol** | `WSS /api/remote.mux` + legacy compat `WS /api/events.mux|host` | `session/event`, `session/queue`, `host/session-added`, `approval/requested` | `packages/host/apiproxy/src/api/events.ts` mirrored in `apps/flutter/lib/src/core/api/frames.dart` |
| **E. Local-only** | in-process | `connection.generation`, `remote.$stream` wrapper, `remote.$on` registration | `packages/client/connection/src/client/index.ts:57 Local Observable`, never hits HTTP |
| **F. Deprecated/removed** | 404 | `llm.providers`, `llm.models`, `session.models`, `host.pickDirectory`, `host.*`, `goal.*` singular | No `@Remote` with that name in current HEAD; git log shows removal commit |

**Rule:** Do NOT perform global `\.` → `/` replacement. Each API must be classified first, then verified against current React + Host source.

---

## 3. React Inventory (Agent R1 — exhaustive, 56 logical operations)

Full table is in `migration/api-contract/current-react-api.json` (56 entries covering all namespaces). Highlights:

- **Session:** 14 unary + 2 streams — `session/list|search|create|selectModel|modelCatalog|canOpenWorkspacePath|openWorkspacePath|rename|fork|prompt|attachment|updateQueue|cancel|page` + `session/follow` + `session/control` (`packages/api/session-controller/src/index.ts:208-391`).
- **Workspace:** 6 unary + 1 stream — `workspace/create|rename|delete|insertBefore|insertSessionBefore|archiveSession` + `workspace/follow` (`packages/api/workspace-controller/src/index.ts:34`).
- **DirectoryPicker:** 3 unary — `directoryPicker/pick|list|createDirectory` (`packages/api/workspace-controller/src/directory-picker.ts:33`).
- **Settings/Credentials:** 7 + 3 — `settings/describe|canOpenAgentPresetDirectory|update|replace|mutate|openSettingsDocument|openAgentPresetDirectory` + `credentials/describe|set|unset` (`packages/api/settings-controller/src/index.ts:93` + `credentials.ts:59`).
- **LLM:** 3 — `llm/listProviders|listConfigurableProviders|discoverModels` (`packages/llm/llm/src/index.ts:461,533,620`).
- **Other:** `goals/edit|pause|resume|complete|clear|create`, `agentPresets/list|read|copy|deletePreset|select`, `commands/list|execute`, `fileReferences/list`, `skills/list`, `sessionReferenceResolver/candidates`, `messageFeedback/list|put|delete`, `subagents/list|prompt|interruptByParent`, `pluginInventory/list`, `remote/pair|devices|revoke|refresh|ws-ticket`, `remote.notifications/register|unregister`, `dynamicCordisRunner/*` (12).
- **Streams:** `session/follow`, `session/control`, `workspace/follow`, plus gateway-internal `$events` + `$events/result` + `remote.mux` upgrade.
- **Transport:** All unary `POST /api/<ns>/<method>` with `{args:{...}}`; streams over `WSS /api/remote.mux`.

React calls are via `ctx.remote.<ns>.<method>` (ClientRemoteService) or ObjectLayer `ctx.sessions` / `ctx.workspaces` which internally fan to same Remotes. See R1 report for per-file line numbers.

---

## 4. Host Inventory (Agent R3 — source-verified, ~54 unary + 4 streams)

Authoritative list in `migration/api-contract/current-react-api.json` (same as React — this file is React=Host because React's generated client is derived from Host's `@Remote` descriptors). Key files:

- `packages/llm/llm/src/index.ts:461 @Remote listProviders`, `:533 @Remote listConfigurableProviders`, `:620 @Remote('discoverModels') remoteDiscoverModels`
- `packages/api/session-controller/src/index.ts:208-391` all session methods
- `packages/api/settings-controller/src/index.ts:121-230` settings + `credentials.ts:85-115`
- `packages/api/workspace-controller/src/index.ts:42` workspace + `directory-picker.ts:44`
- `packages/host/remote-access/src/remote-service.ts:46 @Remote('pair')`, etc.

Protocol constants: `REMOTE_STREAM_MUX_PATH='/api/remote.mux'`, `REMOTE_EVENT_STREAM_ENDPOINT='$events'`, `REMOTE_EVENT_RESULT_ENDPOINT='$events/result'` (all in `packages/api/gateway/src/stream-protocol.ts:5,9,12`).

---

## 5. Flutter Inventory (Agent F1/F2 + manual grep — 52 calls)

Full table in `migration/api-contract/flutter-api.json` (52 entries with file:line, wire string literal, status). Summary by file:

**`ConnectionClient` direct (`apps/flutter/lib/src/core/connection/connection_client.dart:183-906`):**
- 15 dot-methods that should be slash: `session.list|history|prompt|create|cancel|updateQueue|attachment`, `settings.describe|mutate`, `credentials.describe|set|unset`, `workspace.list|create|insertBefore|insertSessionBefore|rename|delete`, `session.search`, `skill.list`, `agentPreset.list|select`, `host.describe`, `remote.pair|ws-ticket|refresh` — all `DOT_SHOULD_BE_SLASH`
- 2 correctly slash after dirty diff: `llm/listProviders`, `llm/listConfigurableProviders`, `session/modelCatalog` — PASS
- 3 deprecated/removed still present: `llm.providers` (fallback join), `llm.models`, `session.models` — REMOVED
- 3 payload-shape issues: `session.selectModel` (special `request` wrapper), `llm.discoverModels` (needs `settingsNs`+`request`), `session.history` (payload `{sessionId,beforeSeq}` vs host `{sessionId,cursor?,limit?}`)

**`WorkspacesService` (`apps/flutter/lib/src/core/services/session_workspace_services.dart:72-152`):**
- `host.pickDirectory|listDirectory|createDirectory` → should be `directoryPicker/*` — WRONG_NAMESPACE_AND_DOT
- `workspace.list|create|archiveSession` via callMethod — DOT

**`Plugins` :**
- `agent_preset_provider.dart:93 agentPreset.read DOT singular → agentPresets/read slash plural`
- `agent_preset_provider.dart:107 agentPreset.copy DOT → agentPresets/copy`
- `agent_preset_provider.dart:118 agentPreset.remove DOT → agentPresets/deletePreset`
- `goal_control.dart:97 goal.edit DOT singular → goals/edit plural`
- `commands/command_service.dart:230 session.prompt DOT → session/prompt`
- `reference/reference_plugin.dart:124 fileReferences/list SLASH correct PASS`, `:151 sessionReferenceResolver/candidates PASS`
- `commands/command_plugin.dart:74 commands/list SLASH correct PASS`
- `app_plugins.dart:387 commands/execute SLASH correct PASS`
- `sidebar.dart:1894 session.rename DOT → session/rename`, `:1909 session.fork DOT`, `:1933 workspace.archiveSession DOT`
- `devices_screen.dart:42 remote.devices DOT → remote/devices`, `:300 remote.revoke DOT`

**Event/stream layer (`apps/flutter/lib/src/core/connection/connection_client.dart:931-1106` + `websocket_transport.dart`):**
- `eventsMux() → /api/events.mux`, `eventsHost() → /api/events.host` — LEGACY (host compat stub accepts but does not pump frames) — should be `/api/remote.mux` with Typert stream protocol + `$events`.
- `respond() → POST /api/respond` — LEGACY, should be `POST /api/$events/result` via Typert.

**Provider/service map (F2):** 38 Riverpod providers scanned (full inventory in F2 report). Critical joins:

| Area | Flutter Provider | Cache | Invalidation | Current-value source | Event source |
|---|---|---|---|---|---|
| Sessions | `sessionsProvider` Notifier + `sessionBootstrapProvider` Future | normalized `Map<SessionId,SessionSummary>` | `host/session-added|removed|status` → `setAll` ; `onConnected` re-list | `sessionByIdProvider`, `currentSessionProvider` | `HostFrame` + `MuxFrame session/event` |
| Workspace | `workspaceListProvider` Future + `WorkspacesService` | `Async<List<WorkspaceView>>` | manual invalidate + `host/workspace-*` frames | `workspaceListProvider` | `HostFrame workspace-*` |
| Models | `modelDirectoryProvider.family` StateNotifier per session | `ModelDirectoryState.groups` | manual `load()` only (no push) | `modelDirectoryProvider(id)` | pull only |
| Providers/Credentials | `modelsSettingsControllerProvider` Notifier | `ProviderRow[]` | `llm/adapters-updated`, `settings/document-updated`, `credentials/reference-updated` | `modelsStore.rows` | mux/host forwarded events |
| AgentPreset | `agentPresetListProvider` Future | `AgentPresetRoster` | manual (no auto on `agent-preset/selected`) | `agentPresetListProvider` | `session/event agent-preset/selected` |
| Permissions | `permissionSelectProvider.family` StateProvider | `PermissionSelect?` | `session/projection key=permissions` | `permissionSelectProvider(id)` | mux `session/projection` |
| Queue/Jobs | `queueProvider`/`jobsProvider` StateNotifier | whole-snapshot Map | `session/queue` / `session/jobs` push | `queueProvider[id]` | mux `session/queue|jobs` |
| Approvals/Questions | `approvalsProvider`/`pendingQuestionsProvider` | `Map<sid,Pending*>` | `approval/question requested|resolved` | `approvalsProvider[id]` | mux answerable frames + `respond()` |

Full per-area deep map in `migration/parity-reports/...` §F2.

---

## 6. Events / Stream / Projection Inventory (F3)

- **MuxFrame:** 10 discriminants (`session/event`, `session/subscribed`, `approval/requested|resolved`, `question/requested|resolved`, `session/queue|jobs|projection`, `stream/error`) — `apps/flutter/lib/src/core/api/frames.dart:122-419` — parity intact.
- **HostFrame:** 9 discriminants (`host/session-added|removed|status`, `host/agent-error`, `host/workspace-*`, `host/remote-event`, `stream/error`) — `frames.dart:422-651`.
- **SessionEventMap:** 38 known types (12 core + 26 merged) — `packages/core/session/src/types.ts:221-325` + `known-event-types.ts:18-70` — no rename.
- **Forwarded RemoteEvents:** 17 allowlisted (`packages/api/remotes/src/remote-events.ts:16-31`): `agent-preset/selected` (emit), `approval/request` + `user-questions/request` (waterfall), `api-session/*` (5), `commands/change`, `credentials/reference-updated`, `llm/adapters-updated`, `settings/document-updated`, etc. — unchanged.
- **Projection:** `SessionProjectionFrame {sessionId, key, value, seq}` higher-seq-wins (`projection_store.dart:34-77`).
- **RPC envelope:** `RpcId` mint initiator, echo responder (`rpc_envelope.dart`, `connection_client.dart:26-39`), `POST /api/respond` vs new `POST /api/$events/result` — **moved** (P1).
- **Conclusion:** No upstream event name/shape change detected (F3 §10). All event names identical TS ↔ Dart.

---

## 7. API Rename Map (every suspected change proved with source)

| OLD Flutter (pre-sync) | CURRENT Host (master) | Reason (commit / source) | Verdict |
|---|---|---|---|
| `POST /api/llm.providers` (dot) | `POST /api/llm/listProviders` + `POST /api/llm/listConfigurableProviders` (two slash endpoints, split) | `packages/llm/llm/src/index.ts:461 @Remote listProviders` + `:533 @Remote listConfigurableProviders`; `git log 4f00a8b82a remove ApiProxy` + `ce3391e280 retire migrated unary routes` — ApiProxy `llm.providers` route deleted, replaced by two Typert Remotes. Not a simple dot→slash but a semantic split (live vs configurable). | **DO NOT** replace with `llm/providers`; use **two** new endpoints and join (`_joinProviderDirectory`). Flutter dirty diff already does this — keep. |
| `POST /api/llm.models` (dot) | `POST /api/session/modelCatalog` (slash, different namespace) | Old `llm.models` advised catalog was removed; new catalog is `session/modelCatalog` via `SessionController.buildModelCatalog` (`packages/api/session-controller/src/index.ts:248 @Remote('modelCatalog')`). Commit `2d4393d842 refactor(api): expose remaining domain remotes`. | **DO NOT** keep `llm.models`; Flutter still calls it (`connection_client.dart:698`) — will 404. Replace with `session/modelCatalog` (global, no sessionId). |
| `POST /api/session.models` (Flutter custom per-session) | `POST /api/session/modelCatalog` (global) + `llm/listProviders` | Same as above — Flutter invented `session.models {sessionId}` which never existed on Host; Host catalog is global. | Remove `sessionModels(sessionId)` wrapper. |
| `POST /api/settings.describe` (dot) → `POST /api/settings/describe` (slash) | `POST /api/settings/describe` | `packages/api/settings-controller/src/index.ts:121 @Remote describe` namespace `settings`, method `describe` => endpoint `settings/describe` per Analyzer rules. Commit `fd7f2065b2 remove settings and credentials RPCs`. | **DO** replace dot→slash, same namespace/method. |
| `POST /api/workspace.list` (dot) → but Host has no `workspace.list` | `POST /api/workspace/create|rename|...` (Host `workspaceController` has 6 methods but no `list`) | `packages/api/workspace-controller/src/index.ts` lists only `create|rename|delete|insertBefore|insertSessionBefore|archiveSession|follow`. `workspace.list` may be implicit registry read or compat stub. Host `rpc-host.ts:163` compat stub returns `{workspaces:[]}` for `workspace.list` DOT. | **DO** slash for existing methods (`workspace/create` etc). For `workspace.list` investigate: Flutter `workspaceList()` currently calls `workspace.list` DOT which compat stub answers 200 with empty. After slash migration it becomes `workspace/list` which has no Host handler → will 404. Need to confirm Host source for list (maybe `workspace/list` not exposed; Flutter should keep using stub or add host method). Mark as **needs verification**. |
| `POST /api/agentPreset.list` (dot singular) | `POST /api/agentPresets/list` (slash plural) | `packages/preset/agent-presets/src/index.ts` `super(ctx,'agentPresets',{namespace:'agentPresets'})` method `remoteExportList` => `agentPresets/list`. Commit `306419cc84 refactor(agent-presets): expose browser operations through Remote`. | **DO** replace singular→plural + slash. Same for `read|copy|deletePreset|select`. |
| `POST /api/skill.list` (dot singular) | `POST /api/skills/list` (slash plural) | `packages/api/session-controller/src/skill-catalog.ts:25 super(ctx,'sessionSkillCatalog',{namespace:'skills'})` => `skills/list`. | **DO** replace `skill.list` → `skills/list`. |
| `POST /api/host.pickDirectory` (dot host) | `POST /api/directoryPicker/pick` (slash different namespace) | `packages/api/workspace-controller/src/directory-picker.ts:44 super(ctx,'directoryPickerController',{namespace:'directoryPicker'})` methods `pick|list|createDirectory`. Commits `6e4087626d remove directory-picker RPCs`, `54d77eff00 docs directory-picker`. | **DO** replace `host.*` → `directoryPicker/*` (namespace rename, not just slash). |
| `POST /api/goal.edit` (dot singular) | `POST /api/goals/edit` (slash plural) | `packages/goal/goal/src/index.ts:194 @Remote('edit')` inside `GoalService super(ctx,'goals')` namespace `goals`. Lookup `agentId` not `sessionId`. | **DO** replace `goal.edit` → `goals/edit` plural + slash, and fix payload from `{sessionId,ref,objective}` DOT shape to `{args:{agentId, ref, request:{objective}}}` slash shape. |
| `POST /api/host.describe` (dot) | `COMPAT stub POST /api/host.describe 200 {hostId,home}` (no real Typert) | `packages/client/connection/src/rpc-host.ts:161` compat stub returns fake host info when no interceptor claims endpoint. Real host info now comes from `RemoteEvent ready {home}` or `remote` namespace. | **KEEP** compat for handshake liveness but migrate to `$events` ready frame for real data (P1). |
| `POST /api/session.history` (dot) | `POST /api/session/page` (slash, payload shape changed) | Old `session.history` was apiproxy route (`packages/host/apiproxy/src/api/sessions.ts: history`). Migrated to Typert `session/page` (`packages/api/session-controller/src/index.ts:367 @Remote('page')`). Request now `{sessionId, cursor?, limit?}` vs old `{sessionId, beforeSeq?, maxMessages?}`. | **DO** rename to `session/page` and remap payload. |
| `POST /api/session.selectModel` (dot) | `POST /api/session/selectModel` (slash with wrapper) | Typert expects `payload:{args:{request:{sessionId,provider,model,reasoningEffort?}}}` per dirty diff special case. Flutter currently sends dot raw payload. | **DO** slash + wrapper fix. |
| `WS /api/events.mux` + `/api/events.host` (legacy SSE/WebSocket) | `WSS /api/remote.mux` multiplex + `$events` + `$events/result` | Host moved from `host/apiproxy events.mux/host` to `api/gateway` mux (`packages/api/gateway/src/index.ts:209`, `stream-protocol.ts:5`). Old Flutter paths kept as compat upgrades that `acceptWebSocket` but never pump frames (`packages/client/connection/src/index.ts:195-211`). | **DO NOT** blanket keep old paths; they now silently drop events (P1). Migrate to `remote.mux` with Typert `RemoteStream` protocol. |

**Dot→Slash rule of thumb proved:** For every Typert Remote, `endpoint = namespace + "/" + method` (slash). For every legacy ApiProxy dot method that was migrated, the new endpoint is **exactly** that slash form **unless** the namespace or method was also renamed (see 5 cases above where namespace changed). Global `sed 's/\./\//g'` would break the 5 renamed cases by producing correct slash but wrong namespace.

---

## 8. Removed APIs (current React no longer exposes)

| Removed | Last seen | Replacement | Evidence |
|---|---|---|---|
| `llm.providers` | pre-`4f00a8b82a` ApiProxy | `llm/listProviders` + `llm/listConfigurableProviders` | No `@Remote` named `providers` in `packages/llm/llm/src/index.ts`; host tests `service.spec.ts` only check `listProviders` |
| `llm.models` | same | `session/modelCatalog` | No `llm.models` Remote; Host log `a2ba3fc0a8 update tracker after upstream merge` notes model catalog move |
| `session.models` (Flutter custom) | never on Host | `session/modelCatalog` global | Host has no `@Remote('models')` in `session-controller`; only `modelCatalog` |
| `host.pickDirectory`, `host.listDirectory`, `host.createDirectory` | pre-`6e4087626d` | `directoryPicker/pick|list|createDirectory` | `packages/host/directory-picker*` docs |
| `goal.*` singular namespace | pre-`243f6629ef delete the goal unary domain` | `goals/*` plural | `packages/goal/goal/src/index.ts` namespace `goals` |
| `agentPreset.*` singular | pre-`306419cc84` | `agentPresets/*` plural | `packages/preset/agent-presets/src/index.ts` |
| `skill.*` singular | pre-`2d4393d842` | `skills/*` plural | `packages/api/session-controller/src/skill-catalog.ts` namespace `skills` |
| `ApiProxy` package itself | `4f00a8b82a remove ApiProxy package` | `api/gateway` + `client/connection` | `packages/host/` no longer contains `apiproxy` |
| `POST /api/respond` (legacy mux answer) | pre-gateway | `POST /api/$events/result` | `packages/api/gateway/src/stream-protocol.ts:12` |

---

## 9. New APIs (Flutter must adopt)

| New API | Endpoint | Purpose | Host source |
|---|---|---|---|
| `llm/listProviders` | `POST /api/llm/listProviders` | live adapter routes (`{id,name}[]`) | `packages/llm/llm/src/index.ts:461` |
| `llm/listConfigurableProviders` | `POST /api/llm/listConfigurableProviders` | dormant directory (`{provider,displayName,settingsNs,settingsPath}[]`) | `:533` |
| `llm/discoverModels` (new payload shape) | `POST /api/llm/discoverModels` | interrogate draft endpoint | `:620` |
| `session/modelCatalog` | `POST /api/session/modelCatalog` | global routable model catalog | `packages/api/session-controller/src/index.ts:248` |
| `session/page` | `POST /api/session/page` | history pagination (replaces `session.history`) | `:367` |
| `directoryPicker/*` (3) | `POST /api/directoryPicker/*` | native picker/browse | `packages/api/workspace-controller/src/directory-picker.ts:44` |
| `agentPresets/*` (5) | `POST /api/agentPresets/*` | preset roster/CRUD | `packages/preset/agent-presets/src/index.ts` |
| `skills/list` | `POST /api/skills/list` | skill catalog per session | `packages/api/session-controller/src/skill-catalog.ts:25` |
| `goals/*` (6) | `POST /api/goals/*` | goal waterfall | `packages/goal/goal/src/index.ts` |
| `subagents/*` (3) | `POST /api/subagents/*` | subagent control | `packages/subagent/subagent/src/index.ts:209` |
| `sessionReferenceResolver/candidates` already exists but was not used via old host.* | `POST /api/sessionReferenceResolver/candidates` | @session mentions | `packages/context/session-reference/src/index.ts` |
| `remote/*` slash variants | `POST /api/remote/*` | pairing/devices | `packages/host/remote-access/src/remote-service.ts:46` |

---

## 10. Payload Changes (React/Host vs Flutter)

| API | React/Host shape (slash, strict) | Flutter current (dot, outdated) | Impact |
|---|---|---|---|
| `session/history` → `session/page` | `POST /api/session/page` `payload:{args:{sessionId, cursor?, limit?}}` → `SessionPage{meta,events}` | `POST /api/session.history` `payload:{sessionId, beforeSeq?, maxMessages?}` → Flutter parses `events` + `projections` | **Payload mismatch P0** — host will reject or return 404; Flutter's `beforeSeq` mapping lost |
| `session/selectModel` | `payload:{args:{request:{sessionId,provider,model,reasoningEffort?}}}` (per dirty diff special case) | `payload:{sessionId,provider,model,reasoningEffort?}` raw dot, plus special-case wrapper only for slash but not applied while still dot | Host strict codec expects `request` wrapper; will 400 |
| `llm/discoverModels` | `payload:{args:{settingsNs, request:{provider?,baseURL?,api?,apiKey?}, signal}}` → `LlmDiscoveredModel[]` | `payload:{settingsNs, provider?, baseURL?, api?, apiKey?}` flat raw | Host expects nested `request` object; Flutter flat will 400 `arguments-invalid` |
| `agentPresets/select` | `payload:{args:{agentId, agentPreset}}` (lookup `agentId` wire, not `sessionId`) | `payload:{sessionId, agentPreset}` dot raw | Host lookup via `ctx.typert.lookups` expects `agentId` wire name; `sessionId` field missing → 400 |
| `agentPresets/deletePreset` | `payload:{args:{id}}` where `id` wire = `agentPreset` param | `payload:{agentPreset}` with method `remove` | Method name + wire name both wrong |
| `goals/*` | `payload:{args:{agentId, ref:{id,revision}, request:{objective?}}}` (lookup) | `payload:{sessionId, ref, objective}` flat | Namespace + lookup wire mismatch |
| `skills/list` | `payload:{args:{sessionId}}` (actually host `SkillListRequest {sessionId}`) but via `skills/list` | `payload:{sessionId}` dot raw (same shape but dot vs slash + namespace singular vs plural) | Namespace mismatch causes 404 before payload |
| `settings/*` writes | `payload:{args:{ns,patch,expectedRevision}}` etc. | `payload:{ns,ops,expectedRevision}` dot raw | After slash migration must wrap as `{args:{ns,ops,...}}` — Flutter's modified `_postTypert` already does `args` wrapping for slash, so post-fix will be correct |
| `session/prompt` | `payload:{args:{requestId?, sessionId, mode?, content, clientTimeZone?}}` | same but dot raw | Dot→slash + wrapper needed |
| General unary | All slash methods expect `{args:{...}}` (exactly one key) | All dot methods send raw `payload` without wrapper | Host `assertExactArguments` will reject dot payloads after migration if wrapper not added; dirty diff's `if(method.contains('/')) effectivePayload={args:payload}` fixes this for slash |

**Response shape changes:**

- `session/page` returns `SessionPage{meta:SessionHeader, events:SessionEvent[]}` (host) vs old `session.history` Flutter expected `{events:HistoryEntry[], projections?:SessionProjectionsBlock}` — `meta` vs `projections` mismatch.
- `llm/listProviders` returns top-level JSON array `LlmProviderInfo[]` (host `RemoteResult<LlmProviderInfo[]>`), which gateway wraps as `{_list:[...]}` in Flutter's `_unwrapValue` tolerance — handled.
- `agentPresets/list` returns `{presets:PresetRow[], authorable:boolean}` vs old `agentPreset.list` singular shape similar but namespace singular.
- `skills/list` returns `{skills:SkillEntry[]}` vs Flutter `skill.list` expected `items`.
- `session/modelCatalog` returns `ModelCatalog{providers, default?}` vs old `llm.models` grouped shape.

---

## 11. Event Changes

**Result: No breaking event name or payload change** (F3 §10). All 10 MuxFrame + 9 HostFrame discriminants, 38 SessionEvent types, 17 forwarded RemoteEvents identical TS ↔ Dart. No `SESSION_FORMAT_VERSION` bump.

Two transport-level moves (P1, not breaking event shape):

- `WSS /api/events.mux|host` → `WSS /api/remote.mux` + `$events` logical stream + `POST /api/$events/result` (gateway). Old paths compat-accepted but silent.
- `POST /api/respond` (mux answerable) → `POST /api/$events/result` (Typert waterfall answer). Payload changes from `{type:'client-response', rpcId, result}` to `{args:{clientId,eventId,outcome}}`.

---

## 12. Security & Scope Changes

- **Trust fence preserved:** `isTrustedApiRequest` + `BrowserAuth` unchanged (`packages/client/connection/src/api-request-trust.ts`, `browser-auth.ts`). Dirty diff adds `trustedHosts` handling for `0.0.0.0` binds.
- **Bearer scope:** `remote/*` endpoints now require `full` bearer (except `remote/pair` unauthenticated). Flutter already sends `Authorization: Bearer <token>` via `SecureTokenStore` — correct.
- **Authorization:** No change to `settings.describe` redaction (`redactSecrets:true`), `credentials.describe` `refs` limit 64, `llm/adapters-updated` non-vetoing emit.
- **CORS:** `client-connection/index.ts:195` adds `Access-Control-Allow-Headers: content-type, x-rpc-id, authorization` and `Allow-Credentials` — needed for Flutter Web `withCredentials=true` (dirty diff `connection_client.dart:126` sets `withCredentials=true` for `BrowserClient`).

---

## 13. Priority P0 Fixes (API returns 404/400 or wrong wire endpoint)

**Must fix before any feature works; each is a hard 404 without compat stub.**

1. **session.* dot→slash (6 endpoints)** — `session.list|search|create|prompt|cancel|updateQueue|attachment|rename|fork|search|selectModel|page` — file `connection_client.dart:288,322,361,372,388,399,412,839,1933` + `sidebar.dart` `session.rename|fork`, `command_service.dart` `session.prompt`.
2. **session.history → session/page payload remap** — `connection_client.dart:322` — map `beforeSeq` → `cursor`/`limit` or keep compat shim reading `sessionId` + `cursor`.
3. **settings.* dot→slash** — `settings.describe|mutate|update|replace` — `connection_client.dart:595,610`.
4. **credentials.* dot→slash** — `credentials.describe|set|unset` — `connection_client.dart:616,625,634`.
5. **llm.discoverModels dot→slash + nested request wrapper** — `connection_client.dart:748`.
6. **Remove deprecated `llm.providers` / `llm.models` / `session.models` raw dot calls** — `connection_client.dart:698,712` — keep only `llm/listProviders` + `listConfigurableProviders` + `session/modelCatalog` (already slash).
7. **workspace.* dot→slash (6 endpoints)** — `workspace.list|create|rename|delete|insertBefore|insertSessionBefore|archiveSession` — `connection_client.dart:775-826` + `session_workspace_services.dart:87` + `sidebar.dart:1933`.
8. **skill.list singular→skills/list plural + slash** — `connection_client.dart:844`.
9. **agentPreset.* singular→agentPresets/* plural + slash + method rename `remove→deletePreset`** — `connection_client.dart:849,857` + `agent_preset_provider.dart:93,107,118`.
10. **host.* → directoryPicker/* namespace rename + slash** — `session_workspace_services.dart:99,119,137`.
11. **remote.* dot→slash (5 endpoints)** — `remote.pair|devices|revoke|refresh|ws-ticket` — `connection_client.dart:883,896,906` + `devices_screen.dart:42,300`.
12. **goal.* singular→goals/* plural + slash + payload `{args:{agentId,ref,request}}`** — `goal_control.dart:97,106,110,114`.
13. **`_postTypert` payload wrapper for all slash** — ensure `effectivePayload={args:payload}` except `session/selectModel` special `{args:{request:payload}}` matches Host `SessionSelectModelRequest` shape; for lookup methods ensure wire field is `agentId` not `sessionId`.

**Files to modify (P0):**
- `apps/flutter/lib/src/core/connection/connection_client.dart` — 25 `_postTypert` literal strings
- `apps/flutter/lib/src/core/services/session_workspace_services.dart` — 3 `host.*` → `directoryPicker/*`
- `apps/flutter/lib/src/plugins/agent_preset/ui/agent_preset_provider.dart` — 3 `agentPreset.*` → `agentPresets/*`
- `apps/flutter/lib/src/plugins/goal/goal_control.dart` — 4 `goal.*` → `goals/*` + payload fix
- `apps/flutter/lib/src/plugins/commands/command_service.dart:230` — `session.prompt` dot→slash
- `apps/flutter/lib/src/features/sidebar/sidebar.dart:1894,1909,1933`
- `apps/flutter/lib/src/plugins/settings/children/plugin_inventory/plugin_inventory_service.dart:44` — `pluginInventory.list` dot→slash
- `apps/flutter/lib/src/features/devices/devices_screen.dart:42,300` — `remote.*`

No host or React changes — Flutter is the only drift.

---

## 14. Priority P1 Fixes (feature loads but stale / wrong invalidation / compat stub)

1. **Event streams: migrate `/api/events.mux` + `/api/events.host` → `/api/remote.mux` multiplex** — `connection_client.dart:937,944` `_openEvents`, `websocket_transport.dart`. Host compat upgrades (`client/connection/src/index.ts:195-211`) accept but drop frames → Flutter sees `Active` but no `session/event|queue|jobs|projection|approval/question` pushes. Must implement `RemoteStreamMuxClient` analog in Dart (open logical streams `session/follow`, `session/control`, `workspace/follow`, `$events`). Deferrable but causes stale conversation/queue.
2. **`POST /api/respond` → `POST /api/$events/result`** — `connection_client.dart:434 respond()` used by `approval_responder.dart` + `question_responder.dart`. Host gateway now expects `$events/result` with `{clientId,eventId,outcome}`. Legacy `respond` may still be answered by compat but waterfall semantics changed.
3. **`host.describe` stale stub** — `connection_client.dart:865` returns fake `{hostId: dsh-local-host, home:/tmp}` via `rpc-host.ts:161` compat. Real `home` should come from `$events` ready frame `host:{home}`. Keep stub for liveness, but surface real `home` when `$events` ready arrives.
4. **Agent preset roster stale** — `agentPresetListProvider` never invalidates on `agent-preset/selected`; add `remote.$on('agent-preset/selected', invalidate)`.
5. **Model directory stale** — `modelDirectoryProvider` has no `llm/adapters-updated` listener; add `$on('llm/adapters-updated', refresh)`.
6. **Settings mutate stale** — generic `SettingsScope` needs `settings/document-updated` → `refreshFromDescribe()` wired (currently only Models store does).
7. **`_postTypert` handling of void vs array results** — `_unwrapValue` wraps array returns as `{_list:[...]}` (host `CommandDescriptor[]` etc.) — correct but plugins must read `_list` not `items`. Already handled in `command_plugin.dart:74` (`value['_list'] ?? ...`). Keep.

---

## 15. Priority P2 (cosmetic / docs)

- `workspace.list` has no host handler — decide if Flutter should keep calling stub or host should expose `workspace/list` (maybe via `workspaceController` + `list`).
- Naming `pluginInventory.list` vs `pluginInventory/list` (already P0) vs `pluginInventory` case — Host uses `pluginInventory` (camelCase) + `list` => `pluginInventory/list` correct.
- `connection_client.dart:246 _legacyPathToMethod` handles `/api/sessions/list|history|prompt` legacy `/api/sessions/*` plural — not used by new code, can be removed after P0.

---

## 16. Security & platform notes

- Remote pairing (`remote/pair` unauth) must keep `pin` optional and `devicePublicKey` handling; Flutter `remote_pairing_client.dart` already does.
- `withCredentials=true` for `BrowserClient` (`connection_client.dart:126`) is required for loopback cookie auth on Web (`127.0.0.1:5001 → 127.0.0.1:3080` cross-port) — dirty diff correct.
- `host.listDirectory` etc. must not be exposed to remote mobile without policy — `directoryPicker` namespace already checks `native` capability and throws `directory-picker-unavailable` when not loopback.

---

## 17. Tests Required (Phase 25)

For every changed API add contract test (at minimum endpoint+method+shape):

- `apps/flutter/test/core/connection/connection_client_test.dart` — add cases for each slash endpoint: assert `POST /api/session/list` with `payload:{args:{}}` and `500` on dot, validate `session/page` cursor mapping, `session/selectModel` wrapper, `llm/discoverModels` nested request, `agentPresets/deletePreset` vs `remove`, `directoryPicker/*`, `goals/*` lookup wire, `skills/list`.
- Live-host integration: run `pnpm dsh --profile headless` host at current master, capture network with `flutter test --dart-define=DSH_HOST_URL=http://localhost:xxx` or manual host; verify `Settings → Models` no longer `POST /api/llm.providers 404`.
- Semantic replay: replay `packages/client` snapshots through Flutter `message_provider_test.dart` already covers `session/event` folding — ensure no drift after payload changes.
- Keep existing `apps/flutter/test/api/frames_test.dart` (Mux/Host frames) and `rpc_envelope_test.dart` green.

No test weakening — add `/* v8 ignore */` only for unreachable defensive arms with real reason.

---

## 18. Live Host Verification Checklist (Phase 26 — to run after P0 fix)

- Start CURRENT DSH host: `pnpm dsh --profile headless "echo ready"` or `pnpm run build && node lib/host` from current master revision, confirm `POST /api/llm.providers → 404` before fix, `POST /api/llm/listProviders → 200` after fix.
- Verify `Settings → Models` loads provider directory (live + configurable) and `credentials/describe` redacted.
- Verify `host.describe + both-streams` handshake completes to `Active` (not `reconnecting`) with real `home` from `$events`.
- Capture actual network: `flutter analyze`, `flutter test` + manual host log `console.log [webserver] POST /api/...` already added in dirty diff for diagnosis — remove after verification.

---

## 19. Full Feature Matrix — Post-Fix Verification (Phase 27)

Each row must be checked on **Flutter Web**, **macOS**, **Android** (Phase 28):

| Feature | RPC / stream verified | Expected host endpoint | Status target |
|---|---|---|---|
| Connection: host.describe + mux + host | `POST /api/host.describe compat 200` + `WS /api/remote.mux` | `host.describe` stub then `$events` ready | Active |
| Sessions: list/create/open/history/prompt/cancel | `session/list|create|page|prompt|cancel` slash | `POST /api/session/*` | PASS |
| Conversation: user message, assistant stream, thinking, tool calls, tool results, subcalls, errors, retry, queue | `session/prompt` + `session/event` + `tool/call|result` events | `session/past` + `session/projection` | PASS |
| Models: provider directory, model directory, model selection, reasoning | `llm/listProviders|listConfigurableProviders`, `session/modelCatalog`, `session/selectModel` | `POST /api/llm/*`, `session/modelCatalog` | PASS |
| Settings: General, Models, Plugins, Inventory, Language | `settings/describe|mutate`, `credentials/*`, `pluginInventory/list` | `settings/describe` slash | PASS |
| Permissions: read-only, workspace-write, danger-full-access | `session/projection key=permissions` + `settings/mutate ns=permission` | `permissions` projection | PASS |
| Plan: on/off/pending | `commands/execute /plan off` | `POST /api/commands/execute` | PASS |
| Agent Preset: Standard, PTC, Minimal, Creator | `agentPresets/*` slash plural | `POST /api/agentPresets/*` | PASS |
| Workspace: list/select/create/rename/archive/reorder | `workspace/*` slash | `POST /api/workspace/*` | PASS |
| Attachments: picker, drop, thumbnail, send, host admission, attachment retrieval | `session.attachment` slash | `POST /api/session/attachment` | PASS |
| Interaction: slash, @ mention, approval, question | `commands/list`, `fileReferences/list`, `sessionReferenceResolver/candidates`, `respond` → `$events/result` | `POST /api/commands/list` | PASS |
| Locale | `settings/locale` via `settings/describe` | `settings/describe` | PASS |
| Devices | `remote/devices|revoke` | `POST /api/remote/*` | PASS |
| Web connects correctly | `withCredentials` + CORS | `Access-Control-Allow-Origin` echo | PASS |
| macOS connects | `SecureTokenStore` bearer | `authorization: Bearer` | PASS |
| Android remote | `ticket` WS | `wss://.../api/remote.mux?ticket=` | PASS |

---

## 20. Git History Evidence (Phase 9)

Selected commits proving contract changes (not invented):

| Commit | Date | Old | New | Affected source |
|---|---|---|---|---|
| `fd7f2065b2 refactor(apiproxy)!: remove settings and credentials RPCs` | 2026-08-09 | `POST /api/settings.*` + `credentials.*` via ApiProxy | `POST /api/settings/describe|mutate ...` via Typert `SettingsController` | `packages/api/settings-controller/src/index.ts` + `credentials.ts` |
| `6e4087626d refactor(apiproxy)!: remove directory-picker RPCs` | 2026-08-10 | `host.pickDirectory|listDirectory|createDirectory` ApiProxy | `directoryPicker/pick|list|createDirectory` Typert | `packages/api/workspace-controller/src/directory-picker.ts` |
| `243f6629ef refactor(apiproxy): delete the goal unary domain` | 2026-08-10 | `goal.*` singular ApiProxy | `goals/*` plural Typert | `packages/goal/goal/src/index.ts` |
| `306419cc84 refactor(agent-presets): expose browser operations through Remote` | 2026-08-10 | `agentPreset.*` singular ApiProxy | `agentPresets/*` plural Typert | `packages/preset/agent-presets/src/index.ts` |
| `ce3391e280 refactor(apiproxy): retire migrated unary routes` | 2026-08-10 | remaining ApiProxy routes | Typert Gateway | `packages/host/apiproxy/src/api/*` deletion |
| `4f00a8b82a refactor(api): remove ApiProxy package` | 2026-08-11 | `ApiProxy` package exists | `ApiProxy` package deleted, Gateway sole carrier | `packages/host/apiproxy` removed |
| `5ba36aa350 Merge PR #3217 worktree-apire-remaining` | 2026-08-12 | `workspace.*` ApiProxy | `workspace/*` Typert | `packages/api/workspace-controller/src/index.ts` |
| `2d4393d842 refactor(api): expose remaining domain remotes` | 2026-08-12 | `skills|subagents|messageFeedback` ApiProxy | `skills/*`, `subagents/*`, `messageFeedback/*` Typert | `packages/api/session-controller/src/skill-catalog.ts`, `packages/subagent/...` |
| `e57e7c3f25 docs(api): describe Connection-owned transport` | 2026-08-12 | per-route docs | Gateway docs `docs/api-gateway.md` with `POST /api/<ns>/<method>` | `docs/api-gateway.md` |

Use `git log -S'oldName'` and `git log -G'pattern'` as in §20 to locate each rename; example `git log -S'llm.providers' --oneline` shows last occurrence before `ce3391e280`.

---

## 21. Machine-Readable Manifests

- `migration/api-contract/current-react-api.json` — 56 React(=Host) entries, source, method, endpoint, request/response, transport.
- `migration/api-contract/flutter-api.json` — 52 Flutter calls, file:line, wire literal, status (`DOT_SHOULD_BE_SLASH`, `REMOVED`, `WRONG_NAMESPACE`, etc.).
- `migration/api-contract/api-diff.json` — Compatibility matrix with `PASS|RENAMED|MOVED|PAYLOAD_CHANGED|REMOVED|WRONG_LAYER|UNKNOWN`, priority `P0|P1|P2`, fix guidance, and `dotVsSlashAnalysis` section proving each suspected rename with OLD/NEW source + commit.

Do not invent schemas — manifest entries mirror TypeScript types and Dart `_postTypert` literals verbatim.

---

## 22. Next Steps — Implementation Order (Phase 24: P0 first)

**Read-only analysis complete. No application code changed in this report PR — report only.**

P0 implementation PR (next) must:

1. Edit `apps/flutter/lib/src/core/connection/connection_client.dart`: replace 25 dot literals with slash (+ 2 removals), fix `session.history` → `session/page` payload, fix `session/selectModel` wrapper, `llm/discoverModels` nesting, `skill`/`agentPreset`/`host`/`goal`/`remote` namespaces.
2. Edit `apps/flutter/lib/src/core/services/session_workspace_services.dart`: `host.*` → `directoryPicker/*`.
3. Edit `apps/flutter/lib/src/plugins/agent_preset/ui/agent_preset_provider.dart`: `agentPreset.*` → `agentPresets/*`.
4. Edit `apps/flutter/lib/src/plugins/goal/goal_control.dart`: `goal.*` → `goals/*` + payload.
5. Edit `apps/flutter/lib/src/plugins/commands/command_service.dart`, `apps/flutter/lib/src/features/sidebar/sidebar.dart`, `apps/flutter/lib/src/plugins/settings/children/plugin_inventory/plugin_inventory_service.dart`, `apps/flutter/lib/src/features/devices/devices_screen.dart`.
6. Add contract tests for every changed API (`apps/flutter/test/core/connection/connection_client_test.dart`).
7. Verify with live host: `POST /api/llm.providers` must **not** remain; `POST /api/llm/listProviders` must 200; `Settings → Models` must work.

P1 streams (`/api/remote.mux` + `$events/result`) in follow-up PR after P0 lands — do not mix wire-endpoint renames with transport refactoring.

---

## 23. Appendix — Repository Baseline (Phase 0)

```
git branch --show-current          => feat/conversation-gen-ai-ui
git rev-parse HEAD                 => 4f2038e343c92bbb1dff37416cb8909b95dd07b8
git rev-parse master               => cd5ef8148158c3a752a658978873241fdf8e2bbc
git rev-parse origin/master        => cd5ef8148158c3a752a658978873241fdf8e2bbc
git merge-base HEAD master         => cd5ef8148158c3a752a658978873241fdf8e2bbc (Flutter contains master)
working tree                       => 6 modified, not yet staged (M)
DeepSeek Harness commit in use     => cd5ef81481 (master HEAD)
Running DSH host built from same revision? => Dirty working tree includes host/webserver + client/connection compat stubs; host must be rebuilt from HEAD (pnpm run build) before live verification.
```

`git diff --stat HEAD` (pre-report):

```
apps/flutter/lib/src/core/connection/connection_client.dart | 103 ++++++++++++++++++---
packages/client/connection/src/api-request-trust.ts         |  11 ++-
packages/client/connection/src/browser-auth.ts              |   2 +-
packages/client/connection/src/index.ts                     |  90 +++++++++++++++++-
packages/client/connection/src/rpc-host.ts                  |  70 ++++++++++++++
packages/host/webserver/src/index.ts                        |   7 ++
```

---

## 24. Appendix — Agents Used

- R1 React surface inventory — exhaustive grep + file reads (56 ops, 13 tables, JSON appendix) — background subagent `ses_faf984e34ffeZq7h55kdJXDnsu` — **completed**
- R2 React transport trace — gateway dispatch + endpoint derivation — `ses_faf966215ffeVS0jhGJCLzX1o6` — **completed**
- R3 Host contract inventory — source Typert `@Remote` scan per namespace (~54 unary + 4 streams, protocol constants) — `ses_faf9628a7ffegpBsjYkDqQbL2P` — **completed**
- F1 Flutter API inventory — manual exhaustive grep + `ses_faf95eb31ffeznT94TdbJMmYZD` (pending, de-duplicated by manual grep) — **completed via manual**
- F2 Flutter provider/service consumer map — full Riverpod inventory (38 providers, per-area deep map) — `ses_faf958299ffePB2zt40Kceay7o` — **completed**
- F3 Events/stream/projection inventory — MuxFrame/HostFrame/SessionEvent/RemoteEvent/ProjectionFrame + RPC envelope, no rename detected — `ses_faf95164dffeTM28wRane56sNx` — **completed**
- X Central comparator — this document + `migration/api-contract/*.json` — **completed**

First pass was read-only as required; application code changes are deferred to next PR.

---

*End of Phase 23 report. Next: Phase 24 P0 implementation PR — update Flutter to current contract, no unrelated UI changes, no compatibility aliases unless justified, every changed API gets a regression test, live-host verification before merge.*
