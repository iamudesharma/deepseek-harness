# Permission / Plan / Model + Conversation Correction — 2026-08-23

**Date:** 2026-08-23 · **Scope:** Flutter Web + macOS · **Contracts:** React `ui-permission-presets`, `plan-mode`/`ui-plan`, `ui-model-selection` + `ui-conversation`/`session`/`live_sync`

## 1. Permission / Access Mode

**React contract:** `packages/interaction/permission-presets` + `packages/client/ui-permission-presets`
- Presets `workspace-write → sandbox workspace-write + approval ask`, `danger-full-access → sandbox danger-full-access + approval never`, `read-only` when configured, `custom` derived (not selectable)
- Projection `SessionProjectionMap.permissions: {options:[{value,name,description}], currentValue}` registered via `sessionProjections` with `apply` on `permission/preset`/`sandbox/mode`/`approval/policy`, view folds composition defaults
- Two lifetimes: **Settings/default** (`permission` ns `defaultPreset` via `settings.mutate`, affects `pinInitialPermission` on `session/created`) vs **Current-session** (`/permission <preset>` via `remote.commands.execute` → durable knob events → `permissions` view)
- Risk acknowledgement for `danger-full-access` via `RiskConfirmation` modal

**Flutter fix:** `permission_session_provider.dart` (`PermissionSelect`), `live_sync` now seeds/applies `SessionProjectionFrame key:permissions` and `getSessionHistory` tail block, `PermissionSeat` (`conversation.session.header.actions` list) reads `permissionSelectProvider`, `PopupMenuButton` shows options with `custom` disabled, `danger-full-access` triggers `showPermissionRiskDialog` checkbox, submit via `client.callMethod('commands/execute',{args:{agentId,line:'/permission <preset>',images:[]}})` — projection is confirmation.

**Live-host verification (real dsh at 8787):**
```
session-9ad6c133… initial permissions: workspace-write
commands/execute /permission danger-full-access → {commandId, result:{kind:success,text:"preset danger-full-access"}} → list: danger-full-access
commands/execute /permission workspace-write → list: workspace-write
```
`read-only` present when deployment configures it (`options` contains it).

## 2. Plan Mode

**React contract:** `packages/plan/plan-mode` + `packages/client/ui-plan`
- Durable `plan/mode {active}` last-wins, no turn-enclosure; `set(agent,active)` → `committed` (idle) / `queued`/`cancelled`/`noop` (hasOpenTurn → pendingIntents → `agent/pre-step` boundary)
- Projection `SessionProjectionMap.plan: {active,pending}` derived from `command/run`/`command/done`+`plan/mode` with `pending = (running?.wanted ?? wanted) != null && != active`
- UI `PlanChip` effective `target = pending ? !active : active`, chip only while `target` and `plan!==undefined`; `exitPlanMode` → `remote.commands.execute('/plan off')` → `!ok` → `message (code)`, `value===undefined` → `unknown command`

**Flutter divergence:** Was `client.sendMessage('/plan off')` as user prompt → `hasValue:false` → always `unknown command`.

**Fix:** `app_plugins.dart` `PlanControl` now `client.callMethod('commands/execute',{args:{agentId,line:'/plan off',images:[]}})` with `result.kind==error` handling; `live_sync` handles `SessionProjectionFrame key:plan` and `plan/mode` direct log; `PlanNotifier` seed `active:false` (inactive before first).

**Live-host:**
```
session-5658e088… plan {active:false,pending:false}
commands/execute /plan          → {kind:success,text:"Plan mode on. …"} → list plan {active:true,pending:false}
commands/execute /plan off (idle) → {kind:success,text:"Plan mode off."} → {active:false,pending:false} (committed)
commands/execute /plan off (idle second time) → {kind:success,text:"Plan mode is already inactive."} → noop
```
In-turn `queued` would leave `pending:true` until next `pre-step` → `plan/mode` → verified by unit `pending ? !active`.

## 3. Model + Reasoning Effort

