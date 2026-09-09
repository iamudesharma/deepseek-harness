# Upstream Sync Report — 2026-09-09

> Generated: 2026-09-09T01:19:18.717Z
> Upstream: https://github.com/deepseek-ai/deepseek-harness.git @ master
> Old SHA: `d347e703908d0406b7a7ef80e3a0e594d86b2215` (`d347e703`) → New SHA: `5dda764ed3aa172535a7967b06ff95d9cbfe536a` (`5dda764e`)
> Local HEAD: `5bbc7cbc`  Merge-base: `b0a7d2ce`  Behind: 879  Ahead: 570

## Summary

| Metric | Value |
|---|---|
| Commits | 879 |
| Files changed | 5459 |
| File categories | HOST:52, API:107, CLIENT:620, REACT:44, CORE:1818, INTERACTION:20, MODEL:62, STREAM:52, SECURITY:37, BUILD:108, DOCS:2301, TEST:97, OTHER:141 |
| API operations (prev → current) | 92 → 97 |
| API changes | 5 (breaking: 0, additive: 5) |
| Stream changes | 0 |
| React surfaces | 1093 |
| Flutter call sites | 167 in 374 files |
| Parity | PASS 56 / MISSING 3 / INCOMPATIBLE 0 / UNKNOWN 10 |
| Flutter impact | P0 2 · P1 1 · P2 5 · P3 0 |
| Registry entries | 669 |
| Parity gate | ❌ FAIL |
| Recommended action | P0 blocking — do not merge Flutter without fixes |

## Commits (upstream..new)

