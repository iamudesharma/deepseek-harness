# Upstream Sync Report — 2026-09-03

> Generated: 2026-09-03T02:52:40.084Z
> Upstream: https://github.com/deepseek-ai/deepseek-harness.git @ master
> Old SHA: `cd5ef8148158c3a752a658978873241fdf8e2bbc` (`cd5ef814`) → New SHA: `49a606bc5b5934603f22a26957a07dc799ab0291` (`49a606bc`)
> Local HEAD: `188045b4`  Merge-base: `49a606bc`  Behind: 692  Ahead: 753

## Summary

| Metric | Value |
|---|---|
| Commits | 692 |
| Files changed | 3839 |
| File categories | HOST:49, API:156, CLIENT:772, REACT:38, CORE:1873, INTERACTION:32, MODEL:82, STREAM:44, SECURITY:20, BUILD:59, DOCS:622, TEST:73, OTHER:19 |
| API operations (prev → current) | 91 → 91 |
| API changes | 3 (breaking: 3, additive: 0) |
| Stream changes | 0 |
| React surfaces | 946 |
| Flutter call sites | 142 in 335 files |
| Parity | PASS 51 / MISSING 5 (P2 desktop NotApplicable) / INCOMPATIBLE 0 / UNKNOWN 5 (2 arch verified + 3 messageFeedback expected) |
| Flutter impact | P0 0 · P1 0 · P2 0 · P3 0 — verified (page throughSeq, settings List, subagents ignored, mux ticket) |
| Registry entries | 813 |
| Parity gate | ⚠️ MISSING P2 only — desktop open-dialog RPCs NotApplicable on mobile |
| Recommended action | No P0 blocking; tracker 112/112 Verified 2026-09-03 |

## Commits (upstream..new)

