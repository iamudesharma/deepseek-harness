# Upstream Sync Report — 2026-09-05

> Generated: 2026-09-05T07:20:48.356Z
> Upstream: https://github.com/deepseek-ai/deepseek-harness.git @ master
> Old SHA: `cd5ef8148158c3a752a658978873241fdf8e2bbc` (`cd5ef814`) → New SHA: `d347e703908d0406b7a7ef80e3a0e594d86b2215` (`d347e703`)
> Local HEAD: `e40ce91f`  Merge-base: `d347e703`  Behind: 984  Ahead: 1105

## Summary

| Metric | Value |
|---|---|
| Commits | 984 |
| Files changed | 4641 |
| File categories | HOST:49, API:168, CLIENT:912, REACT:45, CORE:2248, INTERACTION:35, MODEL:101, STREAM:56, SECURITY:23, BUILD:75, DOCS:801, TEST:101, OTHER:27 |
| API operations (prev → current) | 91 → 92 |
| API changes | 4 (breaking: 3, additive: 1) |
| Stream changes | 0 |
| React surfaces | 967 |
| Flutter call sites | 160 in 355 files |
| Parity | PASS 56 / MISSING 1 / INCOMPATIBLE 0 / UNKNOWN 9 |
| Flutter impact | P0 5 · P1 1 · P2 1 · P3 0 |
| Registry entries | 960 |
| Parity gate | ❌ FAIL |
| Recommended action | P0 blocking — do not merge Flutter without fixes |

## Commits (upstream..new)

