---
name: api-to-dart
description: Use when migrating frontend API/service integrations (Typert RPC, SSE, ConnectionController, host webserver) to Dart — generate typed Dart clients and preserve host compatibility without changing backend logic.
---

# API to Dart — Service Integration Migration Skill

Migrate browser-host RPC and service integrations to Dart while preserving backend, core harness, and provider logic.

## Sources of truth

* `packages/client/connection` — `ConnectionController`, `http-bridge`, `api-path`, `api-request-trust`
* `packages/api`, `packages/typert` — type graph, Typert RPC gateway (`packages/client/AGENTS.md:Layering`)
* `packages/host/webserver`, `packages/host/frontend-static` — serving contract, `rpcId` bidirectional rule
* `packages/client/AGENTS.md:Initiator-owned private chains` — `agent.session` capture rules

## Workflow

### 1. Enumerate consumed APIs per frontend item

```sh
grep -R "ctx\.\|inject\|ConnectionController\|api/" packages/client --include="*.ts" -n | sort
grep -R "sessions\.provide\|useSessions\|useSession" packages/client --include="*.tsx" -n | head -n 100
cat packages/api/*/src/*.ts | head -n 200
```

For each `packages/client/*/src/client/*`, record:
* Typert service name + method (`ctx.llm`, `ctx.sessions`, `ctx.tools`, etc.)
* HTTP/SSE endpoints, `RpcRequest<P>` shape, `rpcId` minting
* Event domains consumed (`session/event`, `agent/*`, `tools/*`)

### 2. Generate / reuse Dart Typert

* Reuse Typert type graph generator: `packages/typert/generator` → Dart emit or `dart:js_interop` bridge
* Prefer native Dart HTTP: `package:http` + `dart:convert` JSON, typed with `freezed`/`json_serializable` or `built_value`
* Keep `rpcId` rule: initiator mints UUID, responder echoes — never mint in business signature

### 3. Preserve host compatibility

* Flutter Web: same origin `fetch` → `http` with credentials; SSE via `EventSource` or `sse_client`
* Flutter macOS: same, plus `Process`/`Socket` if needed but keep provider integrations on host
* If Dart requires small host change (CORS header, JSON field rename), gate behind `Config` field in host plugin, never hardcode default in Dart (`AGENTS.md:No hardcoded tunables`)

### 4. State sync

* Port `runtime` object-layer semantics to Dart `ChangeNotifier`/`Riverpod` providers that mirror `SessionManager` event window and reconnect state machine
* Do not duplicate business state in widget `State` — single source in Dart service layer

### 5. Verify

* `flutter test` mocks host via `http.MockClient` or fake server from `packages/test-support/llm-mock-server`
* E2E: Dart relay of `apps/web/tests/*.e2e.ts` scenarios passes against real `dsh web` (same as `pnpm run test:web:built`)

## Anti-patterns

* Do not rewrite backend/provider logic to fit Flutter — frontend migration only
* Do not bypass Typert validation with `dynamic` / `any` — generate typed contracts
* Do not mix transport and business layers (tool schemas, prompt assembly stay host-owned)