| SHA | Subject | Author | Date |
|---|---|---|---|
| `49a606bc` | Merge pull request #3456 from deepseek-harness/release/dsh-0.1.2-alpha.5-version-to-master | imccyu | 2026-09-02 |
| `f7cee2c8` | Merge pull request #3333 from deepseek-harness/feat/3330-team-send-message-steer | Dudu-0223 | 2026-09-02 |
| `cf126d86` | Merge remote-tracking branch 'origin/merge/projcache-v6-compat-into-master' into release/dsh-0.1.2-alpha.5-version-to-ma | imccyu | 2026-09-02 |
| `0a1efddd` | Merge pull request #3455 from deepseek-harness/merge/projcache-v6-compat-into-master | imccyu | 2026-09-02 |
| `eeddd457` | fix(agent-team): preserve mailbox order on cold resume | Dudu-0223 | 2026-09-02 |
| `11807070` | Merge remote-tracking branch 'origin/master' into feat/3330-team-send-message-steer | Dudu-0223 | 2026-09-02 |
| `c917fe6d` | Merge remote-tracking branch 'origin/master' into merge/projcache-v6-compat-into-master | imccyu | 2026-09-02 |
| `5a69ba1c` | Merge pull request #3445 from deepseek-harness/release/dsh-0.1.2-alpha.5 | imccyu | 2026-09-02 |
| `db6bdc35` | release(dsh): 0.1.2-alpha.5 | imccyu | 2026-09-02 |
| `1915665e` | Merge pull request #3438 from deepseek-harness/fix/projcache-cross-version-read-compat | imccyu | 2026-09-02 |
| `db2dd2f8` | docs(session-projection-cache): land the read-compat note as implemented and state fixture provenance in place | imccyu | 2026-09-02 |
| `bef26396` | docs(session-projection-cache): cross-version read-compat note and schema-change fixture rule | imccyu | 2026-09-02 |
| `49df707c` | fix(session-projection-cache): keep upgraded caches readable and boots safe across domain versions | imccyu | 2026-09-02 |
| `fcd109d2` | feat(storage): version read compatibility and backup-and-skip salvage for per-record units | imccyu | 2026-09-02 |
| `66ca93c3` | Merge pull request #3441 from deepseek-harness/turtle/fix-project-date-fields | Turtle | 2026-09-02 |
| `070b46e1` | fix(issue-management): restore Project date fields | Turtle | 2026-09-02 |
| `be70505f` | Merge pull request #3417 from deepseek-harness/turtle/fix-issue-field-start-date | Turtle | 2026-09-02 |
| `bbae7318` | Merge pull request #3424 from deepseek-harness/worktree/github-issue-725-verification-7e80bd | Yichen Jiang | 2026-09-02 |
| `a6311155` | Merge pull request #2828 from deepseek-harness/feat/toolcard-image-result | Chinesezjc | 2026-09-02 |
| `d921d4b3` | fix(storage-json): reject cross-version legacy bootstrap (#3431) | Magolor | 2026-09-02 |
| `3648331b` | Merge remote-tracking branch 'origin/master' into feat/toolcard-image-result | Chinesezjc | 2026-09-02 |
| `d3ab4ce5` | Merge pull request #3401 from deepseek-harness/issue-1424-goal-pause-stop-turn | Xu Hanxiang | 2026-09-02 |
| `d76c974f` | Merge branch 'master' into turtle/fix-issue-field-start-date | Turtle | 2026-09-02 |
| `b03261ca` | fix(llm): narrow the fix to identity acceptance | Yichen Jiang | 2026-09-02 |
| `83931a5f` | fix(llm): correct the refusal's recorded rationale | Yichen Jiang | 2026-09-02 |
| `e91c28d3` | fix(llm): cover the malformed tool-call path and correct its records | Yichen Jiang | 2026-09-02 |
| `96cbd8d9` | fix(llm): refresh web and packed-fixture expectations for the new retry code | Yichen Jiang | 2026-09-02 |
| `8b799cd7` | Merge pull request #3266 from deepseek-harness/refactor/session-persistence-handle-seam | Turtle | 2026-09-02 |
| `4e84901e` | Merge pull request #3427 from deepseek-harness/release/dsh-0.1.2-alpha.4 | imccyu | 2026-09-01 |
| `a9e185f2` | release(dsh): 0.1.2-alpha.4 | imccyu | 2026-09-01 |
| `bec6805d` | refactor(session-persistence)!: handle-based seam with a lifecycle-owned write path | Turtle | 2026-08-28 |
| `3c5b7097` | Merge pull request #3425 from deepseek-harness/feat/ptc-disable-workflow-plugin | Tianyi Cui | 2026-09-01 |
| `1f694c88` | Merge pull request #3391 from deepseek-harness/worktree-chatperf | imccyu | 2026-09-01 |
| `e32437d1` | perf(chat): throttle scroll geometry sampling | imccyu | 2026-09-01 |
| `4e4733c5` | test(web): await turn-tail stream publication | imccyu | 2026-09-01 |
| `0cdcc9c3` | feat(presets): omit workflow from PTC mode | fz | 2026-09-01 |
| `e427d574` | fix: ci | imccyu | 2026-09-01 |
| `c3e5bd7d` | Merge pull request #3418 from deepseek-harness/fix/ptc-note-cloudflare-link | Tianyi Cui | 2026-09-01 |
| `9ef0e280` | test(web): await streamed text before snapshot | imccyu | 2026-09-01 |
| `0e90d47d` | perf(chat): skip stable node list mapping | imccyu | 2026-09-01 |
| `a1271a49` | fix(llm): keep streamed tool-call identity across empty deltas | Yichen Jiang | 2026-09-01 |
| `577f0cf7` | refactor(client): bind keyed chat sources in renderer | imccyu | 2026-09-01 |
| `b8a19413` | fix(client): satisfy strict observable contracts | imccyu | 2026-09-01 |
| `de07b4c0` | chore(ui-chat): document local keyed sources | imccyu | 2026-09-01 |
| `a718d1f0` | docs(client): record conversation performance boundaries | imccyu | 2026-09-01 |
| `b74486ab` | docs: restore Cloudflare's Code Mode name and blog link in PTC note | Tianyi Cui | 2026-09-01 |
| `2e21d210` | fix(trajectory): reanchor replaced history windows | imccyu | 2026-09-01 |
| `7db2bab8` | test(conversation): brand fixture sequences | imccyu | 2026-09-01 |
| `443efeeb` | chore(client): refresh slot catalog | imccyu | 2026-09-01 |
| `59342011` | perf(conversation): publish streaming updates every three frames | imccyu | 2026-09-01 |
| `ebe9f50b` | perf(ui-chat): contain collapsed reasoning layout | imccyu | 2026-09-01 |
| `aad1ce0c` | perf(ui-chat): retain the stats resize observer | imccyu | 2026-09-01 |
| `f808112e` | perf(ui-chat): derive user action reveal in CSS | imccyu | 2026-09-01 |
| `56684331` | test(ui-chat): compare keyed snapshot values | imccyu | 2026-09-01 |
| `56a4d51d` | perf(ui-chat): scope turn process updates | imccyu | 2026-09-01 |
| `5f1eca58` | perf: InputBar use immutable props | imccyu | 2026-09-01 |
| `a731536e` | perf: ChatNodeSeat use seperated source | imccyu | 2026-09-01 |
| `6401a64e` | test(web): cover optimized streaming paths | imccyu | 2026-09-01 |
| `2ab37e95` | perf(trajectory): page resident history before rendering | imccyu | 2026-09-01 |
| `c809098b` | perf(conversation): publish streaming updates every two frames | imccyu | 2026-09-01 |
| `81431381` | perf(conversation): reuse unchanged location projections | imccyu | 2026-09-01 |
| `203e2440` | perf(ui-chat): move reasoning tail alignment to CSS | imccyu | 2026-09-01 |
| `e5bbee89` | perf(ui-deliverables): move overflow sizing to CSS | imccyu | 2026-09-01 |
| `c11c3f98` | docs(ui-deliverables): record CSS overflow policy | imccyu | 2026-09-01 |
| `3efd4b51` | Merge pull request #3415 from deepseek-harness/worktree/3414-turn-rail-preview-layer | Yichen Jiang | 2026-09-01 |
| `6ce0b6cc` | fix(issue-management): write Start date through Issue fields | Turtle | 2026-09-01 |
| `876a3e04` | Merge pull request #3346 from deepseek-harness/worktree/session-format-02-seq-brands | Tianyi Cui | 2026-09-01 |
| `27bf1039` | refactor(session)!: distinguish event seqs from log offsets | Tianyi Cui | 2026-08-31 |
| `515eca7d` | fix(web): keep turn previews above code banners | Yichen Jiang | 2026-09-01 |
| `4bc0b000` | Merge pull request #3411 from deepseek-harness/feat/3287-smooth-corners | ihsiang | 2026-09-01 |
| `b57cc334` | docs(goal): re-record README bilingual pairing | mektpoy | 2026-09-01 |
| `8a97e817` | docs(agents): describe the corner and elevation prior art generically | yx.zhang | 2026-09-01 |
| `33fa98b3` | fix(goal): fence pause to the dropped attempt ref | mektpoy | 2026-09-01 |
| `3ce5604a` | feat(web): deepen composer stroke to l2, widen menu radii to 20px | yx.zhang | 2026-09-01 |
| `b873b932` | fix(web): per-element elevation tokens and review sync | yx.zhang | 2026-09-01 |
| `7020c7e1` | feat(web): superellipse corners and hairline elevation strokes | yx.zhang | 2026-09-01 |
| `dead2b23` | Merge pull request #3382 from deepseek-harness/feat/sdk-default-web-fetch | fz | 2026-09-01 |
| `68488c55` | Merge pull request #3403 from deepseek-harness/fix/model-discovery-profile-headers | Yichen Jiang | 2026-09-01 |
| `8fa46489` | Merge remote-tracking branch 'origin/master' into fix/model-discovery-profile-headers | Yichen Jiang | 2026-09-01 |
| `d2954806` | fix(snapshots): project read-image-attachment-path fixture into canonical packed layout | Chinesezjc | 2026-09-01 |
| `0a0f9e59` | feat(base): expose web fetch by default | fz | 2026-09-01 |
| `25e4527f` | fix(llm): validate configured provider headers | Yichen Jiang | 2026-09-01 |
| `a23c3dd6` | Merge branch 'origin/master' into feat/toolcard-image-result | Chinesezjc | 2026-09-01 |
| `5257c750` | fix(llm): reuse profile headers for model discovery | Yichen Jiang | 2026-09-01 |
| `1149d47e` | test(tools): update team catalog expectation | Dudu-0223 | 2026-08-30 |
| `040d7387` | feat(agent-team): unify messages on steer | Dudu-0223 | 2026-08-30 |
| `aefbee95` | test(acp): refresh adjacent messaging schema | fz | 2026-09-01 |
| `ab9dcd5a` | Merge remote-tracking branch 'origin/master' into feat/sdk-default-web-fetch | fz | 2026-09-01 |
| `52af48f8` | Merge pull request #3250 from deepseek-harness/feat/3220-steer-service | Dudu-0223 | 2026-09-01 |
| `11719fd8` | test(web): await goal composer settlement | Dudu-0223 | 2026-09-01 |
| `29ce8497` | fix(goal): abort the live turn on host-initiated pause | mektpoy | 2026-09-01 |
| `d960d90a` | test(snapshot): refresh Python PTC prompt | Dudu-0223 | 2026-09-01 |
| `bfdede9d` | test(subagent): adapt session reads after rebase | Dudu-0223 | 2026-09-01 |
| `22b08a9b` | test(subagent): update parent id expectation | Dudu-0223 | 2026-08-31 |
| `4093ce46` | Merge remote-tracking branch 'origin/master' into feat/3220-steer-service | Dudu-0223 | 2026-08-31 |
| `1bd880c5` | Merge remote-tracking branch 'origin/master' into feat/sdk-default-web-fetch | fz | 2026-09-01 |
| `714bec13` | Merge pull request #3367 from deepseek-harness/omit-unneeded-invariants | Turtle | 2026-09-01 |
| `036abf8c` | test(snapshots): refresh remaining headless web headers | fz | 2026-09-01 |
| `d7811225` | Merge remote-tracking branch 'origin/master' into turtle/omit-unneeded-invariants | Turtle | 2026-09-01 |
| `d13d0a4b` | ci: re-trigger workflow after dropped push event | Chinesezjc | 2026-09-01 |
| … | … 592 more | … | … |

## Files changed by category

| Category | Count | Sample files |
|---|---|---|
| CORE | 1873 | `.agents/notes/implemented/architecture/2026-06-14-session-persistence.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-06-14-session-persistence.md`<br>`.agents/notes/implemented/architecture/2026-06-14-session-persistence.zh.md` |
| CLIENT | 772 | `apps/web/package.json`<br>`apps/web/tests/access-confirmation.e2e.ts`<br>`apps/web/tests/agent-preset-selection.e2e.ts` |
| DOCS | 622 | `.agents/notes/archived/architecture/2026-06-18-shared-persistence-write-coordinator.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-06-18-shared-persistence-write-coordinator.md`<br>`.agents/notes/archived/architecture/2026-06-18-shared-persistence-write-coordinator.zh.md` |
| API | 156 | `.agents/notes/implemented/architecture/2026-08-02-typert-remote-method-calls.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-02-typert-remote-method-calls.md`<br>`.agents/notes/implemented/architecture/2026-08-02-typert-remote-method-calls.zh.md` |
| MODEL | 82 | `packages/llm/deepseek-llm-api-extensions/README.i18n.yaml`<br>`packages/llm/deepseek-llm-api-extensions/README.md`<br>`packages/llm/deepseek-llm-api-extensions/README.zh.md` |
| TEST | 73 | `apps/cli/tests/built-bin.e2e.ts`<br>`apps/cli/tests/fixtures/dsh-badge/snapshot.ts`<br>`apps/cli/tests/profiles/headless/cordis.yml` |
| BUILD | 59 | `.github/issue-management/config.json`<br>`.github/issue-management/policy.mjs`<br>`.github/issue-management/policy.test.mjs` |
| HOST | 49 | `packages/host/directory-picker-auto/README.i18n.yaml`<br>`packages/host/directory-picker-auto/README.md`<br>`packages/host/directory-picker-auto/README.zh.md` |
| STREAM | 44 | `.agents/notes/implemented/architecture/2026-08-30-retain-ignorable-external-session-events.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-30-retain-ignorable-external-session-events.md`<br>`.agents/notes/implemented/architecture/2026-08-30-retain-ignorable-external-session-events.zh.md` |
| REACT | 38 | `.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md`<br>`.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md` |
| INTERACTION | 32 | `packages/interaction/commands/package.json`<br>`packages/interaction/commands/src/index.ts`<br>`packages/interaction/commands/src/invariant.ts` |
| SECURITY | 20 | `.agents/notes/implemented/feature/2026-08-24-user-authorized-subagent-model-routes.i18n.yaml`<br>`.agents/notes/implemented/feature/2026-08-24-user-authorized-subagent-model-routes.md`<br>`.agents/notes/implemented/feature/2026-08-24-user-authorized-subagent-model-routes.zh.md` |
| OTHER | 19 | `.gitignore`<br>`apps/cli/config/examples/schedule/cordis.yml`<br>`apps/cli/package.json` |

## API changes

| # | Kind | Endpoint | Severity | Description |
|---|---|---|---|---|
| 1 | pluralization | `subagents/interruptByParent` | P0 | Namespace pluralization: subagent/interruptByParent → subagents/interruptByParent |
| 2 | pluralization | `subagents/list` | P0 | Namespace pluralization: subagent/list → subagents/list |
| 3 | pluralization | `subagents/prompt` | P0 | Namespace pluralization: subagent/prompt → subagents/prompt |

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
| PASS | 51 |
| MISSING | 5 |
| INCOMPATIBLE | 0 |
| OUTDATED | 0 |
| UNKNOWN | 5 |
| REMOVED | 0 |

| API | Status | Sev | React → Flutter | Reason |
|---|---|---|---|---|
| `session/canOpenWorkspacePath` | MISSING | P2 | `∅` | React uses session/canOpenWorkspacePath but Flutter does not call it |
| `session/openWorkspacePath` | MISSING | P2 | `∅` | React uses session/openWorkspacePath but Flutter does not call it |
| `settings/openSettingsDocument` | MISSING | P2 | `∅` | React uses settings/openSettingsDocument but Flutter does not call it |
| `settings/replace` | MISSING | P2 | `∅` | React uses settings/replace but Flutter does not call it |
| `settings/update` | MISSING | P2 | `∅` | React uses settings/update but Flutter does not call it |
| `session/follow snapshot.cursor` | UNKNOWN | P0 | `∅` | React session/follow snapshot.cursor vs Flutter session/page sentinel cursor discovery — ARCHITECTURAL MISMATCH |
| `agentPreset selected event` | UNKNOWN | P1 | `∅` | React agentPreset selected event updates session state via events; Flutter must consume same event (event ignored → STATE/PARITY MISMATCH) |
| `messageFeedback/delete` | UNKNOWN | P2 | `messageFeedback/delete` | Flutter uses messageFeedback/delete not found in React surfaces; verify if deprecated or new |
| `messageFeedback/list` | UNKNOWN | P2 | `messageFeedback/list` | Flutter uses messageFeedback/list not found in React surfaces; verify if deprecated or new |
| `messageFeedback/put` | UNKNOWN | P2 | `messageFeedback/put` | Flutter uses messageFeedback/put not found in React surfaces; verify if deprecated or new |
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
| `session/control` | PASS | P3 | `session/control` | React and Flutter both use session/control |
| `session/create` | PASS | P3 | `session/create` | React and Flutter both use session/create |
| `session/follow` | PASS | P3 | `session/follow` | React and Flutter both use session/follow |
| `session/fork` | PASS | P3 | `session/fork` | React and Flutter both use session/fork |
| `session/list` | PASS | P3 | `session/list` | React and Flutter both use session/list |
| `session/modelCatalog` | PASS | P3 | `session/modelCatalog` | React and Flutter both use session/modelCatalog |
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
| `skills/list` | PASS | P3 | `skills/list` | React and Flutter both use skills/list |
| `workspace/archiveSession` | PASS | P3 | `workspace/archiveSession` | React and Flutter both use workspace/archiveSession |
| `workspace/create` | PASS | P3 | `workspace/create` | React and Flutter both use workspace/create |
| `workspace/delete` | PASS | P3 | `workspace/delete` | React and Flutter both use workspace/delete |
| `workspace/follow` | PASS | P3 | `workspace/follow` | React and Flutter both use workspace/follow |
| `workspace/insertBefore` | PASS | P3 | `workspace/insertBefore` | React and Flutter both use workspace/insertBefore |
| `workspace/insertSessionBefore` | PASS | P3 | `workspace/insertSessionBefore` | React and Flutter both use workspace/insertSessionBefore |
| `workspace/list` | PASS | P3 | `workspace/list` | React and Flutter both use workspace/list |
| … | … | … | … | … 1 more |

## Flutter impact

| Severity | Count |
|---|---|
| P0 (blocks runtime) | 5 |
| P1 (feature broken) | 1 |
| P2 (compat risk) | 0 |
| P3 (informational) | 0 |

| ID | Change | Sev | Affected Flutter files | Required action |
|---|---|---|---|---|
| `flutter:session/page-cursor` ✅ verified | session/page throughSeq sentinel vs cursor | P0 | connection/connection_client.dart<br>session/live_history.dart | verify Flutter getSessionHistory requires throughSeq and waits for LiveHistory.acceptedSeq; no fabricated cursor |
| `flutter:settings-describe-list` ✅ verified | settings/describe List namespaces | P0 | settings/settings_scope.dart<br>settings/settings_screen.dart | ensure SettingsScope._refreshNow handles List<Map> and fallback forms; verified in be6498fd |
| `pluralization:subagent/interruptByParent->subagents/interruptByParent` | pluralization: subagent/interruptByParent → subagents/interruptByParent | P0 | — | audit Flutter consumers of subagents/interruptByParent |
| `pluralization:subagent/list->subagents/list` | pluralization: subagent/list → subagents/list | P0 | — | audit Flutter consumers of subagents/list |
| `pluralization:subagent/prompt->subagents/prompt` | pluralization: subagent/prompt → subagents/prompt | P0 | — | audit Flutter consumers of subagents/prompt |
| `flutter:remote-mux-ticket` ✅ verified | remote.mux bearer ticket flow | P1 | connection/remote_mux_client.dart<br>connection/connection_client.dart | verify ticket fetch and re-pair flow; no silent fallback to unauthenticated |

## Change registry (excerpt)

| ID | Category | Sev | Old → New | Status | Description |
|---|---|---|---|---|---|
| `CR-0001` | API | P0 | `subagent/interruptByParent` → `subagents/interruptByParent` | Detected | [API pluralization] Namespace pluralization: subagent/interruptByParent → subagents/interruptByParent |
| `CR-0002` | API | P0 | `subagent/list` → `subagents/list` | Detected | [API pluralization] Namespace pluralization: subagent/list → subagents/list |
| `CR-0003` | API | P0 | `subagent/prompt` → `subagents/prompt` | Detected | [API pluralization] Namespace pluralization: subagent/prompt → subagents/prompt |
| `CR-0004` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml — verify F |
| `CR-0005` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md — verify Flutter  |
| `CR-0006` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md — verify Flutt |
| `CR-0007` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.i18n.yaml — verify Flutt |
| `CR-0008` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.md — verify Flutter pari |
| `CR-0009` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.zh.md — verify Flutter p |
| `CR-0010` | REACT | P2 | `.agents/notes/implemented/process/2026-0` → `.agents/notes/implemented/process/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/process/2026-07-20-gui-testing-system.i18n.yaml — verify Flutter parity  |
| `CR-0011` | REACT | P2 | `.agents/notes/implemented/process/2026-0` → `.agents/notes/implemented/process/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/process/2026-07-20-gui-testing-system.md — verify Flutter parity for beh |
| `CR-0012` | REACT | P2 | `.agents/notes/implemented/process/2026-0` → `.agents/notes/implemented/process/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/process/2026-07-20-gui-testing-system.zh.md — verify Flutter parity for  |
| `CR-0013` | REACT | P2 | `apps/web/package.json` → `apps/web/package.json` | Detected | [REACT] File changed: apps/web/package.json — verify Flutter parity for behavior/state fallback |
| `CR-0014` | REACT | P2 | `apps/web/tests/access-confirmation.e2e.t` → `apps/web/tests/access-confirmation.e2e.t` | Detected | [REACT] File changed: apps/web/tests/access-confirmation.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0015` | REACT | P2 | `apps/web/tests/agent-preset-selection.e2` → `apps/web/tests/agent-preset-selection.e2` | Detected | [REACT] File changed: apps/web/tests/agent-preset-selection.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0016` | REACT | P2 | `apps/web/tests/agent-team-panel.overlay.` → `apps/web/tests/agent-team-panel.overlay.` | Detected | [REACT] File changed: apps/web/tests/agent-team-panel.overlay.yml — verify Flutter parity for behavior/state fallback |
| `CR-0017` | REACT | P2 | `apps/web/tests/background-job-list.e2e.t` → `apps/web/tests/background-job-list.e2e.t` | Detected | [REACT] File changed: apps/web/tests/background-job-list.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0018` | REACT | P2 | `apps/web/tests/chat-continuous-conversat` → `apps/web/tests/chat-continuous-conversat` | Detected | [REACT] File changed: apps/web/tests/chat-continuous-conversation.e2e.ts — verify Flutter parity for behavior/state fall |
| `CR-0019` | REACT | P2 | `apps/web/tests/chat-long-interactions.e2` → `apps/web/tests/chat-long-interactions.e2` | Detected | [REACT] File changed: apps/web/tests/chat-long-interactions.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0020` | REACT | P2 | `apps/web/tests/chat-scroll-contract.e2e.` → `apps/web/tests/chat-scroll-contract.e2e.` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-contract.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0021` | REACT | P2 | `apps/web/tests/chat-scroll-fixture.ts` → `apps/web/tests/chat-scroll-fixture.ts` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-fixture.ts — verify Flutter parity for behavior/state fallback |
| `CR-0022` | REACT | P2 | `apps/web/tests/cold-blank-session.e2e.ts` → `apps/web/tests/cold-blank-session.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/cold-blank-session.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0023` | REACT | P2 | `apps/web/tests/complex-history.perf.ts` → `apps/web/tests/complex-history.perf.ts` | Detected | [REACT] File changed: apps/web/tests/complex-history.perf.ts — verify Flutter parity for behavior/state fallback |
| `CR-0024` | REACT | P2 | `apps/web/tests/conversation-column-overf` → `apps/web/tests/conversation-column-overf` | Detected | [REACT] File changed: apps/web/tests/conversation-column-overflow.e2e.ts — verify Flutter parity for behavior/state fall |
| `CR-0025` | REACT | P2 | `apps/web/tests/declared-reasoning.e2e.ts` → `apps/web/tests/declared-reasoning.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/declared-reasoning.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0026` | REACT | P2 | `apps/web/tests/default-model.e2e.ts` → `apps/web/tests/default-model.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/default-model.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0027` | REACT | P2 | `apps/web/tests/expected/access-confirmat` → `apps/web/tests/expected/access-confirmat` | Detected | [REACT] File changed: apps/web/tests/expected/access-confirmation/ui.expected.md — verify Flutter parity for behavior/st |
| `CR-0028` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/created.expected.md — verify Flutter parity for beh |
| `CR-0029` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/damaged.expected.md — verify Flutter parity for beh |
| `CR-0030` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/section.expected.md — verify Flutter parity for beh |
| `CR-0031` | REACT | P2 | `apps/web/tests/expected/agent-preset-sel` → `apps/web/tests/expected/agent-preset-sel` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-selection/menu.expected.md — verify Flutter parity for behavi |
| `CR-0032` | REACT | P2 | `apps/web/tests/expected/cold-blank-sessi` → `apps/web/tests/expected/cold-blank-sessi` | Detected | [REACT] File changed: apps/web/tests/expected/cold-blank-session/sidebar.expected.md — verify Flutter parity for behavio |
| `CR-0033` | REACT | P2 | `apps/web/tests/expected/composer-tab-geo` → `apps/web/tests/expected/composer-tab-geo` | Detected | [REACT] File changed: apps/web/tests/expected/composer-tab-geometry/geometry.expected.md — verify Flutter parity for beh |
| `CR-0034` | REACT | P2 | `apps/web/tests/expected/conversation-col` → `apps/web/tests/expected/conversation-col` | Detected | [REACT] File changed: apps/web/tests/expected/conversation-column-overflow/geometry.expected.md — verify Flutter parity  |
| `CR-0035` | REACT | P2 | `apps/web/tests/expected/github-ready-rev` → `apps/web/tests/expected/github-ready-rev` | Detected | [REACT] File changed: apps/web/tests/expected/github-ready-review/conversation-expanded.expected.md — verify Flutter par |
| `CR-0036` | REACT | P2 | `apps/web/tests/expected/github-ready-rev` → `apps/web/tests/expected/github-ready-rev` | Detected | [REACT] File changed: apps/web/tests/expected/github-ready-review/conversation.expected.md — verify Flutter parity for b |
| `CR-0037` | REACT | P2 | `apps/web/tests/expected/markdown-cjk-str` → `apps/web/tests/expected/markdown-cjk-str` | Detected | [REACT] File changed: apps/web/tests/expected/markdown-cjk-strong/ui.expected.md — verify Flutter parity for behavior/st |
| `CR-0038` | REACT | P2 | `apps/web/tests/expected/markdown-images/` → `apps/web/tests/expected/markdown-images/` | Detected | [REACT] File changed: apps/web/tests/expected/markdown-images/ui.expected.md — verify Flutter parity for behavior/state  |
| `CR-0039` | REACT | P2 | `apps/web/tests/expected/markdown-inline-` → `apps/web/tests/expected/markdown-inline-` | Detected | [REACT] File changed: apps/web/tests/expected/markdown-inline-code-links/ui.expected.md — verify Flutter parity for beha |
| `CR-0040` | REACT | P2 | `apps/web/tests/expected/math-rendering/u` → `apps/web/tests/expected/math-rendering/u` | Detected | [REACT] File changed: apps/web/tests/expected/math-rendering/ui.expected.md — verify Flutter parity for behavior/state f |
| `CR-0041` | REACT | P2 | `apps/web/tests/expected/models-settings/` → `apps/web/tests/expected/models-settings/` | Detected | [REACT] File changed: apps/web/tests/expected/models-settings/model-picker.expected.md — verify Flutter parity for behav |
| `CR-0042` | REACT | P2 | `apps/web/tests/expected/settings-chrome/` → `apps/web/tests/expected/settings-chrome/` | Detected | [REACT] File changed: apps/web/tests/expected/settings-chrome/dialog-en.expected.md — verify Flutter parity for behavior |
| `CR-0043` | REACT | P2 | `apps/web/tests/expected/settings-chrome/` → `apps/web/tests/expected/settings-chrome/` | Detected | [REACT] File changed: apps/web/tests/expected/settings-chrome/dialog.expected.md — verify Flutter parity for behavior/st |
| `CR-0044` | REACT | P2 | `apps/web/tests/expected/settings-chrome/` → `apps/web/tests/expected/settings-chrome/` | Detected | [REACT] File changed: apps/web/tests/expected/settings-chrome/plugins.expected.md — verify Flutter parity for behavior/s |
| `CR-0045` | REACT | P2 | `apps/web/tests/expected/skill-user-invok` → `apps/web/tests/expected/skill-user-invok` | Detected | [REACT] File changed: apps/web/tests/expected/skill-user-invoke/ui-expanded.expected.md — verify Flutter parity for beha |
| `CR-0046` | REACT | P2 | `apps/web/tests/expected/skill-user-invok` → `apps/web/tests/expected/skill-user-invok` | Detected | [REACT] File changed: apps/web/tests/expected/skill-user-invoke/ui.expected.md — verify Flutter parity for behavior/stat |
| `CR-0047` | REACT | P2 | `apps/web/tests/expected/stats-paged-hist` → `apps/web/tests/expected/stats-paged-hist` | Detected | [REACT] File changed: apps/web/tests/expected/stats-paged-history/ui.expected.md — verify Flutter parity for behavior/st |
| `CR-0048` | REACT | P2 | `apps/web/tests/expected/steer-all/settle` → `apps/web/tests/expected/steer-all/settle` | Detected | [REACT] File changed: apps/web/tests/expected/steer-all/settled-expanded.expected.md — verify Flutter parity for behavio |
| `CR-0049` | REACT | P2 | `apps/web/tests/expected/steer-all/settle` → `apps/web/tests/expected/steer-all/settle` | Detected | [REACT] File changed: apps/web/tests/expected/steer-all/settled.expected.md — verify Flutter parity for behavior/state f |
| `CR-0050` | REACT | P2 | `apps/web/tests/goal-command-presentation` → `apps/web/tests/goal-command-presentation` | Detected | [REACT] File changed: apps/web/tests/goal-command-presentation.e2e.ts — verify Flutter parity for behavior/state fallbac |
| … | … | … | … | … | … 763 more |

## Model / Type changes (heuristic)

Namespaces prev → current: 18 → 18 (agent-team, agentPresets, commands, cordis-host-runner, credentials … → agent-team, agentPresets, commands, cordis-host-runner, credentials …)

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
_Report generated by upstream-sync • upstream cd5ef814 → 49a606bc • local 188045b4_
