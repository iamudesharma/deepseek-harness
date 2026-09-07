# Upstream Sync Report — 2026-09-07

> Generated: 2026-09-07T14:42:32.161Z
> Upstream: https://github.com/deepseek-ai/deepseek-harness.git @ master
> Old SHA: `d347e703908d0406b7a7ef80e3a0e594d86b2215` (`d347e703`) → New SHA: `b0a7d2ce3b4c19d7452e364b2d7acbfa87e707ed` (`b0a7d2ce`)
> Local HEAD: `003422c9`  Merge-base: `b0a7d2ce`  Behind: 422  Ahead: 424

## Summary

| Metric | Value |
|---|---|
| Commits | 422 |
| Files changed | 3971 |
| File categories | HOST:41, API:32, CLIENT:214, REACT:41, CORE:1236, INTERACTION:5, MODEL:31, STREAM:46, SECURITY:23, BUILD:70, DOCS:2101, TEST:54, OTHER:77 |
| API operations (prev → current) | 92 → 92 |
| API changes | 0 (breaking: 0, additive: 0) |
| Stream changes | 0 |
| React surfaces | 987 |
| Flutter call sites | 160 in 361 files |
| Parity | PASS 56 / MISSING 1 / INCOMPATIBLE 0 / UNKNOWN 9 |
| Flutter impact | P0 2 · P1 1 · P2 0 · P3 0 |
| Registry entries | 255 |
| Parity gate | ❌ FAIL |
| Recommended action | P0 blocking — do not merge Flutter without fixes |

## Commits (upstream..new)