| SHA | Subject | Author | Date |
|---|---|---|---|
| `5dda764e` | Merge pull request #3809 from deepseek-harness/worktree/release/dsh-0.1.5-alpha.1 | imccyu | 2026-09-08 |
| `2faa751b` | release(dsh): 0.1.5-alpha.1 | imccyu | 2026-09-08 |
| `96a66ba4` | Merge pull request #3790 from deepseek-harness/worktree-ci-0908 | imccyu | 2026-09-08 |
| `7b1c9893` | Merge pull request #3631 from deepseek-harness/release/session-log-v3 | Tianyi Cui | 2026-09-08 |
| `edcde102` | Merge pull request #3808 from deepseek-harness/integrate/v3-master-e5f3-refresh | Tianyi Cui | 2026-09-08 |
| `5ad38e5b` | Merge remote-tracking branch 'origin/master' into integrate/v3-master-refresh-345248 | Tianyi Cui | 2026-09-08 |
| `6982a8f5` | Merge remote-tracking branch 'origin/release/session-log-v3' into integrate/v3-master-refresh-345248 | Tianyi Cui | 2026-09-08 |
| `f7a4f0b9` | Merge pull request #3805 from deepseek-harness/session-v3/content-admission-fix | Tianyi Cui | 2026-09-08 |
| `5212603a` | fix(session): audit every historical content carrier before V3 migration | Tianyi Cui | 2026-09-08 |
| `2c21c7a0` | ci: 1 | imccyu | 2026-09-08 |
| `93a51e4d` | Merge pull request #3804 from deepseek-harness/worktree/release-nativesystem-0.1.2 | imccyu | 2026-09-08 |
| `bb407e30` | Merge master into session-log-v3 release | Tianyi Cui | 2026-09-08 |
| `9ddc35c2` | release(node-addon-system): 0.1.2 | imccyu | 2026-09-08 |
| `08f42810` | Merge pull request #3781 from deepseek-harness/worktree/ci-reliability-master-20260908 | Tianyi Cui | 2026-09-08 |
| `9ea82286` | Merge pull request #3708 from deepseek-harness/worktree-fixgyp | imccyu | 2026-09-08 |
| `11ec7cc5` | Merge pull request #3799 from deepseek-harness/session-v3/migration-coverage | Tianyi Cui | 2026-09-08 |
| `92d4410a` | Merge pull request #3801 from deepseek-harness/worktree/ci-reliability-release-v3-20260908 | Tianyi Cui | 2026-09-08 |
| `ae491963` | test(web): align SSH replay with V3 release fixtures | Tianyi Cui | 2026-09-08 |
| `cadd3ac0` | Merge current V3 release into migration coverage audit | Tianyi Cui | 2026-09-08 |
| `5924d4c1` | test(session): audit V3 migration composition and centralize upgrade spec | Tianyi Cui | 2026-09-08 |
| `e72c9e4b` | Merge pull request #3797 from deepseek-harness/integrate/v3-master-refresh-345248 | Tianyi Cui | 2026-09-08 |
| `36997d85` | test(ci): inherit runner budgets in publint and LSP fixtures | Tianyi Cui | 2026-09-08 |
| `59ec2d3e` | test(ci): clean up fixture workers after test timeouts | Tianyi Cui | 2026-09-08 |
| `475f5648` | test(ci): wait for owned completion in master tests | Tianyi Cui | 2026-09-08 |
| `a0656e24` | Merge pull request #3787 from deepseek-harness/feat/upgrade-codex-claude-runtimes | fz | 2026-09-08 |
| `0aa1ef0d` | Merge remote-tracking branch 'origin/release/session-log-v3' into integrate/v3-master-refresh-345248 | Tianyi Cui | 2026-09-08 |
| `537102a0` | Merge pull request #3636 from deepseek-harness/session-v3/canonical-envelopes | Tianyi Cui | 2026-09-08 |
| `e11b2a55` | merge: refresh session-log-v3 from master 345248f470 | Tianyi Cui | 2026-09-08 |
| `b4983e92` | Merge pull request #3788 from deepseek-harness/turtle/fix-approved-review-rerequest | Turtle | 2026-09-08 |
| `03f439df` | Merge pull request #3673 from deepseek-harness/worktree/typert-forward-reexport | CreatixChu | 2026-09-08 |
| `97e7223d` | refactor(native): expose Landlock through its capability subpath | imccyu | 2026-09-08 |
| `a2784a22` | test(web): synchronize theme writes and focus assertions | imccyu | 2026-09-08 |
| `3a445b80` | test(ci): stabilize storage and subprocess lifecycle checks | imccyu | 2026-09-08 |
| `d927cbff` | feat(native): add prebuilt Node-API flock support | imccyu | 2026-09-07 |
| `7264906f` | refactor(native): rename package family to node-addon-system | imccyu | 2026-09-07 |
| `336ebb23` | refactor(native): move Landlock workspace to native/system | imccyu | 2026-09-07 |
| `bcdaed38` | Merge pull request #3295 from deepseek-harness/xtr/explicit-agent-context | _Kerman | 2026-09-08 |
| `3a98d05a` | refactor(subagent): keep preset teardown outside identity changes | _Kerman | 2026-09-08 |
| `d5e6b4e2` | chore: remove unrelated PTY test repair from agent refactor | _Kerman | 2026-09-08 |
| `5045631a` | chore: remove unrelated sidebar test notes from agent refactor | _Kerman | 2026-09-08 |
| `fde15a83` | fix(ci): do not re-request approved reviewers | Turtle | 2026-09-08 |
| `ace0c461` | chore(subagent): upgrade Codex and Claude Code runtimes | fz | 2026-09-08 |
| `606b85cd` | refactor(typert): track forwarding visits without a delimiter | creatixchu | 2026-09-08 |
| `b7291982` | fix(typert): distinguish forwarding visits by export name | creatixchu | 2026-09-08 |
| `3e0e419b` | Merge remote-tracking branch 'origin/master' into xtr/explicit-agent-context | _Kerman | 2026-09-08 |
| `657482d1` | Merge remote-tracking branch 'origin/master' into worktree/typert-forward-reexport | creatixchu | 2026-09-08 |
| `6c87f030` | fix(checks): preserve visualizer composition preset identifiers | _Kerman | 2026-09-08 |
| `36bd2972` | fix(visualizer): keep model registration independent of agent identity | _Kerman | 2026-09-08 |
| `795a9cc2` | test(web): sample queue alignment in one layout | _Kerman | 2026-09-08 |
| `55660e8a` | test(terminal): decouple descendant identity from startup | _Kerman | 2026-09-08 |
| `8fda2f62` | Merge pull request #3671 from deepseek-harness/fix/session-prose-local-media-display | _Kerman | 2026-09-08 |
| `44008a79` | test(team): await mailbox acknowledgement flushes before teardown | _Kerman | 2026-09-08 |
| `404097f8` | test(subagent): reap SDK startup before readiness fixture cleanup | _Kerman | 2026-09-08 |
| `939e6907` | test(shell): gate consuming PowerShell reads on parent acknowledgement | _Kerman | 2026-09-08 |
| `71e96aeb` | test(subagent): preserve ACP readiness budgets and teardown ownership | _Kerman | 2026-09-08 |
| `b76a6d99` | fix(web): keep animated connection dots hidden on hover | _Kerman | 2026-09-08 |
| `a433eec5` | test(web): await editor credential state before snapshots | _Kerman | 2026-09-08 |
| `c846beaf` | merge: sync reverted visualizer base from master | _Kerman | 2026-09-08 |
| `eda67c4a` | Merge pull request #3778 from deepseek-harness/revert-3337-feat/visualizer-host-plugin | Tianyi Cui | 2026-09-08 |
| `92b3b026` | Revert "feat(visualizer): add dormant Host capability" | Tianyi Cui | 2026-09-08 |
| `e186c218` | test(web): release workflow gates after failed submissions | _Kerman | 2026-09-08 |
| `75996526` | merge: sync origin/master | _Kerman | 2026-09-08 |
| `c26350c3` | Merge remote-tracking branch 'origin/master' into xtr/explicit-agent-context | _Kerman | 2026-09-08 |
| `0f9d944f` | test(worker): account for the dockkit browser CSS entry | _Kerman | 2026-09-08 |
| `7627622c` | test(session): await durable cold projection cache writes | _Kerman | 2026-09-08 |
| `3ec21912` | test(web): await feedback submit replies before snapshots | _Kerman | 2026-09-08 |
| `19d87778` | test(web): hold workflow children through live navigation checks | _Kerman | 2026-09-08 |
| `e7bde97a` | fix(tool-subagent): await agent-started preset cleanup | _Kerman | 2026-09-08 |
| `b4c69b0f` | Merge pull request #3337 from deepseek-harness/feat/visualizer-host-plugin | Ziya | 2026-09-08 |
| `180bdede` | fix(test): retain child turn diagnostics when log reads time out | _Kerman | 2026-09-08 |
| `f7ef7103` | test(subagent): await the image capability read before draining | _Kerman | 2026-09-08 |
| `f7c9170b` | fix(web): dismiss tooltips when composer actions become disabled | _Kerman | 2026-09-08 |
| `314ccf08` | Merge remote-tracking branch 'origin/master' into xtr/explicit-agent-context | _Kerman | 2026-09-08 |
| `ef8f166c` | test(ci): preserve the lane budget for invariant verifier children | _Kerman | 2026-09-08 |
| `3fc9027a` | docs(session): refresh replay config source location | Tianyi Cui | 2026-09-08 |
| `53f42a78` | test(session): close canonical envelope CI gaps | Tianyi Cui | 2026-09-08 |
| `c4d8ee5f` | test(session): canonicalize headless expected system replacements | Tianyi Cui | 2026-09-08 |
| `920e9179` | fix(session): retain unknown required events for vocabulary validation | Tianyi Cui | 2026-09-08 |
| `b7622e9f` | chore(session): refresh canonical API catalog after integration | Tianyi Cui | 2026-09-08 |
| `756b10fc` | test(session): cover composed canonical and PTC restoration | Tianyi Cui | 2026-09-06 |
| `c2863958` | test(session): keep historical fixtures outside current V3 encoding | Tianyi Cui | 2026-09-06 |
| `657e6818` | fix(session): canonicalize V3 envelopes through adjacent migration | Tianyi Cui | 2026-09-06 |
| `7cbb0526` | Merge pull request #3711 from deepseek-harness/integrate/v3-latest-master-for-canonical | Tianyi Cui | 2026-09-08 |
| `8e468c13` | test(visualizer): remove redundant host web replay | ZiyaZhang | 2026-09-08 |
| `934d4b65` | refactor(visualizer): trust settled widget contents | ZiyaZhang | 2026-09-08 |
| `e7dc1322` | fix(visualizer): leave motion to presentation choice | ZiyaZhang | 2026-09-08 |
| `b80e22ec` | docs(visualizer): require self-contained widget sources | ZiyaZhang | 2026-09-07 |
| `b75b8ce4` | chore(visualizer): align release metadata and snapshots | ZiyaZhang | 2026-09-07 |
| `7729e0ff` | refactor(visualizer): simplify host contract | ZiyaZhang | 2026-09-07 |
| `b17e90f7` | fix(visualizer): validate fragment contracts precisely | ZiyaZhang | 2026-09-07 |
| `f1f6ca1c` | feat(visualizer): add dormant Host capability | ZiyaZhang | 2026-09-02 |
| `839a6fa9` | test(web): await mutation replies before capturing settled UI | _Kerman | 2026-09-08 |
| `3aee29c6` | test(lsp): hold queued source reads behind a response barrier | _Kerman | 2026-09-08 |
| `189d9692` | Merge pull request #3769 from deepseek-harness/turtle/auto-repair-issue-labels | Turtle | 2026-09-08 |
| `1d6b898e` | Merge pull request #3764 from deepseek-harness/turtle/request-review-live-smoke | Turtle | 2026-09-08 |
| `e33834f5` | test(web): await session and responsive layout readiness | _Kerman | 2026-09-08 |
| `999b677e` | merge: sync origin/master | _Kerman | 2026-09-08 |
| `614ff048` | fix: reconcile automated review requests | Turtle | 2026-09-08 |
| `f8828b2c` | fix(ci): auto-repair invalid Issue labels | Turtle | 2026-09-08 |
| `f9ec0c28` | Merge pull request #3753 from deepseek-harness/turtle/package-summary-100-word-gate | Turtle | 2026-09-08 |
| … | … 779 more | … | … |

