# Upstream Sync Report — 2026-09-06

> Generated: 2026-09-06T11:15:17.208Z
> Upstream: https://github.com/deepseek-ai/deepseek-harness.git @ master
> Old SHA: `d347e703908d0406b7a7ef80e3a0e594d86b2215` (`d347e703`) → New SHA: `d347e703908d0406b7a7ef80e3a0e594d86b2215` (`d347e703`)
> Local HEAD: `75229657`  Merge-base: `d347e703`  Behind: 0  Ahead: 138

## Summary

| Metric | Value |
|---|---|
| Commits | 0 |
| Files changed | 0 |
| File categories |  |
| API operations (prev → current) | 92 → 92 |
| API changes | 0 (breaking: 0, additive: 0) |
| Stream changes | 0 |
| React surfaces | 967 |
| Flutter call sites | 160 in 360 files |
| Parity | PASS 56 / MISSING 1 / INCOMPATIBLE 0 / UNKNOWN 9 |
| Flutter impact | P0 2 · P1 1 · P2 0 · P3 0 |
| Registry entries | 0 |
| Parity gate | ❌ FAIL |
| Recommended action | P0 blocking — do not merge Flutter without fixes |

## Commits (upstream..new)

_No commits — already at upstream_

## Files changed by category

| Category | Count | Sample files |
|---|---|---|

## API changes

_No API changes detected_

## Stream changes

_No stream changes_

### Stream endpoints (current)

| Name | Path | Kind | Source |
|---|---|---|---|
| REMOTE_STREAM_MUX_PATH | `/api/__remote_stream_mux` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| $events | `/api/events` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| events.host | `/api/events.host` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| remote.mux | `/api/events.mux` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| REMOTE_STREAM_MUX_PATH | `/api/remote.mux` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| REMOTE_EVENT_STREAM_ENDPOINT | `$events` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| REMOTE_EVENT_RESULT_ENDPOINT | `$events/result` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| session/control | `session/control` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| session/follow | `session/follow` | websocket | `packages/api/gateway/src/stream-protocol.ts` |
| workspace/follow | `workspace/follow` | websocket | `packages/api/gateway/src/stream-protocol.ts` |

Heartbeat: 30000ms · Reconnect: jittered backoff, generation increment · Auth: browser cookie + bearer token (remote)

## React vs Flutter parity

| Status | Count |
|---|---|
| PASS | 56 |
| MISSING | 1 |
| INCOMPATIBLE | 0 |
| OUTDATED | 0 |
| UNKNOWN | 9 |
| REMOVED | 0 |

