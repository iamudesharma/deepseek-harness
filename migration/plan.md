# Migration Execution Plan v2 — Plugin-Architecture-First

**Date:** 2026-08-21 · **Mode:** Migration Mode v1.1 (unchanged contract) · **Tracker:** [migration-tracker.json](migration-tracker.json) (single ledger, extended in place) · **Gate:** `pnpm run verify-flutter-tracker --check`

## Why a new plan

The v1.1 rework rebuilt the measurement system honestly and stopped there: all 112 tracker items sit at `Audited`, none at `Migrated` or beyond, and `--strict` cannot pass because no Verified path exists. Meanwhile `apps/flutter` grew as a hardcoded widget tree: [main.dart](../apps/flutter/lib/main.dart) mounts a fixed router and watches bootstrap providers directly. Features live under `lib/src/features/*` with no plugin host, no slot registry, and no capability seam between them — so each feature is wired to every other by import instead of by composition. That is the structural reason screens can look finished while the application stays incomplete: the React side composes ~33 UI plugin packages through slots and service DI ([client AGENTS](../packages/client/AGENTS.md)), and none of that composition model exists on the Flutter side yet.

This plan changes the **execution unit and order**, not the contract. Lifecycle states, write-authority partition, parity enums, synthetic-fallback policy, and the Gatekeeper remain exactly as specified in the [v1.1 design spec](../docs/superpowers/specs/2026-08-21-migration-rework-v1.1-design.md).

## Decisions inherited (do not relitigate)

- **One tracker, extended in place.** The v1.1 rework rejected a fresh tracker file ("two ledgers invite drift"); this plan adds rows and workstreams, never a second ledger. The proposed "plugin migration manifest schema" is therefore expressed through the existing fields (`reactPackage` already groups items per plugin package; categories `runtime|protocol|slot` already carry the non-UI layers).
- **No new agent framework.** The 18-agent roster and skill set stand. Workstreams below assign *existing* agents disjoint id prefixes.
- **Platform scope is Web + macOS.** `platformParity` keys stay `{web, macos}`. Desktop-portable structure (platform service adapters) is designed now; Windows/Linux verification is out of scope until the core completes.

## Ground truth the plan is built on

1. **React composition model (what Flutter must reproduce):** four cooperating registries — the Loader entry graph (which plugins exist), the client module table (when code arrives; irrelevant for AOT Flutter), Cordis service DI (how features get services), and the typed `SlotMap` ledger (how UI composes). One registration API: `ctx.slots.register({ name, children?, store?, inject? }, Component)` with slot kinds `single|list|keyed|chain`, scopes `root|session-maybe|session`, children-declaration-as-authorization, and cascade collapse on disposal ([ui-slots](../packages/client/ui-slots/src/index.ts)).
2. **Plugin anatomy (the five-layer unit):** every `ui-*` package is `apply` + `inject` service list + `contract/` + stores/controller + slot registrations + components. Exemplar registrations captured in [ui-conversation/src/client/apply.ts](../packages/client/ui-conversation/src/client/apply.ts) (9 registers, shared `chatStore` handle, `ConversationController` class plugin, `sessions.provide`, locale namespace) and [ui-tool](../packages/client/ui-tool/src/client/apply.ts) (keyed chat-node renderer + child-slot declaration + per-tool sub-plugins).
3. **Dependency shape:** `ui-primitives`/`ui-slots` are shell-seeded foundations; `ui-settings` anchors the settings subtree; `ui-layout` owns the frame; **`ui-conversation` is the hub with 18 dependents**; business plugins hang off the hub. Full adjacency lives in [audit/dependency-inventory.md](audit/dependency-inventory.md).
4. **Backend boundary stands:** Flutter consumes Harness session/event/mux/host frames over `/api`; it never becomes the LLM/provider runtime. `api.llm` remains backend-owned (`not-applicable`), as already recorded in the tracker.
5. **Existing Flutter assets worth keeping:** real SSE mux/host pump with backoff (`core/connection`), live sync (`core/session/live_sync.dart`), 80+ `--dsw-*` token aliases, 28 primitives, 139 passing tests, 4 goldens, both platform builds green. These re-enter the ladder as raw material for `Migrated`, not as evidence.
6. **Layer-0 tracker rows already exist** and stay authoritative: [slot.registry](migration-tracker.json), `slot.tool-renderer-registry`, `modules.client-plugin-loading`, and `plugin.client-lifecycle` (all `Audited`). P0.1 claims land on these rows; only genuinely missing host machinery (the renderer seam) gets new rows.
7. **Evidence floor is honest-zero:** all 112 `evidence` objects empty, `behavior` parity `missing` on every item, and the 75 legacy parity reports predate v1.1 gates — nothing may be re-promoted from prior artifacts alone.

