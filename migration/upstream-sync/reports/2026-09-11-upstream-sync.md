# Upstream Sync Report — 2026-09-11

> Generated: 2026-09-11T09:23:43.684Z
> Upstream: https://github.com/deepseek-ai/deepseek-harness.git @ master
> Old SHA: `5dda764ed3aa172535a7967b06ff95d9cbfe536a` (`5dda764e`) → New SHA: `c291e7961a515f6d7af9304e7fd1d257929aef26` (`c291e796`)
> Local HEAD: `2b8b3d40`  Merge-base: `b0a7d2ce`  Behind: 422  Ahead: 149

## Summary

| Metric | Value |
|---|---|
| Commits | 422 |
| Files changed | 2549 |
| File categories | HOST:38, API:83, CLIENT:663, REACT:17, CORE:1050, INTERACTION:31, MODEL:48, STREAM:15, SECURITY:19, BUILD:64, DOCS:400, TEST:52, OTHER:69 |
| API operations (prev → current) | 97 → 100 |
| API changes | 3 (breaking: 0, additive: 3) |
| Stream changes | 0 |
| React surfaces | 1191 |
| Flutter call sites | 172 in 382 files |
| Parity | PASS 56 / MISSING 3 / INCOMPATIBLE 0 / UNKNOWN 11 |
| Flutter impact | P0 2 · P1 1 · P2 3 · P3 0 |
| Registry entries | 683 |
| Parity gate | ❌ FAIL |
| Recommended action | P0 blocking — do not merge Flutter without fixes |

## Commits (upstream..new)