| SHA | Subject | Author | Date |
|---|---|---|---|
| `d347e703` | Merge pull request #3554 from deepseek-harness/release/dsh-0.1.3-alpha.1 | Yichen Jiang | 2026-09-04 |
| `5aff05a9` | Merge branch 'master' into release/dsh-0.1.3-alpha.1 | Yichen Jiang | 2026-09-04 |
| `2f77acb9` | Merge pull request #3558 from deepseek-harness/fix/web-clickable-links-gallery-golden | Yichen Jiang | 2026-09-04 |
| `c42ab9e1` | test(web): refresh the clickable-links gallery golden for the attachment button | Yichen Jiang | 2026-09-04 |
| `6a82a3b3` | Merge branch 'master' into release/dsh-0.1.3-alpha.1 | Yichen Jiang | 2026-09-04 |
| `0180c5cd` | Merge pull request #3547 from deepseek-harness/ihsiangzhang/tool-call-clickable-styles | ihsiang | 2026-09-04 |
| `e94f938c` | release(dsh): align file-upload version | Yichen Jiang | 2026-09-04 |
| `14befe7f` | Merge branch 'master' into release/dsh-0.1.3-alpha.1 | Yichen Jiang | 2026-09-04 |
| `9c137037` | Merge pull request #3556 from deepseek-harness/fix/web-skill-chip-rebuilt-message | Yichen Jiang | 2026-09-04 |
| `53f6590f` | Merge pull request #3109 from deepseek-harness/worktree/2984-generic-file-upload | CreatixChu | 2026-09-04 |
| `75d3402b` | fix(web): keep skill chips on rebuilt message nodes | Yichen Jiang | 2026-09-04 |
| `8ffdee4f` | feat(client): unify clickable-link language with link alias and category glyphs | yx.zhang | 2026-09-04 |
| `e28b58f8` | Merge remote-tracking branch 'origin/master' into worktree/2984-generic-file-upload | creatixchu | 2026-09-04 |
| `58ec1f08` | refactor(file-upload): keep storage helpers and the HTTP route package-private | creatixchu | 2026-09-04 |
| `ed67c224` | release(dsh): 0.1.3-alpha.1 | Yichen Jiang | 2026-09-04 |
| `267d755b` | Merge pull request #3552 from deepseek-harness/worktree/skill-fuzzy-search-53e21d | Yichen Jiang | 2026-09-04 |
| `1b470211` | fix(web): address review: index skill-name batches, bound slash tokens at whitespace, chip only the leading goal token | Yichen Jiang | 2026-09-04 |
| `d976849a` | fix(web): expect the goal command bubble to share the body face | Yichen Jiang | 2026-09-04 |
| `b4517fee` | Merge remote-tracking branch 'origin/master' into worktree/2984-generic-file-upload | creatixchu | 2026-09-04 |
| `7acc038b` | Merge pull request #3362 from deepseek-harness/refactor/session-persistence-write-lease | Turtle | 2026-09-04 |
| `9d947bd9` | Merge branch 'master' into worktree/skill-fuzzy-search-53e21d | Yichen Jiang | 2026-09-04 |
| `d0da8ccf` | fix(web): decorate slash tokens in bubbles from logged skill and command facts | Yichen Jiang | 2026-09-04 |
| `645c68da` | Merge pull request #3530 from deepseek-harness/turtle/pr-3520-review-followup | Turtle 2099 | 2026-09-04 |
| `46d20f8b` | feat(web): rank skill candidates with the shared fuzzy name ranker | Yichen Jiang | 2026-09-04 |
| `c58097a8` | feat(session-persistence-jsonl): cross-process write-ownership lease | Turtle | 2026-08-31 |
| `268cf010` | Merge remote-tracking branch 'origin/master' into worktree/2984-generic-file-upload | creatixchu | 2026-09-04 |
| `f0e52c27` | refactor(file-upload): tighten service boundaries | creatixchu | 2026-09-04 |
| `b6b2ec4a` | Merge pull request #3480 from deepseek-harness/fix/search-result-reveal-session | Dudu-0223 | 2026-09-04 |
| `bee0c13f` | Merge pull request #3513 from deepseek-harness/fix/test-tmp-teardown-self-clean | Chinesezjc | 2026-09-04 |
| `1f0a87eb` | Merge remote-tracking branch 'origin/master' into fix/test-tmp-teardown-self-clean | Chinesezjc | 2026-09-04 |
| `470ea852` | Merge origin/master into fix/search-result-reveal-session | Dudu-0223 | 2026-09-04 |
| `d8a995e0` | docs: align the changed-spec count with the merged-base diff (36) | Chinesezjc | 2026-09-04 |
| `df07f378` | Merge pull request #3516 from deepseek-harness/turtle/issue-2390-windows-hide-subprocess | Turtle | 2026-09-04 |
| `3f074437` | Merge branch 'master' into fix/test-tmp-teardown-self-clean | Chinesezjc | 2026-09-04 |
| `9656a174` | Merge pull request #3521 from deepseek-harness/turtle/issue-2349-windows-root-workspace | Turtle | 2026-09-04 |
| `705cd220` | test(web): migrate file upload snapshot to v2 | creatixchu | 2026-09-04 |
| `48656b45` | test(session-controller): restore Session type import | creatixchu | 2026-09-04 |
| `fb743759` | Merge remote-tracking branch 'origin/master' into worktree/2984-generic-file-upload | creatixchu | 2026-09-04 |
| `b4ea3efc` | Merge pull request #3400 from deepseek-harness/worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `1d35bcfc` | Merge pull request #3533 from deepseek-harness/gate/package-version-drift | Tianyi Cui | 2026-09-03 |
| `a931bcf2` | fix(constraints): require the shared dsh version in every workspace manifest | Tianyi Cui | 2026-09-03 |
| `8cb1d6a7` | Merge commit '85c23a2df3' into worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `86241a44` | fix(session): keep independent version fields off the format generation | Tianyi Cui | 2026-09-03 |
| `6c7603aa` | Merge commit '51f9d5f6c1' into worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `9fb0678f` | Merge commit '22472e4092' into worktree/session-format-05-v1-v2-chunk-migration | Tianyi Cui | 2026-09-03 |
| `721ff67c` | Merge commit '1b6fdd0e1b' into worktree/session-format-04-live-assistant-stream | Tianyi Cui | 2026-09-03 |
| `6c419795` | docs(session): name the frozen v0/v1 vocabulary in the v0-to-v1 README | Tianyi Cui | 2026-09-03 |
| `17fb7191` | Merge commit 'cf8f75faaf' into worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `d58964a0` | Merge commit 'be5db297c7' into worktree/session-format-05-v1-v2-chunk-migration | Tianyi Cui | 2026-09-03 |
| `8a0c91be` | Merge commit 'c347bfcfa6' into worktree/session-format-04-live-assistant-stream | Tianyi Cui | 2026-09-03 |
| `fe9c2d70` | refactor(agent, session-controller): drop the unread startedTime frame field | Tianyi Cui | 2026-09-03 |
| `c97df989` | refactor(session): share the canonical log basename and JSON snapshots | Tianyi Cui | 2026-09-03 |
| `de022388` | test(ci): stabilize attachment fixtures | creatixchu | 2026-09-03 |
| `d18770f5` | fix(web): address latest session reveal review | Dudu-0223 | 2026-09-03 |
| `0516edb0` | test(file-upload): restore host composition fixtures | creatixchu | 2026-09-03 |
| `2a826a93` | Merge remote-tracking branch 'origin/master' into worktree/2984-generic-file-upload | creatixchu | 2026-09-03 |
| `ea669428` | refactor(attachment): unify prompt content admission | creatixchu | 2026-09-03 |
| `3eb9736e` | refactor(file-upload): scope prompt binding rollback | creatixchu | 2026-09-03 |
| `71089f8d` | Merge commit '8f7250f904' into worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `874b174f` | test(web): compare fixture inventories by Session role and pin the v2 upload | Tianyi Cui | 2026-09-03 |
| `d5044d56` | Merge commit 'ee4bad5cde' into worktree/session-format-05-v1-v2-chunk-migration | Tianyi Cui | 2026-09-03 |
| `bb771b13` | Merge commit '09d3a185ab' into worktree/session-format-04-live-assistant-stream | Tianyi Cui | 2026-09-03 |
| `d455ad99` | test(session): record the v2 SDK expectations and cover review-fix branches | Tianyi Cui | 2026-09-03 |
| `dde27f51` | Merge remote-tracking branch 'origin/master' into fix/test-tmp-teardown-self-clean | Chinesezjc | 2026-09-03 |
| `6e7c3f37` | docs(fs): record normalized unread diagnostics | Turtle | 2026-09-03 |
| `a05b5fbe` | fix(subprocess): hide Windows cleanup helpers | Turtle | 2026-09-03 |
| `e609fd73` | fix(workspace): harden qualified path handling | Turtle | 2026-09-03 |
| `778e0866` | test(session): cover the migration read faults and the versioned export name | Tianyi Cui | 2026-09-03 |
| `91904d7c` | Merge commit 'fef079e5c9' into worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `156429e8` | chore(session): satisfy the master gates on the v1-to-v2 branch | Tianyi Cui | 2026-09-03 |
| `28b16c01` | Merge commit 'a123cb0055' into worktree/session-format-05-v1-v2-chunk-migration | Tianyi Cui | 2026-09-03 |
| `13074e4a` | Merge commit '308c1c69a6' into worktree/session-format-04-live-assistant-stream | Tianyi Cui | 2026-09-03 |
| `3c3ad02b` | chore(session): satisfy the master hygiene gates | Tianyi Cui | 2026-09-03 |
| `3aef6479` | Merge master into session format migration | Tianyi Cui | 2026-09-03 |
| `b2c4483c` | refactor(attachment): own prompt admission on service | creatixchu | 2026-09-03 |
| `cf4cfd9e` | docs: correct the changed-spec count in the Agent Note verification section | Chinesezjc | 2026-09-03 |
| `818c4f34` | Merge pull request #3520 from deepseek-harness/turtle/issue-2353-fs-error-copy | Turtle | 2026-09-03 |
| `d89427ba` | Merge commit '12dabcc9d2' into worktree/session-format-06-v2-snapshot-rollout | Tianyi Cui | 2026-09-03 |
| `5fa5fea1` | Merge commit '1f9d5f72e9' into worktree/session-format-05-v1-v2-chunk-migration | Tianyi Cui | 2026-09-03 |
| `51adfbf5` | chore(session): retire the v1-to-v2 benchmark script | Tianyi Cui | 2026-09-03 |
| `7c169a04` | Merge commit '1a244059c3' into worktree/session-format-04-live-assistant-stream | Tianyi Cui | 2026-09-03 |
| `13dee20d` | refactor(session): drop dead migration plumbing | Tianyi Cui | 2026-09-03 |
| `af63a560` | test(workspace): make relative path regression portable | Turtle | 2026-09-03 |
| `c8fc3854` | test: own the default spill dir in subprocess specs; correct retention wording | Chinesezjc | 2026-09-03 |
| `d33fe767` | fix(workspace): preserve Windows drive roots | Turtle | 2026-09-03 |
| `18635905` | fix(fs): normalize unread mutation diagnostics | Turtle | 2026-09-03 |
| `1bc330ce` | docs: cross-link the spill retention decision from the teardown note | Chinesezjc | 2026-09-03 |
| `29e6669e` | test: narrow process-exit spill cleanup to empty dirs; drop spill-store deletion | Chinesezjc | 2026-09-03 |
| `cc8099dc` | fix(subprocess): hide Windows child windows | Turtle | 2026-09-03 |
| `f989df7c` | test(file-upload): cover extensible request identifiers | creatixchu | 2026-09-03 |
| `8a84c1ed` | test(file-upload): cover isolated service paths | creatixchu | 2026-09-03 |
| `33b7123e` | test(remotes): declare built smoke schema dependency | creatixchu | 2026-09-03 |
| `3b8245af` | fix(build): align file upload project faces | creatixchu | 2026-09-03 |
| `71582276` | fix(file-upload): declare host runtime dependencies | creatixchu | 2026-09-03 |
| `6d9776a3` | test: exempt process-exit spill cleanup from the per-file coverage gate | Chinesezjc | 2026-09-03 |
| `1107ff5f` | test: remove remaining dsh-* spill/temp dirs in shell and fs specs | Chinesezjc | 2026-09-03 |
| `9fd72003` | chore(test): remove obsolete lint suppression | creatixchu | 2026-09-03 |
| `dd37061c` | test(client): provide file upload fixture service | creatixchu | 2026-09-03 |
| `0364343a` | test: remove dsh-* temp dirs created by unit tests at teardown | Chinesezjc | 2026-09-03 |
| `a22f2105` | fix(test): stabilize trajectory history pagination | Dudu-0223 | 2026-09-03 |
| … | … 884 more | … | … |