| API | Status | Sev | React → Flutter | Reason |
|---|---|---|---|---|
| `session/disposed` | MISSING | P0 | `∅` | React uses session/disposed but Flutter does not call it |
| `session/follow snapshot.cursor` | UNKNOWN | P0 | `∅` | React session/follow snapshot.cursor vs Flutter session/page sentinel cursor discovery — ARCHITECTURAL MISMATCH |
| `agentPreset selected event` | UNKNOWN | P1 | `∅` | React agentPreset selected event updates session state via events; Flutter must consume same event (event ignored → STATE/PARITY MISMATCH) |
| `directoryPicker/readFile` | UNKNOWN | P2 | `directoryPicker/readFile` | Flutter uses directoryPicker/readFile not found in React surfaces; verify if deprecated or new |
| `messageFeedback/delete` | UNKNOWN | P2 | `messageFeedback/delete` | Flutter uses messageFeedback/delete not found in React surfaces; verify if deprecated or new |
| `messageFeedback/list` | UNKNOWN | P2 | `messageFeedback/list` | Flutter uses messageFeedback/list not found in React surfaces; verify if deprecated or new |
| `messageFeedback/put` | UNKNOWN | P2 | `messageFeedback/put` | Flutter uses messageFeedback/put not found in React surfaces; verify if deprecated or new |
| `subagents/interruptByParent` | UNKNOWN | P2 | `subagents/interruptByParent` | Flutter uses subagents/interruptByParent not found in React surfaces; verify if deprecated or new |
| `subagents/list` | UNKNOWN | P2 | `subagents/list` | Flutter uses subagents/list not found in React surfaces; verify if deprecated or new |
| `subagents/prompt` | UNKNOWN | P2 | `subagents/prompt` | Flutter uses subagents/prompt not found in React surfaces; verify if deprecated or new |
| `agentPresets/copy` | PASS | P3 | `agentPresets/copy` | React and Flutter both use agentPresets/copy |
| `agentPresets/deletePreset` | PASS | P3 | `agentPresets/deletePreset` | React and Flutter both use agentPresets/deletePreset |
| `agentPresets/list` | PASS | P3 | `agentPresets/list` | React and Flutter both use agentPresets/list |
| `agentPresets/read` | PASS | P3 | `agentPresets/read` | React and Flutter both use agentPresets/read |
| `agentPresets/select` | PASS | P3 | `agentPresets/select` | React and Flutter both use agentPresets/select |
| `commands/execute` | PASS | P3 | `commands/execute` | React and Flutter both use commands/execute |
| `commands/list` | PASS | P3 | `commands/list` | React and Flutter both use commands/list |
| `credentials/describe` | PASS | P3 | `credentials/describe` | React and Flutter both use credentials/describe |
| `credentials/set` | PASS | P3 | `credentials/set` | React and Flutter both use credentials/set |
| `credentials/unset` | PASS | P3 | `credentials/unset` | React and Flutter both use credentials/unset |
| `directoryPicker/createDirectory` | PASS | P3 | `directoryPicker/createDirectory` | React and Flutter both use directoryPicker/createDirectory |
| `directoryPicker/list` | PASS | P3 | `directoryPicker/list` | React and Flutter both use directoryPicker/list |
| `directoryPicker/pick` | PASS | P3 | `directoryPicker/pick` | React and Flutter both use directoryPicker/pick |
| `fileReferences/list` | PASS | P3 | `fileReferences/list` | React and Flutter both use fileReferences/list |
| `host/describe` | PASS | P3 | `host/describe` | React and Flutter both use host/describe |
| `llm/discoverModels` | PASS | P3 | `llm/discoverModels` | React and Flutter both use llm/discoverModels |
| `llm/listConfigurableProviders` | PASS | P3 | `llm/listConfigurableProviders` | React and Flutter both use llm/listConfigurableProviders |
| `llm/listProviders` | PASS | P3 | `llm/listProviders` | React and Flutter both use llm/listProviders |
| `pluginInventory/list` | PASS | P3 | `pluginInventory/list` | React and Flutter both use pluginInventory/list |
| `remote/devices` | PASS | P3 | `remote/devices` | React and Flutter both use remote/devices |
| `remote/pair` | PASS | P3 | `remote/pair` | React and Flutter both use remote/pair |
| `remote/refresh` | PASS | P3 | `remote/refresh` | React and Flutter both use remote/refresh |
| `remote/revoke` | PASS | P3 | `remote/revoke` | React and Flutter both use remote/revoke |
| `remote/ws-ticket` | PASS | P3 | `remote/ws-ticket` | React and Flutter both use remote/ws-ticket |
| `session/attachment` | PASS | P3 | `session/attachment` | React and Flutter both use session/attachment |
| `session/cancel` | PASS | P3 | `session/cancel` | React and Flutter both use session/cancel |
| `session/canOpenWorkspacePath` | PASS | P3 | `session/canOpenWorkspacePath` | React and Flutter both use session/canOpenWorkspacePath |
| `session/control` | PASS | P3 | `session/control` | React and Flutter both use session/control |
| `session/create` | PASS | P3 | `session/create` | React and Flutter both use session/create |
| `session/follow` | PASS | P3 | `session/follow` | React and Flutter both use session/follow |
| `session/fork` | PASS | P3 | `session/fork` | React and Flutter both use session/fork |
| `session/list` | PASS | P3 | `session/list` | React and Flutter both use session/list |
| `session/modelCatalog` | PASS | P3 | `session/modelCatalog` | React and Flutter both use session/modelCatalog |
| `session/openWorkspacePath` | PASS | P3 | `session/openWorkspacePath` | React and Flutter both use session/openWorkspacePath |
| `session/page` | PASS | P3 | `session/page` | React and Flutter both use session/page |
| `session/prompt` | PASS | P3 | `session/prompt` | React and Flutter both use session/prompt |
| `session/rename` | PASS | P3 | `session/rename` | React and Flutter both use session/rename |
| `session/search` | PASS | P3 | `session/search` | React and Flutter both use session/search |
| `session/selectModel` | PASS | P3 | `session/selectModel` | React and Flutter both use session/selectModel |
| `session/updateQueue` | PASS | P3 | `session/updateQueue` | React and Flutter both use session/updateQueue |
| `settings/canOpenAgentPresetDirectory` | PASS | P3 | `settings/canOpenAgentPresetDirectory` | React and Flutter both use settings/canOpenAgentPresetDirectory |
| `settings/describe` | PASS | P3 | `settings/describe` | React and Flutter both use settings/describe |
| `settings/mutate` | PASS | P3 | `settings/mutate` | React and Flutter both use settings/mutate |
| `settings/openAgentPresetDirectory` | PASS | P3 | `settings/openAgentPresetDirectory` | React and Flutter both use settings/openAgentPresetDirectory |
| `settings/openSettingsDocument` | PASS | P3 | `settings/openSettingsDocument` | React and Flutter both use settings/openSettingsDocument |
| `settings/replace` | PASS | P3 | `settings/replace` | React and Flutter both use settings/replace |
| `settings/update` | PASS | P3 | `settings/update` | React and Flutter both use settings/update |
| `skills/list` | PASS | P3 | `skills/list` | React and Flutter both use skills/list |
| `workspace/archiveSession` | PASS | P3 | `workspace/archiveSession` | React and Flutter both use workspace/archiveSession |
| `workspace/create` | PASS | P3 | `workspace/create` | React and Flutter both use workspace/create |
| … | … | … | … | … 6 more |