| SHA | Subject | Author | Date |
|---|---|---|---|
| `b0a7d2ce` | Merge pull request #2672 from deepseek-harness/xtr/durable-inbox-recovery | _Kerman | 2026-09-07 |
| `dbb9db5f` | docs(session-controller): refresh translation pairing record | _Kerman | 2026-09-07 |
| `68643a07` | docs(session-controller): unwrap zh readme paragraph | _Kerman | 2026-09-07 |
| `753effe6` | fix(bench): rely on testkit session projection mounting | _Kerman | 2026-09-07 |
| `ba05b7d4` | Merge pull request #3413 from deepseek-harness/feat/electron | 07akioni | 2026-09-07 |
| `0348599f` | Merge remote-tracking branch 'origin/master' into dshw/pr-deepseek-harness-deepseek-harness-2672 | _Kerman | 2026-09-07 |
| `016af7c6` | Merge release 0.1.3-alpha.2 and reconcile desktop composition | 07akioni | 2026-09-07 |
| `8d0d7290` | Merge master native containment updates into feat/electron | 07akioni | 2026-09-07 |
| `82a5fd61` | Merge pull request #3685 from deepseek-harness/worktree/release-dsh-0.1.3-alpha.2 | Yichen Jiang | 2026-09-07 |
| `e379fa8b` | release(dsh): 0.1.3-alpha.2 | Yichen Jiang | 2026-09-07 |
| `c7e29f4b` | Merge pull request #2825 from deepseek-harness/codex/subprocess-native-containment | pku-xht | 2026-09-07 |
| `0f83a2cd` | Merge remote-tracking branch 'origin/master' into codex/subprocess-native-containment | pku-xht | 2026-09-07 |
| `9292dd8a` | feat(workspace): open the workspace in local apps from the web UI (#3409) | ihsiang | 2026-09-07 |
| `e9f1b6c5` | Merge remote-tracking branch 'origin/master' into codex/subprocess-native-containment | pku-xht | 2026-09-07 |
| `9d93c570` | Merge pull request #3672 from deepseek-harness/perf/session-observation-lazy-events | Dudu-0223 | 2026-09-07 |
| `5b91dbfb` | perf(session-query): materialize live observation events on first read | Dudu-0223 | 2026-09-07 |
| `cb602a0d` | Merge pull request #3507 from deepseek-harness/worktree/3410-model-switch-notice | CreatixChu | 2026-09-07 |
| `48cc1cf1` | feat(agent): announce model switches | creatixchu | 2026-09-07 |
| `5fd247f6` | Merge latest master into feat/electron | 07akioni | 2026-09-07 |
| `4ac4e3d0` | Merge pull request #3668 from deepseek-harness/fix/windows-subagent-teardown-ci | Tianyi Cui | 2026-09-07 |
| `96ead609` | feat(subagent): align human inbox controls (#3223) | Dudu-0223 | 2026-09-07 |
| `5608528e` | Merge pull request #3637 from deepseek-harness/perf/frontend-scenarios | Tianyi Cui | 2026-09-07 |
| `b53c95e4` | Merge pull request #3664 from deepseek-harness/fix/scroll-follow-pending-sample | Tianyi Cui | 2026-09-07 |
| `4023879d` | test(codex): finish captured cleanup after sibling failures | Tianyi Cui | 2026-09-07 |
| `a1d11f21` | test(session): observe shared waiter admission before cancellation | Tianyi Cui | 2026-09-07 |
| `4a9c180e` | Merge branch 'master' into feat/electron | 07akioni | 2026-09-07 |
| `9ef426d7` | fix(chat): keep genuine near-floor scroll gestures pending | Tianyi Cui | 2026-09-07 |
| `421e3b07` | test(subagent): preserve lane budgets and await teardown completion | Tianyi Cui | 2026-09-07 |
| `cbdf3244` | fix(benchmarks): calibrate repeated hosted browser open median | Tianyi Cui | 2026-09-06 |
| `1a3af89a` | fix(benchmarks): calibrate hosted paging and trajectory endpoints | Tianyi Cui | 2026-09-06 |
| `620c2b0b` | fix(benchmarks): calibrate hosted frontend endpoints and preserve input overlap | Tianyi Cui | 2026-09-06 |
| `0ac1d4d8` | test(perf): align browser provisioning with hosted benchmark runner | Tianyi Cui | 2026-09-06 |
| `c51c16cd` | test(perf): respect browser failover provisioning policy | Tianyi Cui | 2026-09-06 |
| `00e452aa` | docs(perf): confirm repeated frontend CI calibration | Tianyi Cui | 2026-09-06 |
| `82cd3546` | docs(perf): record first frontend CI calibration | Tianyi Cui | 2026-09-06 |
| `93695858` | test(perf): bound browser observers to active response | Tianyi Cui | 2026-09-06 |
| `2927034f` | test(perf): retain successful CI measurement output | Tianyi Cui | 2026-09-06 |
| `7ac5e082` | test(perf): measure real history streams and live input overlap | Tianyi Cui | 2026-09-06 |
| `6ad74db2` | test(perf): gate long-session browser and active reconnect workflows | Tianyi Cui | 2026-09-06 |
| `843c8723` | docs(perf): link active hosted request calibration | Tianyi Cui | 2026-09-06 |
| `e2b81cf8` | docs(perf): distinguish hosted request and catalog budgets | Tianyi Cui | 2026-09-06 |
| `8e270960` | test(perf): calibrate request history on standard hosted CI | Tianyi Cui | 2026-09-06 |
| `73edce1a` | perf(agent-loop): reuse proven message freezes per agent | Tianyi Cui | 2026-09-06 |
| `84914c31` | test(perf): calibrate baseline requests for hosted CI | Tianyi Cui | 2026-09-06 |
| `2f008835` | test(perf): calibrate tool continuation for hosted CI | Tianyi Cui | 2026-09-06 |
| `daa7f606` | test(perf): calibrate catalog for standard hosted CI | Tianyi Cui | 2026-09-06 |
| `1507f828` | docs(perf): record backend CI evidence and align workload prose | Tianyi Cui | 2026-09-06 |
| `c599ef87` | test(perf): baseline tool-heavy backend workflows | Tianyi Cui | 2026-09-06 |
| `6c4cd033` | Merge pull request #3280 from deepseek-harness/fix/ci-node-compile-cache-data-disk | Tianyi Cui | 2026-09-07 |
| `fa6bf62a` | fix(chat): settle pinned scroll deliveries before layout growth | Tianyi Cui | 2026-09-07 |
| `6d55da99` | Merge master into feat/electron after scope cleanup | 07akioni | 2026-09-07 |
| `4879a8a3` | refactor(desktop): remove unrelated changes and own host dependencies | 07akioni | 2026-09-07 |
| `ef11a4e0` | Merge pull request #3644 from deepseek-harness/fix/environment-prompt-suffix | Tianyi Cui | 2026-09-07 |
| `0125f901` | revert: remove pwsh changes from desktop PR | 07akioni | 2026-09-07 |
| `3d54bd6d` | Merge branch 'master' into fix/ci-node-compile-cache-data-disk | Tianyi Cui | 2026-09-07 |
| `403b978c` | Merge pull request #3626 from deepseek-harness/optimize/ci-compatible-selfhosted | Tianyi Cui | 2026-09-07 |
| `694d250f` | Merge master and retain upstream CI synchronization fixes | 07akioni | 2026-09-07 |
| `a7ea2d74` | docs: remove redundant compatibility runner guide | Tianyi Cui | 2026-09-06 |
| `ac4fa3d6` | docs: clarify compatibility runner scope and verification | Tianyi Cui | 2026-09-06 |
| `a137256f` | ci: set compatibility toolcache after runner environment export | Tianyi Cui | 2026-09-06 |
| `f7a18f49` | ci: isolate compatibility Node jobs on self-hosted Linux | Tianyi Cui | 2026-09-06 |
| `fd9debed` | Merge branch 'master' into fix/environment-prompt-suffix | Tianyi Cui | 2026-09-07 |
| `c379894a` | fix(ci): isolate routing test setup and correct scheduling docs | Tianyi Cui | 2026-09-06 |
| `ab1ee996` | ci: defer macOS ARM runtime and Wine checks to master | Tianyi Cui | 2026-09-06 |
| `fbb385c5` | test(web): pin replay timezone and await UI settlement | 07akioni | 2026-09-07 |
| `31090e24` | Merge pull request #3643 from deepseek-harness/fix/ci-python-runtime-smoke-retry | Tianyi Cui | 2026-09-07 |
| `541dc51e` | fix(desktop): allow fs-ext in generated projects | winewill | 2026-09-07 |
| `8b250f5d` | test: synchronize console and shell readiness and pin browser timezone | 07akioni | 2026-09-07 |
| `60d3e320` | fix(test): await lazy grammar registration notifications | Tianyi Cui | 2026-09-07 |
| `1ed20364` | test(snapshot): refresh PowerShell fixtures | 07akioni | 2026-09-07 |
| `64dfd7a4` | fix(test): await Client Console subscription delivery | Tianyi Cui | 2026-09-07 |
| `f5302b2b` | fix(test): isolate recorded Web browser timezone | Tianyi Cui | 2026-09-07 |
| `31b3f3bc` | Merge remote-tracking branch 'origin/master' into feat/electron | 07akioni | 2026-09-07 |
| `237b3d5e` | fix(test): synchronize pwsh completion and refresh profile snapshots | Tianyi Cui | 2026-09-07 |
| `beb23feb` | Merge branch 'master' into fix/environment-prompt-suffix | Tianyi Cui | 2026-09-07 |
| `5c8e1b53` | Merge latest master into fix/ci-node-compile-cache-data-disk | Tianyi Cui | 2026-09-06 |
| `40792330` | fix(system-prompt): keep model persona prefix and place cwd in suffix | Tianyi Cui | 2026-09-06 |
| `1dc50c49` | fix(ci): harden Python runtime builds against transient failures | Tianyi Cui | 2026-09-06 |
| `6ac32583` | Merge pull request #3640 from deepseek-harness/ci/benchmark-standard-runner | Tianyi Cui | 2026-09-06 |
| `e28862db` | fix(system-prompt): place environment facts after reusable instructions | Tianyi Cui | 2026-09-06 |
| `88e4c3c2` | Merge master and preserve hosted benchmark documentation | Tianyi Cui | 2026-09-06 |
| `6f21b112` | fix: wait for the Python console runtime on Windows | Tianyi Cui | 2026-09-06 |
| `50b0511f` | Merge pull request #3466 from deepseek-harness/feat/system-prompt-surface-node-notes | Tianyi Cui | 2026-09-06 |
| `86528bb8` | Merge pull request #3642 from deepseek-harness/fix/python-runtime-hosted-windows | Tianyi Cui | 2026-09-06 |
| `083cef0a` | docs(notes): record hosted Windows runtime decision, retire the proposal | Tianyi Cui | 2026-09-06 |
| `6933eccd` | docs(notes): record hosted Windows runtime decision, reject proposal | Tianyi Cui | 2026-09-06 |
| `faa33c0f` | revert(ci): run Windows Python runtime CI on GitHub-hosted Windows | Tianyi Cui | 2026-09-06 |
| `cd5e872b` | Merge branch 'master' into ci/benchmark-standard-runner | Tianyi Cui | 2026-09-06 |
| `3bb63f9e` | Merge pull request #3632 from deepseek-harness/perf/speed-up-skill | Tianyi Cui | 2026-09-06 |
| `e29b6528` | docs(ci): list benchmarks among fixed hosted dependencies | Tianyi Cui | 2026-09-06 |
| `b74411d9` | test(bench): calibrate reopen budget for standard two-CPU CI | Tianyi Cui | 2026-09-06 |
| `f75aabcb` | test(ci): run required benchmarks on standard hosted Linux | Tianyi Cui | 2026-09-06 |
| `ce2197aa` | docs(agent-note): propose system prompt surface and in-history updates | Tianyi Cui | 2026-09-05 |
| `eece831b` | Merge pull request #3629 from deepseek-harness/optimize/python-runtime-selfhosted | Tianyi Cui | 2026-09-06 |
| `000cd7e7` | Merge master and reconcile platform failover documentation | Tianyi Cui | 2026-09-06 |
| `d15aaee2` | Merge pull request #3627 from deepseek-harness/optimize/release-rehearsal-selfhosted | Tianyi Cui | 2026-09-06 |
| `37d3ec16` | ci: address Windows runtime routing and isolation review | Tianyi Cui | 2026-09-06 |
| `ed183b1b` | Merge pull request #3630 from deepseek-harness/fix/agent-message-spacing | Tianyi Cui | 2026-09-06 |
| `a1188bbf` | ci: contain release temporary installs and document shared routing | Tianyi Cui | 2026-09-06 |
| `ceb3136b` | ci: size PR previews on measured standard hosted runners (#3628) | Tianyi Cui | 2026-09-06 |
| … | … 322 more | … | … |

## Files changed by category

| Category | Count | Sample files |
|---|---|---|
| DOCS | 2101 | `.agents/notes/README.i18n.yaml`<br>`.agents/notes/README.md`<br>`.agents/notes/README.zh.md` |
| CORE | 1236 | `.agents/notes/archived/architecture/2026-07-02-fs-per-session-cwd.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-07-02-fs-per-session-cwd.md`<br>`.agents/notes/archived/architecture/2026-07-02-fs-per-session-cwd.zh.md` |
| CLIENT | 214 | `apps/web/package.json`<br>`apps/web/tests/chat-long-interactions.e2e.ts`<br>`apps/web/tests/chat-scroll-contract.e2e.ts` |
| OTHER | 77 | `.gitattributes`<br>`.gitignore`<br>`apps/cli/README.i18n.yaml` |
| BUILD | 70 | `.agents/notes/archived/testing/2026-07-30-vitest-jsdom-webstorage-ownership.i18n.yaml`<br>`.agents/notes/archived/testing/2026-07-30-vitest-jsdom-webstorage-ownership.md`<br>`.agents/notes/archived/testing/2026-07-30-vitest-jsdom-webstorage-ownership.zh.md` |
| TEST | 54 | `apps/cli/tests/args.spec.ts`<br>`apps/cli/tests/built-bin.e2e.ts`<br>`apps/cli/tests/fixtures/dsh-badge/snapshot.ts` |
| STREAM | 46 | `.agents/notes/archived/architecture/2026-07-05-subagent-provider-lifecycle-events.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-07-05-subagent-provider-lifecycle-events.md`<br>`.agents/notes/archived/architecture/2026-07-05-subagent-provider-lifecycle-events.zh.md` |
| HOST | 41 | `packages/host/README.i18n.yaml`<br>`packages/host/README.md`<br>`packages/host/README.zh.md` |
| REACT | 41 | `.agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.i18n.yaml`<br>`.agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.md`<br>`.agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.zh.md` |
| API | 32 | `packages/api/gateway/README.i18n.yaml`<br>`packages/api/gateway/README.md`<br>`packages/api/gateway/README.zh.md` |
| MODEL | 31 | `packages/llm/README.i18n.yaml`<br>`packages/llm/README.md`<br>`packages/llm/README.zh.md` |
| SECURITY | 23 | `.agents/notes/archived/architecture/2026-07-29-request-level-llm-config-credentials.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-07-29-request-level-llm-config-credentials.md`<br>`.agents/notes/archived/architecture/2026-07-29-request-level-llm-config-credentials.zh.md` |
| INTERACTION | 5 | `packages/interaction/commands/package.json`<br>`packages/interaction/permission-presets/package.json`<br>`packages/interaction/tool-ask-user/package.json` |

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
| `CR-0001` | REACT | P2 | `.agents/notes/archived/bug-fix/2026-07-2` → `.agents/notes/archived/bug-fix/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.i18n.yaml — verify Flutter parity  |
| `CR-0002` | REACT | P2 | `.agents/notes/archived/bug-fix/2026-07-2` → `.agents/notes/archived/bug-fix/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.md — verify Flutter parity for beh |
| `CR-0003` | REACT | P2 | `.agents/notes/archived/bug-fix/2026-07-2` → `.agents/notes/archived/bug-fix/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.zh.md — verify Flutter parity for  |
| `CR-0004` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-25-workspace-ui-product-flow.i18n.yaml — verify Flutter par |
| `CR-0005` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-25-workspace-ui-product-flow.md — verify Flutter parity for |
| `CR-0006` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-25-workspace-ui-product-flow.zh.md — verify Flutter parity  |
| `CR-0007` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-26-ptc-dispatch-ui-foundation.i18n.yaml — verify Flutter pa |
| `CR-0008` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-26-ptc-dispatch-ui-foundation.md — verify Flutter parity fo |
| `CR-0009` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-26-ptc-dispatch-ui-foundation.zh.md — verify Flutter parity |
| `CR-0010` | REACT | P2 | `.agents/notes/archived/feature/2026-07-3` → `.agents/notes/archived/feature/2026-07-3` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-31-gui-full-access-confirmation.i18n.yaml — verify Flutter  |
| `CR-0011` | REACT | P2 | `.agents/notes/archived/feature/2026-07-3` → `.agents/notes/archived/feature/2026-07-3` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-31-gui-full-access-confirmation.md — verify Flutter parity  |
| `CR-0012` | REACT | P2 | `.agents/notes/archived/feature/2026-07-3` → `.agents/notes/archived/feature/2026-07-3` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-31-gui-full-access-confirmation.zh.md — verify Flutter pari |
| `CR-0013` | REACT | P2 | `.agents/notes/archived/feature/2026-08-0` → `.agents/notes/archived/feature/2026-08-0` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-08-05-pwsh-ui-bash-parity.i18n.yaml — verify Flutter parity fo |
| `CR-0014` | REACT | P2 | `.agents/notes/archived/feature/2026-08-0` → `.agents/notes/archived/feature/2026-08-0` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-08-05-pwsh-ui-bash-parity.md — verify Flutter parity for behav |
| `CR-0015` | REACT | P2 | `.agents/notes/archived/feature/2026-08-0` → `.agents/notes/archived/feature/2026-08-0` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-08-05-pwsh-ui-bash-parity.zh.md — verify Flutter parity for be |
| `CR-0016` | REACT | P2 | `.agents/notes/archived/simplification/20` → `.agents/notes/archived/simplification/20` | Detected | [REACT] File changed: .agents/notes/archived/simplification/2026-08-04-remove-tui-package.i18n.yaml — verify Flutter par |
| `CR-0017` | REACT | P2 | `.agents/notes/archived/simplification/20` → `.agents/notes/archived/simplification/20` | Detected | [REACT] File changed: .agents/notes/archived/simplification/2026-08-04-remove-tui-package.md — verify Flutter parity for |
| `CR-0018` | REACT | P2 | `.agents/notes/archived/simplification/20` → `.agents/notes/archived/simplification/20` | Detected | [REACT] File changed: .agents/notes/archived/simplification/2026-08-04-remove-tui-package.zh.md — verify Flutter parity  |
| `CR-0019` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-07-19-gui-web-client-architecture.i18n.yaml — verify F |
| `CR-0020` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-07-19-gui-web-client-architecture.md — verify Flutter  |
| `CR-0021` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-07-19-gui-web-client-architecture.zh.md — verify Flutt |
| `CR-0022` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml — verify F |
| `CR-0023` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md — verify Flutter  |
| `CR-0024` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md — verify Flutt |
| `CR-0025` | REACT | P2 | `.agents/notes/implemented/bug-fix/2026-0` → `.agents/notes/implemented/bug-fix/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/bug-fix/2026-07-28-web-gui-feedback-loop.i18n.yaml — verify Flutter pari |
| `CR-0026` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-25-workspace-ui-product-flow.i18n.yaml — verify Flutter  |
| `CR-0027` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-26-ptc-dispatch-ui-foundation.i18n.yaml — verify Flutter |
| `CR-0028` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.i18n.yaml — verify Flutt |
| `CR-0029` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-08-05-pwsh-ui-bash-parity.i18n.yaml — verify Flutter parity |
| `CR-0030` | REACT | P2 | `.agents/notes/implemented/simplification` → `.agents/notes/implemented/simplification` | Detected | [REACT] File changed: .agents/notes/implemented/simplification/2026-08-04-remove-tui-package.i18n.yaml — verify Flutter  |
| `CR-0031` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.i18n.yaml — verify Flutter p |
| `CR-0032` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.md — verify Flutter parity f |
| `CR-0033` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.zh.md — verify Flutter parit |
| `CR-0034` | REACT | P2 | `apps/web/package.json` → `apps/web/package.json` | Detected | [REACT] File changed: apps/web/package.json — verify Flutter parity for behavior/state fallback |
| `CR-0035` | REACT | P2 | `apps/web/tests/chat-long-interactions.e2` → `apps/web/tests/chat-long-interactions.e2` | Detected | [REACT] File changed: apps/web/tests/chat-long-interactions.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0036` | REACT | P2 | `apps/web/tests/chat-scroll-contract.e2e.` → `apps/web/tests/chat-scroll-contract.e2e.` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-contract.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0037` | REACT | P2 | `apps/web/tests/clickable-links-gallery.e` → `apps/web/tests/clickable-links-gallery.e` | Detected | [REACT] File changed: apps/web/tests/clickable-links-gallery.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0038` | REACT | P2 | `apps/web/tests/expected/clickable-links-` → `apps/web/tests/expected/clickable-links-` | Detected | [REACT] File changed: apps/web/tests/expected/clickable-links-gallery/ui.expected.md — verify Flutter parity for behavio |
| `CR-0039` | REACT | P2 | `apps/web/tests/feedback-command.e2e.ts` → `apps/web/tests/feedback-command.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/feedback-command.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0040` | REACT | P2 | `apps/web/tests/feedback-release.e2e.ts` → `apps/web/tests/feedback-release.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/feedback-release.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0041` | REACT | P2 | `apps/web/tests/hmr-live.e2e.ts` → `apps/web/tests/hmr-live.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/hmr-live.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0042` | REACT | P2 | `apps/web/tests/lifecycle-chrome.e2e.ts` → `apps/web/tests/lifecycle-chrome.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/lifecycle-chrome.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0043` | REACT | P2 | `apps/web/tests/message-actions.e2e.ts` → `apps/web/tests/message-actions.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/message-actions.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0044` | REACT | P2 | `apps/web/tests/navigation-panes.e2e.ts` → `apps/web/tests/navigation-panes.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/navigation-panes.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0045` | REACT | P2 | `apps/web/tests/preview-boot.e2e.ts` → `apps/web/tests/preview-boot.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/preview-boot.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0046` | REACT | P2 | `apps/web/tests/ptc-round.e2e.ts` → `apps/web/tests/ptc-round.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/ptc-round.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0047` | REACT | P2 | `apps/web/tests/queue-actions.e2e.ts` → `apps/web/tests/queue-actions.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/queue-actions.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0048` | REACT | P2 | `apps/web/tests/queue-image.e2e.ts` → `apps/web/tests/queue-image.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/queue-image.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0049` | REACT | P2 | `apps/web/tests/rail-search-expand.e2e.ts` → `apps/web/tests/rail-search-expand.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/rail-search-expand.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0050` | REACT | P2 | `apps/web/tests/replay-round-trip.e2e.ts` → `apps/web/tests/replay-round-trip.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/replay-round-trip.e2e.ts — verify Flutter parity for behavior/state fallback |
| … | … | … | … | … | … 205 more |

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
_Report generated by upstream-sync • upstream d347e703 → b0a7d2ce • local 003422c9_