## Files changed by category

| Category | Count | Sample files |
|---|---|---|
| CORE | 2248 | `.agents/notes/archived/architecture/2026-08-15-packed-session-history-transport.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-08-15-packed-session-history-transport.md`<br>`.agents/notes/archived/architecture/2026-08-15-packed-session-history-transport.zh.md` |
| CLIENT | 912 | `apps/web/package.json`<br>`apps/web/tests/access-confirmation.e2e.ts`<br>`apps/web/tests/agent-preset-authoring.e2e.ts` |
| DOCS | 801 | `.agents/notes/archived/architecture/2026-06-18-shared-persistence-write-coordinator.i18n.yaml`<br>`.agents/notes/archived/architecture/2026-06-18-shared-persistence-write-coordinator.md`<br>`.agents/notes/archived/architecture/2026-06-18-shared-persistence-write-coordinator.zh.md` |
| API | 168 | `.agents/notes/implemented/architecture/2026-08-02-typert-remote-method-calls.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-02-typert-remote-method-calls.md`<br>`.agents/notes/implemented/architecture/2026-08-02-typert-remote-method-calls.zh.md` |
| MODEL | 101 | `packages/llm/deepseek-llm-api-extensions/README.i18n.yaml`<br>`packages/llm/deepseek-llm-api-extensions/README.md`<br>`packages/llm/deepseek-llm-api-extensions/README.zh.md` |
| TEST | 101 | `apps/cli/tests/built-bin.e2e.ts`<br>`apps/cli/tests/fixtures/dsh-badge/snapshot.ts`<br>`apps/cli/tests/github-webhook-real.e2e.ts` |
| BUILD | 75 | `.github/issue-management/config.json`<br>`.github/issue-management/policy.mjs`<br>`.github/issue-management/policy.test.mjs` |
| STREAM | 56 | `.agents/notes/implemented/architecture/2026-08-10-cancelled-stream-prefix-finalize.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-10-cancelled-stream-prefix-finalize.md`<br>`.agents/notes/implemented/architecture/2026-08-10-cancelled-stream-prefix-finalize.zh.md` |
| HOST | 49 | `packages/host/directory-picker-auto/README.i18n.yaml`<br>`packages/host/directory-picker-auto/README.md`<br>`packages/host/directory-picker-auto/README.zh.md` |
| REACT | 45 | `.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml`<br>`.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md`<br>`.agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md` |
| INTERACTION | 35 | `packages/interaction/commands/README.i18n.yaml`<br>`packages/interaction/commands/README.md`<br>`packages/interaction/commands/README.zh.md` |
| OTHER | 27 | `.gitignore`<br>`.gitlab-ci.yml`<br>`apps/cli/config/examples/schedule/cordis.yml` |
| SECURITY | 23 | `.agents/notes/implemented/feature/2026-08-24-user-authorized-subagent-model-routes.i18n.yaml`<br>`.agents/notes/implemented/feature/2026-08-24-user-authorized-subagent-model-routes.md`<br>`.agents/notes/implemented/feature/2026-08-24-user-authorized-subagent-model-routes.zh.md` |