## Flutter impact

| Severity | Count |
|---|---|
| P0 (blocks runtime) | 2 |
| P1 (feature broken) | 1 |
| P2 (compat risk) | 0 |
| P3 (informational) | 0 |

| ID | Change | Sev | Affected Flutter files | Required action |
|---|---|---|---|---|
| `flutter:session/page-cursor` | session/page throughSeq sentinel vs cursor | P0 | connection/connection_client.dart<br>session/live_history.dart | verify Flutter getSessionHistory requires throughSeq and waits for LiveHistory.acceptedSeq; no fabricated cursor |
| `flutter:settings-describe-list` | settings/describe List namespaces | P0 | settings/settings_scope.dart<br>settings/settings_screen.dart | ensure SettingsScope._refreshNow handles List<Map> and fallback forms; verified in be6498fd |
| `flutter:remote-mux-ticket` | remote.mux bearer ticket flow | P1 | connection/remote_mux_client.dart<br>connection/connection_client.dart | verify ticket fetch and re-pair flow; no silent fallback to unauthenticated |

## Change registry (excerpt)

| ID | Category | Sev | Old → New | Status | Description |
|---|---|---|---|---|---|

## Model / Type changes (heuristic)

Namespaces prev → current: 19 → 19 (agentPresets, agentTeams, commands, credentials, directoryPicker … → agentPresets, agentTeams, commands, credentials, directoryPicker …)

## Recommended actions

- [ ] Fix all **P0** items before merging sync branch (runtime blockers).
- [ ] Verify `session/page throughSeq` cursor discipline — no synthetic sentinel.
- [ ] Run `pnpm upstream:verify` (typecheck + flutter analyze + verify-flutter-tracker).
- [ ] Create branches as per policy: `sync/upstream/YYYY-MM-DD-<sha>` and `flutter-sync/YYYY-MM-DD-<sha>` (no auto-merge).

## Artifacts

- `migration/upstream-sync/upstream-state.json`
- `migration/upstream-sync/api-contract-current.json` / `api-contract-previous.json` / `api-diff.json`
- `migration/upstream-sync/stream-contract-current.json` / `stream-contract-previous.json` / `stream-diff.json`
- `migration/upstream-sync/react-contract.json`
- `migration/upstream-sync/flutter-contract.json`
- `migration/upstream-sync/flutter-impact.json`
- `migration/upstream-sync/change-registry.json`

---
_Report generated by upstream-sync • upstream d347e703 → d347e703 • local 75229657_