**React contract:** `packages/client/ui-model-selection` + host `session.models`/`session.selectModel` (`ModelSelection {provider,model,reasoningEffort?}`, `ModelCatalogModel.reasoning?:{efforts:[{id,name,description}],defaultEffort}`)
- `ModelInfo.reasoning` from exact-model `resolveModelInfo` (DeepSeek `off/low/high/max` with `thinking:disabled` → `off` only)
- Effort UI only when `reasoning!==undefined`; `effectiveEffort = current.reasoningEffort ?? defaultEffort`; `provider-default` row when `defaultEffort==null`
- Model switch carries `defaultEffort` (or none) — clears stale; effort switch preserves `provider/model`

**Flutter gap:** `ModelInfo` had no `reasoning`, seat showed only model name, `onSelected` never sent `reasoningEffort`.

**Fix:** `model_directory.dart` adds `ModelReasoningEffort`/`ModelReasoning` parsed from `json['reasoning']`; `model_seat.dart` finds exact `currentModel` to read `reasoning`, computes `effectiveEffort`, shows second `PopupMenuButton` for effort only when `reasoning!=null` (with provider-default row, check on `effectiveEffort`), model pick sends `reasoningEffort: target.reasoning?.defaultEffort`, effort pick preserves route.

**Live-host:**
```
session.models current {provider:opencode,model:laguna-s-2.1-free}
groups 4, deepseek-official/deepseek-v4-flash reasoning {efforts:[off,low,high,max],defaultEffort:high}
session.selectModel provider:deepseek-official model:deepseek-v4-flash → selected {provider,model,reasoningEffort:high}
```

Blank → live default, restored → durable `request/header`, `reasoning==null` hides effort.

## 4. Conversation (title, user, markers, steps, error, queue, plan)

**React contracts:** `ui-conversation` definitions, `session/title` projection, `live_sync` `applySessionEventToSummary` (blank→false on `user/message`), structural markers log-only, step brackets hidden until content, `displayFailureMessage` for `turn/end` error.

**Flutter fixes:** `SessionSummary.displayTitle` (`title→cwd basename→id`, blank→`New session`), `fromJson` reads `projections.values['title']`, `getSessionHistory` tail block, `live_sync` `SessionProjectionFrame key:title`; `_extractUserText` for `ContentBlock[]`, compaction guard, `turn/start`/`end-seed`/`compaction/start` no longer emit `MarkerNode`, empty `step/start→step/end` dropped, `_upsert` group-aware via `_findAssistant`, `chat_view` forwards `expandedGroup`, `MarkerNode` → `SizedBox.shrink`.

**Live-host conversation:**
```
session-b9c982f5… prompt Hello → history tail contains turn/start, step/start, user/message content:[{type:text,text:"Hello"}] surfaceOp:append, etc.
Flutter fold: UserMessageNode text:"Hello" top-level, no markers, no Step 1·0 tools
```

**Tests:** `conversation_integration_test.dart` 22 tests (title, user→assistant, failed turn, markers, compaction, todo, empty/non-empty/multi-step/streaming, plan nop, markers), `permission_model_plan_test.dart` 18 tests, plus `conversation_nodes_test.dart` 15, `live_sync_test` gap, `business_host` co-activation, `semantic_parity` 2, `surface_goldens` 6.

## 5. Builds / Platforms / Live

* `flutter analyze lib` — 0 errors
* `flutter test` — 494/494 (was 460, +22+18 new, full suite 494)
* `pnpm vitest run semantic-parity` — 2/2
* `flutter test test/goldens --update-goldens` — 6/6
* `flutter build web --release --dart-define=DSH_HOST_URL=http://127.0.0.1:8787 --no-wasm-dry-run` — ✓ 3.4M
* `flutter build macos --debug` — ✓ `dsh_flutter.app`
* `session.create→list→prompt→history` live at 8787 verified for all three flows above
* Python `http.server 8321` serving `build/web` same-origin via `DSH_HOST_URL` + `isTrustedApiRequest` loopback cross-port + CORS