| SHA | Subject | Author | Date |
|---|---|---|---|
| `c291e796` | Merge pull request #3977 from deepseek-harness/worktree/release-0.1.5-sync-master | Yichen Jiang | 2026-09-10 |
| `e570e747` | Merge pull request #3962 from deepseek-harness/turtle/ci-smoke-20260910-1820 | Turtle | 2026-09-10 |
| `59f2e3be` | Merge release/dsh-0.1.5 version 0.1.5-rc.2 into master sync branch | Yichen Jiang | 2026-09-10 |
| `fb2c4b9e` | Merge pull request #3978 from deepseek-harness/worktree/release-dsh-0.1.5-rc.2 | Yichen Jiang | 2026-09-10 |
| `a3053034` | release(dsh): 0.1.5-rc.2 | Yichen Jiang | 2026-09-10 |
| `3bfcebe1` | Merge master into worktree/release-0.1.5-sync-master | Yichen Jiang | 2026-09-10 |
| `2107e469` | Merge pull request #3973 from deepseek-harness/worktree/release-0.1.5-backport-feedback-deliverables | Yichen Jiang | 2026-09-10 |
| `060323d8` | feat(web): backport feedback and file refinements to 0.1.5 | yixiangihsiang | 2026-09-10 |
| `0963bdd7` | test(python): control stray-output fragments for sealing coverage | turtle1999 | 2026-09-10 |
| `3b5daf10` | test(ci): verify current master on PR runners | turtle1999 | 2026-09-10 |
| `060ae6f3` | Merge pull request #3957 from deepseek-harness/fix/subprocess-linux-scope-empty-range | Turtle | 2026-09-10 |
| `42b50bd3` | Merge pull request #3828 from deepseek-harness/xtr/deprecate-session-event-readers | _Kerman | 2026-09-10 |
| `1050091d` | Merge pull request #3926 from deepseek-harness/ci/blacksmith-hosted-image-fixes | Chinesezjc | 2026-09-10 |
| `989b3d43` | Merge hosted-image test fixes for Blacksmith CI | turtle1999 | 2026-09-10 |
| `69005cb9` | Merge pull request #3860 from deepseek-harness/fix/parallel-macos-notarization | 07akioni | 2026-09-10 |
| `03770494` | ci: give the Linux coverage lane the hosted image's teardown budget | Chinesezjc | 2026-09-10 |
| `114e8c9b` | test: drop two host-paced assumptions the hosted image exposes | Chinesezjc | 2026-09-10 |
| `c4c2d163` | test(subprocess): align the teardown race with the settlement contract | Chinesezjc | 2026-09-10 |
| `def3f88b` | Merge pull request #3943 from deepseek-harness/fix/master-ci-corpus-css-pin | Turtle | 2026-09-10 |
| `3ece2784` | Merge pull request #3925 from deepseek-harness/turtle/dsh-cache-path | Turtle | 2026-09-10 |
| `87f32dc8` | docs(notes): record the hosted-image assumptions the coverage suite names | Chinesezjc | 2026-09-10 |
| `45c10ed2` | ci: give the Linux coverage lane the hosted image's teardown budget | Chinesezjc | 2026-09-10 |
| `f45ca2d9` | test: drop two host-paced assumptions the hosted image exposes | Chinesezjc | 2026-09-10 |
| `df709f44` | test(subprocess): align the teardown race with the settlement contract | Chinesezjc | 2026-09-10 |
| `ac5f8510` | test(directory-picker): probe the folder dialog class instead of the platform | Chinesezjc | 2026-09-10 |
| `aaa02a39` | fix(subprocess): settle a Linux scope left active with no processes | turtle1999 | 2026-09-10 |
| `0989a5cf` | Merge remote-tracking branch 'origin/master' into dshw/pr-deepseek-harness-deepseek-harness-3828 | _Kerman | 2026-09-10 |
| `42123ef0` | fix(desktop): tighten parallel notarization checks | 07akioni | 2026-09-10 |
| `ce94430e` | Merge master into fix/parallel-macos-notarization | 07akioni | 2026-09-10 |
| `25d554d4` | Merge pull request #3650 from deepseek-harness/worktree-feqatest | imccyu | 2026-09-10 |
| `6fc0064b` | Merge pull request #3914 from deepseek-harness/fix/bundle-speed | 07akioni | 2026-09-10 |
| `5a88e5c4` | docs(ci): state the full admitted failure class for the dockkit exemption | turtle1999 | 2026-09-10 |
| `632d42ee` | Merge remote-tracking branch 'origin/master' into dshw/pr-deepseek-harness-deepseek-harness-3828 | _Kerman | 2026-09-10 |
| `f74ca1e2` | fix(remote-mock): abort stream handle on consumer return | imccyu | 2026-09-10 |
| `4ffc774e` | test(settings): exercise settings through the whole-client fixture | imccyu | 2026-09-08 |
| `d58c5455` | test(api): migrate Session and Workspace specs to assembled clients | imccyu | 2026-09-08 |
| `627c0f74` | feat(test-support): assemble real clients with native test fixtures | imccyu | 2026-09-08 |
| `48d83eca` | refactor(client): share boot and transport integration points | imccyu | 2026-09-08 |
| `3d6fa12a` | feat(remote-mock): expose typed native mocks and controlled streams | imccyu | 2026-09-08 |
| `07187118` | docs(testing): define the native-mock client assembly tier | imccyu | 2026-09-08 |
| `8f85739d` | Merge pull request #3745 from deepseek-harness/worktree/composer-plus-menu | CreatixChu | 2026-09-10 |
| `529434e1` | fix(ci): admit any `.css` refusal for the dockkit corpus exemption | turtle1999 | 2026-09-10 |
| `ae7462c5` | test: clarify live SDK smoke completion acknowledgement | 07akioni | 2026-09-10 |
| `f63fdd89` | Merge pull request #3889 from deepseek-harness/turn-duration-hours-unit | lsdsjy | 2026-09-10 |
| `d0ba1a3c` | Merge remote-tracking branch 'origin/master' into worktree/composer-plus-menu | creatixchu | 2026-09-10 |
| `7910cd9e` | test(web): assert the shipped feedback command identity | creatixchu | 2026-09-10 |
| `ac495c0b` | Merge pull request #3934 from deepseek-harness/turtle/fix-weighted-approval-run-identity | Turtle | 2026-09-10 |
| `e7b8ebed` | fix(ci): identify approval review runs by workflow path | turtle1999 | 2026-09-10 |
| `c428e6ff` | Merge remote-tracking branch 'origin/master' into dshw/pr-deepseek-harness-deepseek-harness-3828 | _Kerman | 2026-09-10 |
| `249d5838` | feat(web): add hours to turn duration labels | lsdsjy | 2026-09-09 |
| `c09574fc` | Merge remote-tracking branch 'origin/master' into dshw/pr-deepseek-harness-deepseek-harness-3828 | _Kerman | 2026-09-10 |
| `9f27a454` | test: preserve immediate disposal and observe automatic terminal cleanup | 07akioni | 2026-09-10 |
| `aed83d29` | Merge remote-tracking branch 'origin/master' into worktree/composer-plus-menu | creatixchu | 2026-09-10 |
| `fff1ed7a` | fix(plan): keep command identity independent of optional runtime | creatixchu | 2026-09-10 |
| `c31ac4fd` | feat(web): gate agent preset selection behind a setting (#3870) | Ziya | 2026-09-10 |
| `81d017bb` | docs: align generated catalog source links in both locales | creatixchu | 2026-09-10 |
| `ca827aa2` | fix(commands): refresh catalogs and use type-only export identity | creatixchu | 2026-09-10 |
| `07413c2c` | Merge remote-tracking branch 'origin/master' into worktree/composer-plus-menu | creatixchu | 2026-09-10 |
| `996278e6` | refactor: separate command identity and composer file action ownership | creatixchu | 2026-09-10 |
| `d7670417` | refactor(home-paths): simplify cache path dispatch | turtle1999 | 2026-09-10 |
| `646c4c2f` | Merge pull request #3924 from deepseek-harness/worktree/image-token-v41 | CreatixChu | 2026-09-10 |
| `ba2a931a` | Merge remote-tracking branch 'origin/master' into worktree/composer-plus-menu | creatixchu | 2026-09-10 |
| `7f005e2c` | test(attachment-local): isolate fallback cache home | turtle1999 | 2026-09-10 |
| `6becec95` | Merge master and retain its strict Linux startup cancellation handling | 07akioni | 2026-09-10 |
| `d911a7b4` | feat(attachment-local): move request images into shared cache | turtle1999 | 2026-09-10 |
| `6d103f8f` | Revert Windows dialog smoke acceptance of unavailable COM classes | 07akioni | 2026-09-10 |
| `61b02efa` | Merge pull request #3916 from deepseek-harness/worktree/fix-deliverable-sidebar-preview | Yichen Jiang | 2026-09-10 |
| `d570f32f` | Merge latest master into fix/bundle-speed | 07akioni | 2026-09-10 |
| `8d1e8acd` | Merge pull request #3917 from deepseek-harness/worktree/composer-reference-previews | Yichen Jiang | 2026-09-10 |
| `b79a227c` | fix(subprocess): preserve Linux cancellation before bootstrap consumption | Yichen Jiang | 2026-09-10 |
| `f657a3e8` | Merge remote-tracking branch 'origin/master' into worktree/image-token-v41 | creatixchu | 2026-09-10 |
| `f24bc3c8` | fix(llm-deepseek): correct image pricing documentation and edge-case evidence | creatixchu | 2026-09-10 |
| `a62fab00` | test: distinguish unavailable Windows dialog classes in native smoke | 07akioni | 2026-09-10 |
| `4c024cf2` | fix: preserve early process cancellation and sample stream markers promptly | 07akioni | 2026-09-10 |
| `85df0e76` | docs(home-paths): align cache helper example | turtle1999 | 2026-09-10 |
| `24e63e45` | fix(web): handle pending and linked skill previews | Yichen Jiang | 2026-09-10 |
| `e4e0e78d` | feat(home-paths): add dshCachePath | turtle1999 | 2026-09-10 |
| `82293ff4` | refactor(desktop): remove unused plugin classification query | 07akioni | 2026-09-10 |
| `d55b2b3d` | fix(desktop): make startup recovery and package rebuilds retryable | 07akioni | 2026-09-10 |
| `a64dc3a6` | fix(llm-deepseek): 图片 token 预估器改用官方计算器 v41 配置 | creatixchu | 2026-09-10 |
| `5445ad16` | test(web): update file link gallery preview label | Yichen Jiang | 2026-09-10 |
| `40606d15` | Merge pull request #3873 from deepseek-harness/ci/failover-canary-leg | Chinesezjc | 2026-09-10 |
| `6469b522` | Merge pull request #3899 from deepseek-harness/worktree/manifest-plugin-metadata | Yichen Jiang | 2026-09-10 |
| `6fe445ea` | Merge origin/master into worktree/composer-plus-menu | creatixchu | 2026-09-10 |
| `13fc0a60` | Merge remote-tracking branch 'origin/master' into fix/bundle-speed | 07akioni | 2026-09-10 |
| `71046d83` | fix(web): unify inline file preview labels | Yichen Jiang | 2026-09-10 |
| `ce7ceb60` | refactor(manifest): remove discovery categories | Yichen Jiang | 2026-09-10 |
| `4115e886` | test(web): update SVG delivery sidebar snapshot | Yichen Jiang | 2026-09-10 |
| `ff153dfb` | Merge remote-tracking branch 'origin/master' into worktree/fix-deliverable-sidebar-preview | Yichen Jiang | 2026-09-10 |
| `aa8262ec` | Merge pull request #3920 from deepseek-harness/feat/add-readme-citation | Tianyi Cui | 2026-09-10 |
| `dcec949f` | fix(python): allow workspace-only patches during runtime deploy | 07akioni | 2026-09-10 |
| `597f0f8f` | fix(web): align composer reference heights and baselines | Yichen Jiang | 2026-09-10 |
| `81239767` | docs: add BibTeX citation to READMEs | fz | 2026-09-10 |
| `710d7b5c` | Merge latest fix/bundle-speed and resolve desktop documentation conflicts | 07akioni | 2026-09-10 |
| `081e054c` | Merge remote-tracking branch 'origin/master' into worktree/manifest-plugin-metadata | Yichen Jiang | 2026-09-10 |
| `11d6bd05` | feat(web): preview file and skill references in the sidebar | Yichen Jiang | 2026-09-10 |
| `8ce9b21e` | Merge master into fix/bundle-speed and preserve desktop runtime changes | 07akioni | 2026-09-10 |
| `eb0a6664` | Merge remote-tracking branch 'origin/master' into dshw/pr-deepseek-harness-deepseek-harness-3828 | _Kerman | 2026-09-10 |
| `ca2a9017` | fix(web): preview delivered file links in the sidebar | Yichen Jiang | 2026-09-10 |
| `20374de3` | Merge remote-tracking branch 'origin/fix/bundle-speed' into fix/parallel-macos-notarization | 07akioni | 2026-09-10 |
| … | … 322 more | … | … |

## Files changed by category

| Category | Count | Sample files |
|---|---|---|
| CORE | 1050 | `.agents/notes/implemented/architecture/2026-06-14-session-persistence.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-06-14-session-persistence.md`<br>`.agents/notes/implemented/architecture/2026-06-14-session-persistence.zh.md` |
| CLIENT | 663 | `apps/web/package.json`<br>`apps/web/tests/README.i18n.yaml`<br>`apps/web/tests/README.md` |
| DOCS | 400 | `.agents/notes/archived/feature/2026-09-08-web-explicit-file-delivery.i18n.yaml`<br>`.agents/notes/archived/feature/2026-09-08-web-explicit-file-delivery.md`<br>`.agents/notes/archived/feature/2026-09-08-web-explicit-file-delivery.zh.md` |
| API | 83 | `packages/api/README.i18n.yaml`<br>`packages/api/README.md`<br>`packages/api/README.zh.md` |
| OTHER | 69 | `.oxlintrc.json`<br>`README.i18n.yaml`<br>`apps/cli/README.i18n.yaml` |
| BUILD | 64 | `.github/AGENTS.md`<br>`.github/review-ownership/CODEOWNERS`<br>`.github/review-ownership/README.md` |
| TEST | 52 | `apps/cli/tests/built-bin.e2e.ts`<br>`apps/cli/tests/profiles/headless/tests/expected/mcp-pagination/stderr-cause.txt`<br>`apps/cli/tests/profiles/headless/tests/expected/subagent-inheritance/parent.expected.jsonl` |
| MODEL | 48 | `packages/llm/README.i18n.yaml`<br>`packages/llm/README.zh.md`<br>`packages/llm/deepseek-llm-api-extensions/README.i18n.yaml` |
| HOST | 38 | `packages/host/directory-picker-auto/README.i18n.yaml`<br>`packages/host/directory-picker-auto/README.md`<br>`packages/host/directory-picker-auto/README.zh.md` |
| INTERACTION | 31 | `packages/interaction/README.i18n.yaml`<br>`packages/interaction/README.md`<br>`packages/interaction/README.zh.md` |
| SECURITY | 19 | `.agents/notes/implemented/architecture/2026-09-09-workspace-file-read-authority.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-09-09-workspace-file-read-authority.md`<br>`.agents/notes/implemented/architecture/2026-09-09-workspace-file-read-authority.zh.md` |
| REACT | 17 | `.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md`<br>`.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md` |
| STREAM | 15 | `.agents/notes/implemented/simplification/2026-06-20-collapse-trace-only-session-events.i18n.yaml`<br>`.agents/notes/implemented/simplification/2026-06-20-collapse-trace-only-session-events.md`<br>`.agents/notes/implemented/simplification/2026-06-20-collapse-trace-only-session-events.zh.md` |

## API changes

| # | Kind | Endpoint | Severity | Description |
|---|---|---|---|---|
| 1 | added | `sessionFeedback/record` | P2 | Endpoint added: sessionFeedback/record (service sessionFeedback, mode unary) from packages/feedback/command-feedback/src/index.ts:102 |
| 2 | added | `workspaceFiles/readAll` | P2 | Endpoint added: workspaceFiles/readAll (service workspaceFiles, mode unary) from packages/api/workspace-files/src/index.ts:278 |
| 3 | added | `workspaceFiles/readRelated` | P2 | Endpoint added: workspaceFiles/readRelated (service workspaceFiles, mode unary) from packages/api/workspace-files/src/index.ts:300 |

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
| MISSING | 3 |
| INCOMPATIBLE | 0 |
| OUTDATED | 0 |
| UNKNOWN | 11 |
| REMOVED | 0 |

| API | Status | Sev | React → Flutter | Reason |
|---|---|---|---|---|
| `session/disposed` | MISSING | P0 | `∅` | React uses session/disposed but Flutter does not call it |
| `llm/stream` | MISSING | P1 | `∅` | React uses llm/stream but Flutter does not call it |
| `remote/transport` | MISSING | P1 | `∅` | React uses remote/transport but Flutter does not call it |
| `session/follow snapshot.cursor` | UNKNOWN | P0 | `∅` | React session/follow snapshot.cursor vs Flutter session/page sentinel cursor discovery — ARCHITECTURAL MISMATCH |
| `agentPreset selected event` | UNKNOWN | P1 | `∅` | React agentPreset selected event updates session state via events; Flutter must consume same event (event ignored → STATE/PARITY MISMATCH) |
| `directoryPicker/readFile` | UNKNOWN | P2 | `directoryPicker/readFile` | Flutter uses directoryPicker/readFile not found in React surfaces; verify if deprecated or new |
| `goals/get` | UNKNOWN | P2 | `goals/get` | Flutter uses goals/get not found in React surfaces; verify if deprecated or new |
| `messageFeedback/delete` | UNKNOWN | P2 | `messageFeedback/delete` | Flutter uses messageFeedback/delete not found in React surfaces; verify if deprecated or new |
| `messageFeedback/list` | UNKNOWN | P2 | `messageFeedback/list` | Flutter uses messageFeedback/list not found in React surfaces; verify if deprecated or new |
| `messageFeedback/put` | UNKNOWN | P2 | `messageFeedback/put` | Flutter uses messageFeedback/put not found in React surfaces; verify if deprecated or new |
| `remote/describe` | UNKNOWN | P2 | `remote/describe` | Flutter uses remote/describe not found in React surfaces; verify if deprecated or new |
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
| … | … | … | … | … 10 more |

## Flutter impact

| Severity | Count |
|---|---|
| P0 (blocks runtime) | 2 |
| P1 (feature broken) | 1 |
| P2 (compat risk) | 3 |
| P3 (informational) | 0 |

| ID | Change | Sev | Affected Flutter files | Required action |
|---|---|---|---|---|
| `flutter:session/page-cursor` | session/page throughSeq sentinel vs cursor | P0 | connection/connection_client.dart<br>session/live_history.dart | verify Flutter getSessionHistory requires throughSeq and waits for LiveHistory.acceptedSeq; no fabricated cursor |
| `flutter:settings-describe-list` | settings/describe List namespaces | P0 | settings/settings_scope.dart<br>settings/settings_screen.dart | ensure SettingsScope._refreshNow handles List<Map> and fallback forms; verified in be6498fd |
| `flutter:remote-mux-ticket` | remote.mux bearer ticket flow | P1 | connection/remote_mux_client.dart<br>connection/connection_client.dart | verify ticket fetch and re-pair flow; no silent fallback to unauthenticated |
| `added:sessionFeedback/record` | added: ∅ → sessionFeedback/record | P2 | — | evaluate if Flutter should consume new endpoint |
| `added:workspaceFiles/readAll` | added: ∅ → workspaceFiles/readAll | P2 | files/workspace_files_client.dart<br>files/workspace_files_client.dart | evaluate if Flutter should consume new endpoint |
| `added:workspaceFiles/readRelated` | added: ∅ → workspaceFiles/readRelated | P2 | files/workspace_files_client.dart<br>files/workspace_files_client.dart | evaluate if Flutter should consume new endpoint |

## Change registry (excerpt)

| ID | Category | Sev | Old → New | Status | Description |
|---|---|---|---|---|---|
| `CR-0001` | API | P2 | `∅` → `sessionFeedback/record` | Detected | [API added] Endpoint added: sessionFeedback/record (service sessionFeedback, mode unary) from packages/feedback/command- |
| `CR-0002` | API | P2 | `∅` → `workspaceFiles/readAll` | Detected | [API added] Endpoint added: workspaceFiles/readAll (service workspaceFiles, mode unary) from packages/api/workspace-file |
| `CR-0003` | API | P2 | `∅` → `workspaceFiles/readRelated` | Detected | [API added] Endpoint added: workspaceFiles/readRelated (service workspaceFiles, mode unary) from packages/api/workspace- |
| `CR-0004` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml — verify F |
| `CR-0005` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md — verify Flutter  |
| `CR-0006` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md — verify Flutt |
| `CR-0007` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.i18n.yaml — verify Flutter p |
| `CR-0008` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.md — verify Flutter parity f |
| `CR-0009` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.zh.md — verify Flutter parit |
| `CR-0010` | REACT | P2 | `apps/web/package.json` → `apps/web/package.json` | Detected | [REACT] File changed: apps/web/package.json — verify Flutter parity for behavior/state fallback |
| `CR-0011` | REACT | P2 | `apps/web/tests/README.i18n.yaml` → `apps/web/tests/README.i18n.yaml` | Detected | [REACT] File changed: apps/web/tests/README.i18n.yaml — verify Flutter parity for behavior/state fallback |
| `CR-0012` | REACT | P2 | `apps/web/tests/README.md` → `apps/web/tests/README.md` | Detected | [REACT] File changed: apps/web/tests/README.md — verify Flutter parity for behavior/state fallback |
| `CR-0013` | REACT | P2 | `apps/web/tests/README.zh.md` → `apps/web/tests/README.zh.md` | Detected | [REACT] File changed: apps/web/tests/README.zh.md — verify Flutter parity for behavior/state fallback |
| `CR-0014` | REACT | P2 | `apps/web/tests/agent-preset-authoring.e2` → `apps/web/tests/agent-preset-authoring.e2` | Detected | [REACT] File changed: apps/web/tests/agent-preset-authoring.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0015` | REACT | P2 | `apps/web/tests/agent-preset-selection.e2` → `apps/web/tests/agent-preset-selection.e2` | Detected | [REACT] File changed: apps/web/tests/agent-preset-selection.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0016` | REACT | P2 | `apps/web/tests/agent-team-panel.e2e.ts` → `apps/web/tests/agent-team-panel.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/agent-team-panel.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0017` | REACT | P2 | `apps/web/tests/clickable-links-gallery.e` → `apps/web/tests/clickable-links-gallery.e` | Detected | [REACT] File changed: apps/web/tests/clickable-links-gallery.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0018` | REACT | P2 | `apps/web/tests/composer-placeholder.e2e.` → `apps/web/tests/composer-placeholder.e2e.` | Detected | [REACT] File changed: apps/web/tests/composer-placeholder.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0019` | REACT | P2 | `apps/web/tests/details-session-lifecycle` → `apps/web/tests/details-session-lifecycle` | Detected | [REACT] File changed: apps/web/tests/details-session-lifecycle.e2e.ts — verify Flutter parity for behavior/state fallbac |
| `CR-0020` | REACT | P2 | `apps/web/tests/document-preview.e2e.ts` → `apps/web/tests/document-preview.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/document-preview.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0021` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/created.expected.md — verify Flutter parity for beh |
| `CR-0022` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/damaged.expected.md — verify Flutter parity for beh |
| `CR-0023` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/section.expected.md — verify Flutter parity for beh |
| `CR-0024` | REACT | P2 | `apps/web/tests/expected/agent-preset-sel` → `apps/web/tests/expected/agent-preset-sel` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-selection/header.expected.md — verify Flutter parity for beha |
| `CR-0025` | REACT | P2 | `apps/web/tests/expected/agent-preset-sel` → `apps/web/tests/expected/agent-preset-sel` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-selection/menu.expected.md — verify Flutter parity for behavi |
| `CR-0026` | REACT | P2 | `apps/web/tests/expected/clickable-links-` → `apps/web/tests/expected/clickable-links-` | Detected | [REACT] File changed: apps/web/tests/expected/clickable-links-gallery/ui.expected.md — verify Flutter parity for behavio |
| `CR-0027` | REACT | P2 | `apps/web/tests/expected/composer-placeho` → `apps/web/tests/expected/composer-placeho` | Detected | [REACT] File changed: apps/web/tests/expected/composer-placeholder/visibility.expected.md — verify Flutter parity for be |
| `CR-0028` | REACT | P2 | `apps/web/tests/expected/file-upload-roun` → `apps/web/tests/expected/file-upload-roun` | Detected | [REACT] File changed: apps/web/tests/expected/file-upload-round/draft.expected.md — verify Flutter parity for behavior/s |
| `CR-0029` | REACT | P2 | `apps/web/tests/expected/file-upload-roun` → `apps/web/tests/expected/file-upload-roun` | Detected | [REACT] File changed: apps/web/tests/expected/file-upload-round/history.expected.md — verify Flutter parity for behavior |
| `CR-0030` | REACT | P2 | `apps/web/tests/expected/github-ready-rev` → `apps/web/tests/expected/github-ready-rev` | Detected | [REACT] File changed: apps/web/tests/expected/github-ready-review/conversation-expanded.expected.md — verify Flutter par |
| `CR-0031` | REACT | P2 | `apps/web/tests/expected/github-ready-rev` → `apps/web/tests/expected/github-ready-rev` | Detected | [REACT] File changed: apps/web/tests/expected/github-ready-review/conversation.expected.md — verify Flutter parity for b |
| `CR-0032` | REACT | P2 | `apps/web/tests/expected/goal-command-pre` → `apps/web/tests/expected/goal-command-pre` | Detected | [REACT] File changed: apps/web/tests/expected/goal-command-presentation/ui.expected.md — verify Flutter parity for behav |
| `CR-0033` | REACT | P2 | `apps/web/tests/expected/markdown-cjk-str` → `apps/web/tests/expected/markdown-cjk-str` | Detected | [REACT] File changed: apps/web/tests/expected/markdown-cjk-strong/ui.expected.md — verify Flutter parity for behavior/st |
| `CR-0034` | REACT | P2 | `apps/web/tests/expected/markdown-images/` → `apps/web/tests/expected/markdown-images/` | Detected | [REACT] File changed: apps/web/tests/expected/markdown-images/ui.expected.md — verify Flutter parity for behavior/state  |
| `CR-0035` | REACT | P2 | `apps/web/tests/expected/markdown-inline-` → `apps/web/tests/expected/markdown-inline-` | Detected | [REACT] File changed: apps/web/tests/expected/markdown-inline-code-links/ui.expected.md — verify Flutter parity for beha |
| `CR-0036` | REACT | P2 | `apps/web/tests/expected/math-rendering/u` → `apps/web/tests/expected/math-rendering/u` | Detected | [REACT] File changed: apps/web/tests/expected/math-rendering/ui.expected.md — verify Flutter parity for behavior/state f |
| `CR-0037` | REACT | P2 | `apps/web/tests/expected/models-settings-` → `apps/web/tests/expected/models-settings-` | Detected | [REACT] File changed: apps/web/tests/expected/models-settings-recovery/stored-error.expected.md — verify Flutter parity  |
| `CR-0038` | REACT | P2 | `apps/web/tests/expected/onboarding-deeps` → `apps/web/tests/expected/onboarding-deeps` | Detected | [REACT] File changed: apps/web/tests/expected/onboarding-deepseek-config/default-models.expected.md — verify Flutter par |
| `CR-0039` | REACT | P2 | `apps/web/tests/expected/onboarding-deeps` → `apps/web/tests/expected/onboarding-deeps` | Detected | [REACT] File changed: apps/web/tests/expected/onboarding-deepseek-config/models.expected.md — verify Flutter parity for  |
| `CR-0040` | REACT | P2 | `apps/web/tests/expected/reference-compos` → `apps/web/tests/expected/reference-compos` | Detected | [REACT] File changed: apps/web/tests/expected/reference-composer/order.expected.md — verify Flutter parity for behavior/ |
| `CR-0041` | REACT | P2 | `apps/web/tests/expected/settings-chrome/` → `apps/web/tests/expected/settings-chrome/` | Detected | [REACT] File changed: apps/web/tests/expected/settings-chrome/dialog.expected.md — verify Flutter parity for behavior/st |
| `CR-0042` | REACT | P2 | `apps/web/tests/expected/settings-chrome/` → `apps/web/tests/expected/settings-chrome/` | Detected | [REACT] File changed: apps/web/tests/expected/settings-chrome/plugin-instances.expected.md — verify Flutter parity for b |
| `CR-0043` | REACT | P2 | `apps/web/tests/expected/settings-chrome/` → `apps/web/tests/expected/settings-chrome/` | Detected | [REACT] File changed: apps/web/tests/expected/settings-chrome/plugins.expected.md — verify Flutter parity for behavior/s |
| `CR-0044` | REACT | P2 | `apps/web/tests/expected/skill-invocation` → `apps/web/tests/expected/skill-invocation` | Detected | [REACT] File changed: apps/web/tests/expected/skill-invocation-policy/preview.expected.md — verify Flutter parity for be |
| `CR-0045` | REACT | P2 | `apps/web/tests/expected/skill-user-invok` → `apps/web/tests/expected/skill-user-invok` | Detected | [REACT] File changed: apps/web/tests/expected/skill-user-invoke/ui-expanded.expected.md — verify Flutter parity for beha |
| `CR-0046` | REACT | P2 | `apps/web/tests/expected/skill-user-invok` → `apps/web/tests/expected/skill-user-invok` | Detected | [REACT] File changed: apps/web/tests/expected/skill-user-invoke/ui.expected.md — verify Flutter parity for behavior/stat |
| `CR-0047` | REACT | P2 | `apps/web/tests/expected/stats-paged-hist` → `apps/web/tests/expected/stats-paged-hist` | Detected | [REACT] File changed: apps/web/tests/expected/stats-paged-history/ui.expected.md — verify Flutter parity for behavior/st |
| `CR-0048` | REACT | P2 | `apps/web/tests/expected/steer-all/mid-st` → `apps/web/tests/expected/steer-all/mid-st` | Detected | [REACT] File changed: apps/web/tests/expected/steer-all/mid-steer.expected.md — verify Flutter parity for behavior/state |
| `CR-0049` | REACT | P2 | `apps/web/tests/expected/steer-all/settle` → `apps/web/tests/expected/steer-all/settle` | Detected | [REACT] File changed: apps/web/tests/expected/steer-all/settled-expanded.expected.md — verify Flutter parity for behavio |
| `CR-0050` | REACT | P2 | `apps/web/tests/expected/steer-all/settle` → `apps/web/tests/expected/steer-all/settle` | Detected | [REACT] File changed: apps/web/tests/expected/steer-all/settled.expected.md — verify Flutter parity for behavior/state f |
| … | … | … | … | … | … 633 more |

## Model / Type changes (heuristic)

Namespaces prev → current: 20 → 21 (agentPresets, agentTeams, commands, credentials, directoryPicker … → agentPresets, agentTeams, commands, credentials, directoryPicker …)

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
_Report generated by upstream-sync • upstream 5dda764e → c291e796 • local 2b8b3d40_