## Files changed by category

| Category | Count | Sample files |
|---|---|---|
| DOCS | 2301 | `.agents/notes/README.i18n.yaml`<br>`.agents/notes/README.md`<br>`.agents/notes/README.zh.md` |
| CORE | 1818 | `.agents/notes/archived/architecture/2026-07-02-fs-per-session-cwd.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-07-02-fs-per-session-cwd.md`<br>`.agents/notes/archived/architecture/2026-07-02-fs-per-session-cwd.zh.md` |
| CLIENT | 620 | `apps/web/package.json`<br>`apps/web/tests/agent-preset-selection.e2e.ts`<br>`apps/web/tests/approval-composer.e2e.ts` |
| OTHER | 141 | `.gitattributes`<br>`.gitignore`<br>`apps/cli/README.i18n.yaml` |
| BUILD | 108 | `.agents/notes/archived/testing/2026-07-30-vitest-jsdom-webstorage-ownership.i18n.yaml`<br>`.agents/notes/archived/testing/2026-07-30-vitest-jsdom-webstorage-ownership.md`<br>`.agents/notes/archived/testing/2026-07-30-vitest-jsdom-webstorage-ownership.zh.md` |
| API | 107 | `.agents/notes/implemented/bug-fix/2026-09-07-typert-package-local-forwarding-imports.i18n.yaml`<br>`.agents/notes/implemented/bug-fix/2026-09-07-typert-package-local-forwarding-imports.md`<br>`.agents/notes/implemented/bug-fix/2026-09-07-typert-package-local-forwarding-imports.zh.md` |
| TEST | 97 | `apps/cli/tests/args.spec.ts`<br>`apps/cli/tests/built-bin.e2e.ts`<br>`apps/cli/tests/fixtures/dsh-badge/snapshot.ts` |
| MODEL | 62 | `packages/llm/README.i18n.yaml`<br>`packages/llm/README.md`<br>`packages/llm/README.zh.md` |
| HOST | 52 | `packages/host/README.i18n.yaml`<br>`packages/host/README.md`<br>`packages/host/README.zh.md` |
| STREAM | 52 | `.agents/notes/archived/architecture/2026-07-05-subagent-provider-lifecycle-events.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-07-05-subagent-provider-lifecycle-events.md`<br>`.agents/notes/archived/architecture/2026-07-05-subagent-provider-lifecycle-events.zh.md` |
| REACT | 44 | `.agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.i18n.yaml`<br>`.agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.md`<br>`.agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.zh.md` |
| SECURITY | 37 | `.agents/notes/archived/architecture/2026-07-29-request-level-llm-config-credentials.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-07-29-request-level-llm-config-credentials.md`<br>`.agents/notes/archived/architecture/2026-07-29-request-level-llm-config-credentials.zh.md` |
| INTERACTION | 20 | `packages/interaction/README.i18n.yaml`<br>`packages/interaction/README.md`<br>`packages/interaction/README.zh.md` |