## API changes

| # | Kind | Endpoint | Severity | Description |
|---|---|---|---|---|
| 1 | pluralization | `subagents/interruptByParent` | P0 | Namespace pluralization: subagent/interruptByParent → subagents/interruptByParent |
| 2 | pluralization | `subagents/list` | P0 | Namespace pluralization: subagent/list → subagents/list |
| 3 | pluralization | `subagents/prompt` | P0 | Namespace pluralization: subagent/prompt → subagents/prompt |
| 4 | added | `fileUploads/upload` | P2 | Endpoint added: fileUploads/upload (service fileUploads, mode unary) from packages/client/file-upload/src/index.ts:106 |

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
| P0 (blocks runtime) | 5 |
| P1 (feature broken) | 1 |
| P2 (compat risk) | 1 |
| P3 (informational) | 0 |

| ID | Change | Sev | Affected Flutter files | Required action |
|---|---|---|---|---|
| `flutter:session/page-cursor` | session/page throughSeq sentinel vs cursor | P0 | connection/connection_client.dart<br>session/live_history.dart | verify Flutter getSessionHistory requires throughSeq and waits for LiveHistory.acceptedSeq; no fabricated cursor |
| `flutter:settings-describe-list` | settings/describe List namespaces | P0 | settings/settings_scope.dart<br>settings/settings_screen.dart | ensure SettingsScope._refreshNow handles List<Map> and fallback forms; verified in be6498fd |
| `pluralization:subagent/interruptByParent->subagents/interruptByParent` | pluralization: subagent/interruptByParent → subagents/interruptByParent | P0 | connection/connection_client.dart | audit Flutter consumers of subagents/interruptByParent |
| `pluralization:subagent/list->subagents/list` | pluralization: subagent/list → subagents/list | P0 | connection/connection_client.dart | audit Flutter consumers of subagents/list |
| `pluralization:subagent/prompt->subagents/prompt` | pluralization: subagent/prompt → subagents/prompt | P0 | connection/connection_client.dart | audit Flutter consumers of subagents/prompt |
| `flutter:remote-mux-ticket` | remote.mux bearer ticket flow | P1 | connection/remote_mux_client.dart<br>connection/connection_client.dart | verify ticket fetch and re-pair flow; no silent fallback to unauthenticated |
| `added:fileUploads/upload` | added: ∅ → fileUploads/upload | P2 | — | evaluate if Flutter should consume new endpoint |