## Strategy shift

```
was:  React component ──translate──▶ Flutter widget in features/
now:  React plugin package ──port layer-by-layer──▶ Flutter plugin registered into a host
      (contract → runtime/services → slot registrations → UI → verification)
```

The Flutter app becomes a plugin host. `main.dart` shrinks to: build host context (connection, sessions, workspaces, locale, settings, remote), install built-in machinery (slot registry, renderer), then activate plugins in dependency order; the shell renders `'root'` and nothing else knows the tree. Each existing `features/<name>` directory is re-homed as `plugins/<name>` **as part of that plugin's `Audited → In Progress` transition**, carrying its tests along — no big-bang rewrite, no throwaway of current work.

### Layer 0 — Flutter host (new code, tracked as new rows)

Mirrors the React seams 1:1 so semantic parity stays comparable; no invented abstractions:

- **Slot registry** (`core/slots/`): `SlotKind {single, list, keyed, chain}`, `SlotScope {root, sessionMaybe, session}`, register-with-children-authorization, same-cell conflict throws, cascade child collapse on dispose, `inject(slot)` wait-and-follow semantics with atomic generator rollback. Render side resolves shadowing by priority; only the host renders `root`.
- **Plugin contract** (`core/plugin/`): `DshPlugin { id, List<String> inject, Future<void> apply(DshContext) }` where `DshContext` exposes the service table (Riverpod containers/readers behind stable faces: `slots`, `sessions`, `workspaces`, `locale`, `connection`, `settingsScope`). Activation waits declared services — the cordis fiber-wait model, not import order.
- **Renderer** (`core/renderer/`): slot outlets as widgets, session-scoped provider injection (the `SessionProvider` analog over Riverpod), snapshot-selector hooks (`useSession(sel)` ≙ `Provider<Watch>)`.
- **Platform service seam** (`platform/`): directory picker, window, clipboard, storage behind conditional imports (pattern already proven by `adaptive_directory_picker`); Web + macOS implementations verified, stubs documented-not-verified for future desktop targets.

Tracker mapping: the existing `slot.registry`, `modules.client-plugin-loading`, and `plugin.client-lifecycle` rows own the registry/lifecycle seams; a renderer-seam row sourced from `packages/client/ui-renderer` is added if the audit confirms none covers it.

## Phased DAG

Order is dependency-driven from the adjacency list; blockers are recorded per phase entry criteria. P0/P1/P2 naming matches the planner mandate and the v1.1 phase letters.

### P0 — Host foundation + core runtime (critical path, mostly serial)

1. **Host slice** (Layer 0 above) — blocks every plugin port.
2. **Connection completion**: full `ConnectionController` semantics — generation counter, strict two-stream handshake, jittered backoff, `connection/reset`; carrier visibility banner already exists.
3. **Session/event runtime**: event-window fold, `SessionEventMap` fidelity (required-on-read defaults, ignorable envelopes), notifier publication discipline (`notifyNow` gesture echo / microtask `markDirty` / cumulative streaming frames), projection runtime, pending-interaction runtime.
4. **Conversation assembly contracts**: node definitions, deterministic fold replayable by log `seq`, streaming tail, turn/step grouping, compaction — as *contracts consumed through DI* even though the UI arrives later.
5. **Protocol extraction**: RPC request/result/error carriers, `rpcId` bidirectional pairing, domain APIs (`SessionsApi`, `HostApi`, `WorkspaceApi`, …) generated from TS definitions — hand-invented contracts forbidden (`$harness-api-contract-extraction`).

Exit: a headless Flutter harness activates the host, connects to a live host or replay fixture, folds a recorded session stream, and prints a stable transcript snapshot. Tracker: runtime/protocol/slot rows reach `Integrated` with `integrationPoints` recorded; `e2eScenarios` populated.

### P1 — Composition hubs, then business plugins (parallelizable)

Hubs first (serial-ish, dependency order): `ui-theme` → `ui-primitives` re-audit → `ui-settings` (+ `settingsScope`) → `ui-layout` frame + `ui-sidebar` → **`ui-conversation`** (skeleton, composer chain, chat view, details, docks, node renderers).

Then business plugins in parallel workstreams, each owning **disjoint `reactPackage` prefixes** and entering only after its declared dependencies reached `Integrated`:

| Workstream | Plugins (reactPackage values) |
|---|---|
| WS-Chat | ui-tool (+7 toolview sub-registrations), ui-trajectory, ui-message-feedback |
| WS-Agent | ui-subagent, ui-skill, ui-agent-preset, ui-plan |
| WS-Tasks | ui-goal, ui-jobs, ui-workflow-run, ui-deliverables |
| WS-Input | ui-input-trigger, ui-commands, ui-reference, ui-user-questions |
| WS-Surfaces | ui-model-selection, ui-permission-presets, ui-workspace, ui-directory-picker-browse/native, ui-brand-official, ui-attachment, settings-* children |

Each plugin ports its five layers in order (contract → services/stores → slot registrations → UI → tests), re-homing its `features/` code at `In Progress`. Stop claims at `Migrated`; integration-stage agents advance `Integrated`.

### P2 — Parity, platform, promotion waves

Semantic replay (`$semantic-parity-replay`: identical event streams through React and Flutter, diffed), three-tier test generation, visual parity + goldens, Web/macOS platform sweeps, then Gatekeeper promotion waves under `--strict`. Completion requires the full v1.1 gate conjunction (schema valid, no orphans, runtime/streaming/reconnect/interaction parity pass, replay pass, platform pass, no production synthetic fallback, Gatekeeper approval).

## Verification mapping (unchanged mechanisms)

- Every tracker edit: `pnpm run verify-flutter-tracker --check`; completion claims additionally `--strict`.
- Evidence lives outside the tracker: `migration/parity-reports/`, test output, replay diffs. `parityCheck: pass` remains a claim until the Gatekeeper reviews the bundle.
- Synthetic fallback policy enforced per `runtimeMode` (`live` forbids adapters; `replay` allows fixtures; `offline` allows declared `adapter-of:` only).

## Risks and recorded blockers

- **`flutter_gen_ai_chat_ui` vs slot composition** — the conversation feature recently adopted this package (see git history). If its rendering pipeline cannot sit inside the conversation plugin's slot registrations, it gets confined to the chat-node renderer or replaced; decided by WS-Chat at `In Progress`, recorded on the affected tracker rows.
- **Re-home churn** — mitigated by moving each feature directory only within its own plugin's transition, tests traveling with the code.
- **flutterTarget path drift** — legacy rows cite kebab-case or renamed paths that no longer exist on disk (`user-questions_screen.dart` vs `user_questions_screen.dart`, `tooltip.dart` vs `ds_tooltip.dart`), and both `route/` and `routing/` directories exist. The gate tolerates this below `Migrated` but blocks every promotion; each plugin reconciles its own targets at `Audited → In Progress` (Tracker Agent bookkeeping), and P0.1 consolidates on `routing/`.
- **Hub serialization** — `ui-conversation` gates 18 packages; it starts immediately after its dependencies and is the P1 critical path.
- **Windows/Linux pressure** — deferred by decision; the platform seam keeps the door open without widening `platformParity` today.

## First actions

1. Reconcile drifted `flutterTarget` paths on the four Layer-0 rows and any row entering `In Progress`; add only the missing renderer-seam row (source: `packages/client/ui-renderer`); regenerate [TRACKER.md](TRACKER.md); `--check` green.
2. Stand up `apps/flutter/lib/src/core/{slots,plugin,renderer}` with package-level tests, claiming `slot.registry` + `modules.client-plugin-loading` + `plugin.client-lifecycle` toward `Migrated` (owners: slot-plugin + flutter-integration stage agents).
3. Begin P0.5 protocol extraction in parallel (owner: protocol-event agent) — it touches no Flutter UI and unblocks session runtime work.