## API changes

| # | Kind | Endpoint | Severity | Description |
|---|---|---|---|---|
| 1 | added | `workspaceFiles/changes` | P2 | Endpoint added: workspaceFiles/changes (service workspaceFiles, mode stream) from packages/api/workspace-files/src/index.ts:274 |
| 2 | added | `workspaceFiles/list` | P2 | Endpoint added: workspaceFiles/list (service workspaceFiles, mode unary) from packages/api/workspace-files/src/index.ts:246 |
| 3 | added | `workspaceFiles/read` | P2 | Endpoint added: workspaceFiles/read (service workspaceFiles, mode unary) from packages/api/workspace-files/src/index.ts:197 |
| 4 | added | `workspaceFiles/readBytes` | P2 | Endpoint added: workspaceFiles/readBytes (service workspaceFiles, mode unary) from packages/api/workspace-files/src/index.ts:217 |
| 5 | added | `workspaceFiles/stat` | P2 | Endpoint added: workspaceFiles/stat (service workspaceFiles, mode unary) from packages/api/workspace-files/src/index.ts:233 |

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
| UNKNOWN | 10 |
| REMOVED | 0 |

| API | Status | Sev | React → Flutter | Reason |
|---|---|---|---|---|
| `session/disposed` | MISSING | P0 | `∅` | React uses session/disposed but Flutter does not call it |
| `llm/stream` | MISSING | P1 | `∅` | React uses llm/stream but Flutter does not call it |
| `remote/transport` | MISSING | P1 | `∅` | React uses remote/transport but Flutter does not call it |
| `session/follow snapshot.cursor` | UNKNOWN | P0 | `∅` | React session/follow snapshot.cursor vs Flutter session/page sentinel cursor discovery — ARCHITECTURAL MISMATCH |
| `agentPreset selected event` | UNKNOWN | P1 | `∅` | React agentPreset selected event updates session state via events; Flutter must consume same event (event ignored → STATE/PARITY MISMATCH) |
| `directoryPicker/readFile` | UNKNOWN | P2 | `directoryPicker/readFile` | Flutter uses directoryPicker/readFile not found in React surfaces; verify if deprecated or new |
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
| `settings/update` | PASS | P3 | `settings/update` | React and Flutter both use settings/update |
| … | … | … | … | … 9 more |