## Change registry (excerpt)

| ID | Category | Sev | Old → New | Status | Description |
|---|---|---|---|---|---|
| `CR-0001` | API | P0 | `subagent/interruptByParent` → `subagents/interruptByParent` | Detected | [API pluralization] Namespace pluralization: subagent/interruptByParent → subagents/interruptByParent |
| `CR-0002` | API | P0 | `subagent/list` → `subagents/list` | Detected | [API pluralization] Namespace pluralization: subagent/list → subagents/list |
| `CR-0003` | API | P0 | `subagent/prompt` → `subagents/prompt` | Detected | [API pluralization] Namespace pluralization: subagent/prompt → subagents/prompt |
| `CR-0004` | API | P2 | `∅` → `fileUploads/upload` | Detected | [API added] Endpoint added: fileUploads/upload (service fileUploads, mode unary) from packages/client/file-upload/src/in |
| `CR-0005` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.i18n.yaml — verify F |
| `CR-0006` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.md — verify Flutter  |
| `CR-0007` | REACT | P2 | `.agents/notes/implemented/architecture/2` → `.agents/notes/implemented/architecture/2` | Detected | [REACT] File changed: .agents/notes/implemented/architecture/2026-08-23-locale-owned-client-ui-copy.zh.md — verify Flutt |
| `CR-0008` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-26-ptc-dispatch-ui-foundation.i18n.yaml — verify Flutter |
| `CR-0009` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-26-ptc-dispatch-ui-foundation.md — verify Flutter parity |
| `CR-0010` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-26-ptc-dispatch-ui-foundation.zh.md — verify Flutter par |
| `CR-0011` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.i18n.yaml — verify Flutt |
| `CR-0012` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.md — verify Flutter pari |
| `CR-0013` | REACT | P2 | `.agents/notes/implemented/feature/2026-0` → `.agents/notes/implemented/feature/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/feature/2026-07-31-gui-full-access-confirmation.zh.md — verify Flutter p |
| `CR-0014` | REACT | P2 | `.agents/notes/implemented/process/2026-0` → `.agents/notes/implemented/process/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/process/2026-07-20-gui-testing-system.i18n.yaml — verify Flutter parity  |
| `CR-0015` | REACT | P2 | `.agents/notes/implemented/process/2026-0` → `.agents/notes/implemented/process/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/process/2026-07-20-gui-testing-system.md — verify Flutter parity for beh |
| `CR-0016` | REACT | P2 | `.agents/notes/implemented/process/2026-0` → `.agents/notes/implemented/process/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/process/2026-07-20-gui-testing-system.zh.md — verify Flutter parity for  |
| `CR-0017` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.i18n.yaml — verify Flutter p |
| `CR-0018` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.md — verify Flutter parity f |
| `CR-0019` | REACT | P2 | `.agents/notes/implemented/testing/2026-0` → `.agents/notes/implemented/testing/2026-0` | Detected | [REACT] File changed: .agents/notes/implemented/testing/2026-07-24-web-gui-browser-e2e-lane.zh.md — verify Flutter parit |
| `CR-0020` | REACT | P2 | `apps/web/package.json` → `apps/web/package.json` | Detected | [REACT] File changed: apps/web/package.json — verify Flutter parity for behavior/state fallback |
| `CR-0021` | REACT | P2 | `apps/web/tests/access-confirmation.e2e.t` → `apps/web/tests/access-confirmation.e2e.t` | Detected | [REACT] File changed: apps/web/tests/access-confirmation.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0022` | REACT | P2 | `apps/web/tests/agent-preset-authoring.e2` → `apps/web/tests/agent-preset-authoring.e2` | Detected | [REACT] File changed: apps/web/tests/agent-preset-authoring.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0023` | REACT | P2 | `apps/web/tests/agent-preset-selection.e2` → `apps/web/tests/agent-preset-selection.e2` | Detected | [REACT] File changed: apps/web/tests/agent-preset-selection.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0024` | REACT | P2 | `apps/web/tests/agent-team-panel.e2e.ts` → `apps/web/tests/agent-team-panel.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/agent-team-panel.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0025` | REACT | P2 | `apps/web/tests/agent-team-panel.overlay.` → `apps/web/tests/agent-team-panel.overlay.` | Detected | [REACT] File changed: apps/web/tests/agent-team-panel.overlay.yml — verify Flutter parity for behavior/state fallback |
| `CR-0026` | REACT | P2 | `apps/web/tests/approval-composer.e2e.ts` → `apps/web/tests/approval-composer.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/approval-composer.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0027` | REACT | P2 | `apps/web/tests/background-job-list.e2e.t` → `apps/web/tests/background-job-list.e2e.t` | Detected | [REACT] File changed: apps/web/tests/background-job-list.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0028` | REACT | P2 | `apps/web/tests/bash-abort-row.e2e.ts` → `apps/web/tests/bash-abort-row.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/bash-abort-row.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0029` | REACT | P2 | `apps/web/tests/chat-continuous-conversat` → `apps/web/tests/chat-continuous-conversat` | Detected | [REACT] File changed: apps/web/tests/chat-continuous-conversation.e2e.ts — verify Flutter parity for behavior/state fall |
| `CR-0030` | REACT | P2 | `apps/web/tests/chat-long-interactions.e2` → `apps/web/tests/chat-long-interactions.e2` | Detected | [REACT] File changed: apps/web/tests/chat-long-interactions.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0031` | REACT | P2 | `apps/web/tests/chat-scroll-contract.e2e.` → `apps/web/tests/chat-scroll-contract.e2e.` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-contract.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0032` | REACT | P2 | `apps/web/tests/chat-scroll-fixture.ts` → `apps/web/tests/chat-scroll-fixture.ts` | Detected | [REACT] File changed: apps/web/tests/chat-scroll-fixture.ts — verify Flutter parity for behavior/state fallback |
| `CR-0033` | REACT | P2 | `apps/web/tests/clickable-links-gallery.e` → `apps/web/tests/clickable-links-gallery.e` | Detected | [REACT] File changed: apps/web/tests/clickable-links-gallery.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0034` | REACT | P2 | `apps/web/tests/cold-blank-session.e2e.ts` → `apps/web/tests/cold-blank-session.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/cold-blank-session.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0035` | REACT | P2 | `apps/web/tests/command-image-envelope.ex` → `apps/web/tests/command-image-envelope.ex` | Detected | [REACT] File changed: apps/web/tests/command-image-envelope.expected.e2e.ts — verify Flutter parity for behavior/state f |
| `CR-0036` | REACT | P2 | `apps/web/tests/complex-history.perf.ts` → `apps/web/tests/complex-history.perf.ts` | Detected | [REACT] File changed: apps/web/tests/complex-history.perf.ts — verify Flutter parity for behavior/state fallback |
| `CR-0037` | REACT | P2 | `apps/web/tests/conversation-column-overf` → `apps/web/tests/conversation-column-overf` | Detected | [REACT] File changed: apps/web/tests/conversation-column-overflow.e2e.ts — verify Flutter parity for behavior/state fall |
| `CR-0038` | REACT | P2 | `apps/web/tests/cordis-tool-round.e2e.ts` → `apps/web/tests/cordis-tool-round.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/cordis-tool-round.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0039` | REACT | P2 | `apps/web/tests/declared-reasoning.e2e.ts` → `apps/web/tests/declared-reasoning.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/declared-reasoning.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0040` | REACT | P2 | `apps/web/tests/default-model.e2e.ts` → `apps/web/tests/default-model.e2e.ts` | Detected | [REACT] File changed: apps/web/tests/default-model.e2e.ts — verify Flutter parity for behavior/state fallback |
| `CR-0041` | REACT | P2 | `apps/web/tests/details-session-lifecycle` → `apps/web/tests/details-session-lifecycle` | Detected | [REACT] File changed: apps/web/tests/details-session-lifecycle.e2e.ts — verify Flutter parity for behavior/state fallbac |
| `CR-0042` | REACT | P2 | `apps/web/tests/expected/access-confirmat` → `apps/web/tests/expected/access-confirmat` | Detected | [REACT] File changed: apps/web/tests/expected/access-confirmation/ui.expected.md — verify Flutter parity for behavior/st |
| `CR-0043` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/created.expected.md — verify Flutter parity for beh |
| `CR-0044` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/damaged.expected.md — verify Flutter parity for beh |
| `CR-0045` | REACT | P2 | `apps/web/tests/expected/agent-preset-aut` → `apps/web/tests/expected/agent-preset-aut` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-authoring/section.expected.md — verify Flutter parity for beh |
| `CR-0046` | REACT | P2 | `apps/web/tests/expected/agent-preset-sel` → `apps/web/tests/expected/agent-preset-sel` | Detected | [REACT] File changed: apps/web/tests/expected/agent-preset-selection/menu.expected.md — verify Flutter parity for behavi |
| `CR-0047` | REACT | P2 | `apps/web/tests/expected/clickable-links-` → `apps/web/tests/expected/clickable-links-` | Detected | [REACT] File changed: apps/web/tests/expected/clickable-links-gallery/ui.expected.md — verify Flutter parity for behavio |
| `CR-0048` | REACT | P2 | `apps/web/tests/expected/cold-blank-sessi` → `apps/web/tests/expected/cold-blank-sessi` | Detected | [REACT] File changed: apps/web/tests/expected/cold-blank-session/sidebar.expected.md — verify Flutter parity for behavio |
| `CR-0049` | REACT | P2 | `apps/web/tests/expected/composer-tab-geo` → `apps/web/tests/expected/composer-tab-geo` | Detected | [REACT] File changed: apps/web/tests/expected/composer-tab-geometry/geometry.expected.md — verify Flutter parity for beh |
| `CR-0050` | REACT | P2 | `apps/web/tests/expected/conversation-col` → `apps/web/tests/expected/conversation-col` | Detected | [REACT] File changed: apps/web/tests/expected/conversation-column-overflow/geometry.expected.md — verify Flutter parity  |
| … | … | … | … | … | … 910 more |

## Model / Type changes (heuristic)

Namespaces prev → current: 18 → 19 (agent-team, agentPresets, commands, cordis-host-runner, credentials … → agent-team, agentPresets, commands, cordis-host-runner, credentials …)

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
_Report generated by upstream-sync • upstream cd5ef814 → d347e703 • local e40ce91f_