## Flutter impact

| Severity | Count |
|---|---|
| P0 (blocks runtime) | 2 |
| P1 (feature broken) | 1 |
| P2 (compat risk) | 5 |
| P3 (informational) | 0 |

| ID | Change | Sev | Affected Flutter files | Required action |
|---|---|---|---|---|
| `flutter:session/page-cursor` | session/page throughSeq sentinel vs cursor | P0 | connection/connection_client.dart<br>session/live_history.dart | verify Flutter getSessionHistory requires throughSeq and waits for LiveHistory.acceptedSeq; no fabricated cursor |
| `flutter:settings-describe-list` | settings/describe List namespaces | P0 | settings/settings_scope.dart<br>settings/settings_screen.dart | ensure SettingsScope._refreshNow handles List<Map> and fallback forms; verified in be6498fd |
| `flutter:remote-mux-ticket` | remote.mux bearer ticket flow | P1 | connection/remote_mux_client.dart<br>connection/connection_client.dart | verify ticket fetch and re-pair flow; no silent fallback to unauthenticated |
| `added:workspaceFiles/changes` | added: ∅ → workspaceFiles/changes | P2 | — | evaluate if Flutter should consume new endpoint |
| `added:workspaceFiles/list` | added: ∅ → workspaceFiles/list | P2 | — | evaluate if Flutter should consume new endpoint |
| `added:workspaceFiles/read` | added: ∅ → workspaceFiles/read | P2 | — | evaluate if Flutter should consume new endpoint |
| `added:workspaceFiles/readBytes` | added: ∅ → workspaceFiles/readBytes | P2 | — | evaluate if Flutter should consume new endpoint |
| `added:workspaceFiles/stat` | added: ∅ → workspaceFiles/stat | P2 | — | evaluate if Flutter should consume new endpoint |

## Change registry (excerpt)

| ID | Category | Sev | Old → New | Status | Description |
|---|---|---|---|---|---|
| `CR-0001` | API | P2 | `∅` → `workspaceFiles/changes` | Detected | [API added] Endpoint added: workspaceFiles/changes (service workspaceFiles, mode stream) from packages/api/workspace-fil |
| `CR-0002` | API | P2 | `∅` → `workspaceFiles/list` | Detected | [API added] Endpoint added: workspaceFiles/list (service workspaceFiles, mode unary) from packages/api/workspace-files/s |
| `CR-0003` | API | P2 | `∅` → `workspaceFiles/read` | Detected | [API added] Endpoint added: workspaceFiles/read (service workspaceFiles, mode unary) from packages/api/workspace-files/s |
| `CR-0004` | API | P2 | `∅` → `workspaceFiles/readBytes` | Detected | [API added] Endpoint added: workspaceFiles/readBytes (service workspaceFiles, mode unary) from packages/api/workspace-fi |
| `CR-0005` | API | P2 | `∅` → `workspaceFiles/stat` | Detected | [API added] Endpoint added: workspaceFiles/stat (service workspaceFiles, mode unary) from packages/api/workspace-files/s |
| `CR-0006` | REACT | P2 | `.agents/notes/archived/bug-fix/2026-07-2` → `.agents/notes/archived/bug-fix/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.i18n.yaml — verify Flutter parity  |
| `CR-0007` | REACT | P2 | `.agents/notes/archived/bug-fix/2026-07-2` → `.agents/notes/archived/bug-fix/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.md — verify Flutter parity for beh |
| `CR-0008` | REACT | P2 | `.agents/notes/archived/bug-fix/2026-07-2` → `.agents/notes/archived/bug-fix/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/bug-fix/2026-07-28-web-gui-feedback-loop.zh.md — verify Flutter parity for  |
| `CR-0009` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-25-workspace-ui-product-flow.i18n.yaml — verify Flutter par |
| `CR-0010` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-25-workspace-ui-product-flow.md — verify Flutter parity for |
| `CR-0011` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-25-workspace-ui-product-flow.zh.md — verify Flutter parity  |
| `CR-0012` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-26-ptc-dispatch-ui-foundation.i18n.yaml — verify Flutter pa |
| `CR-0013` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-26-ptc-dispatch-ui-foundation.md — verify Flutter parity fo |
| `CR-0014` | REACT | P2 | `.agents/notes/archived/feature/2026-07-2` → `.agents/notes/archived/feature/2026-07-2` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-26-ptc-dispatch-ui-foundation.zh.md — verify Flutter parity |
| `CR-0015` | REACT | P2 | `.agents/notes/archived/feature/2026-07-3` → `.agents/notes/archived/feature/2026-07-3` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-31-gui-full-access-confirmation.i18n.yaml — verify Flutter  |
| `CR-0016` | REACT | P2 | `.agents/notes/archived/feature/2026-07-3` → `.agents/notes/archived/feature/2026-07-3` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-31-gui-full-access-confirmation.md — verify Flutter parity  |
| `CR-0017` | REACT | P2 | `.agents/notes/archived/feature/2026-07-3` → `.agents/notes/archived/feature/2026-07-3` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-07-31-gui-full-access-confirmation.zh.md — verify Flutter pari |
| `CR-0018` | REACT | P2 | `.agents/notes/archived/feature/2026-08-0` → `.agents/notes/archived/feature/2026-08-0` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-08-05-pwsh-ui-bash-parity.i18n.yaml — verify Flutter parity fo |
| `CR-0019` | REACT | P2 | `.agents/notes/archived/feature/2026-08-0` → `.agents/notes/archived/feature/2026-08-0` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-08-05-pwsh-ui-bash-parity.md — verify Flutter parity for behav |
| `CR-0020` | REACT | P2 | `.agents/notes/archived/feature/2026-08-0` → `.agents/notes/archived/feature/2026-08-0` | Detected | [REACT] File changed: .agents/notes/archived/feature/2026-08-05-pwsh-ui-bash-parity.zh.md — verify Flutter parity for be |
| `CR-0021` | REACT | P2 | `.agents/notes/archived/simplification/20` → `.agents/notes/archived/simplification/20` | Detected | [REACT] File changed: .agents/notes/archived/simplification/2026-08-04-remove-tui-package.i18n.yaml — verify Flutter par |
| `CR-0022` | REACT | P2 | `.agents/notes/archived/simplification/20` → `.agents/notes/archived/simplification/20` | Detected | [REACT] File changed: .agents/notes/archived/simplification/2026-08-04-remove-tui-package.md — verify Flutter parity for |
| `CR-0023` | REACT | P2 | `.agents/notes/archived/simplification/20` → `.agents/notes/archived/simplification/20` | Detected | [REACT] File changed: .agents/notes/archived/simplification/2026-08-04-remove-tui-package.zh.md — verify Flutter parity  |
| `CR-0024` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-07-19-gui-web-client-architecture.i18n.yaml — verify F |
| `CR-0025` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-07-19-gui-web-client-architecture.md — verify Flutter  |
| `CR-0026` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-07-19-gui-web-client-architecture.zh.md — verify Flutt |
| `CR-0027` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml — verify F |
| `CR-0028` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md — verify Flutter  |
| `CR-0029` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md — verify Flutt |
| `CR-0030` | REACT | P2 | `.agents/notes/implemented/bug-fix/2026-0` → `.agents/notes/implemented/bug-fix/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/bug-fix/2026-07-28-web-gui-feedback-loop.i18n.yaml — verify Flutter pari |
| `CR-0031` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-25-workspace-ui-product-flow.i18n.yaml — verify Flutter  |
| `CR-0032` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-26-ptc-dispatch-ui-foundation.i18n.yaml — verify Flutter |
| `CR-0033` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.i18n.yaml — verify Flutt |
| `CR-0034` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-08-05-pwsh-ui-bash-parity.i18n.yaml — verify Flutter parity |
| `CR-0035` | REACT | P2 | `.agents/notes/implemented/simplification` → `.agents/notes/implemented/simplification` | Detected | [REACT] File changed: .agents/notes/implemented/simplification/2026-08-04-remove-tui-package.i18n.yaml — verify Flutter  |
| `CR-0036` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.i18n.yaml — verify Flutter p |
| `CR-0037` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.md — verify Flutter parity f |
| `CR-0038` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.zh.md — verify Flutter parit |
| `CR-0039` | REACT | P2 | `apps/web/package.json` → `apps/web/package.json` | Detected | [REACT] File changed: apps/web/package.json — verify Flutter parity for behavior/state fallback |
| `CR-0040` | REACT | P2 | `apps/web/tests/agent-preset-selection.e2` → `apps/web/tests/agent-preset-selection.e2` | Detected | [REACT] File changed: apps/web/tests/agent-preset-selection.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0041` | REACT | P2 | `apps/web/tests/approval-composer.e2e.ts` → `apps/web/tests/approval-composer.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/approval-composer.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0042` | REACT | P2 | `apps/web/tests/background-job-list.e2e.t` → `apps/web/tests/background-job-list.e2e.t` | Detected | [REACT] File changed: apps/web/tests/background-job-list.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0043` | REACT | P2 | `apps/web/tests/bash-abort-row.e2e.ts` → `apps/web/tests/bash-abort-row.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/bash-abort-row.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0044` | REACT | P2 | `apps/web/tests/built-boot.expected.e2e.t` → `apps/web/tests/built-boot.expected.e2e.t` | Detected | [REACT] File changed: apps/web/tests/built-boot.expected.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0045` | REACT | P2 | `apps/web/tests/chat-long-interactions.e2` → `apps/web/tests/chat-long-interactions.e2` | Detected | [REACT] File changed: apps/web/tests/chat-long-interactions.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0046` | REACT | P2 | `apps/web/tests/chat-scroll-contract.e2e.` → `apps/web/tests/chat-scroll-contract.e2e.` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-contract.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0047` | REACT | P2 | `apps/web/tests/chat-scroll-fixture.ts` → `apps/web/tests/chat-scroll-fixture.ts` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-fixture.ts — verify Flutter parity for behavior/state fallback |
| `CR-0048` | REACT | P2 | `apps/web/tests/clickable-links-gallery.e` → `apps/web/tests/clickable-links-gallery.e` | Detected | [REACT] File changed: apps/web/tests/clickable-links-gallery.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0049` | REACT | P2 | `apps/web/tests/command-image-envelope.ex` → `apps/web/tests/command-image-envelope.ex` | Detected | [REACT] File changed: apps/web/tests/command-image-envelope.expected.e2e.ts — verify Flutter parity for behavior/state f |
| `CR-0050` | REACT | P2 | `apps/web/tests/complex-history.perf.ts` → `apps/web/tests/complex-history.perf.ts` | Detected | [REACT] File changed: apps/web/tests/complex-history.perf.ts — verify Flutter parity for behavior/state fallback |
| … | … | … | … | … | … 619 more |

## Model / Type changes (heuristic)

Namespaces prev → current: 19 → 20 (agentPresets, agentTeams, commands, credentials, directoryPicker … → agentPresets, agentTeams, commands, credentials, directoryPicker …)

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
_Report generated by upstream-sync • upstream d347e703 → 5dda764e • local 5bbc7cbc_
