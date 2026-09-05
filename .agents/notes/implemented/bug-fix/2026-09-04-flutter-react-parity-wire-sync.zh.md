# Agent Note: Flutter 同步其 RPC 面到 React 线协议契约

Status: implemented

[English](2026-09-04-flutter-react-parity-wire-sync.md) | 中文

## Problem

2026-09-04 的 React↔Flutter parity 审计发现 Flutter 客户端调用了不存在的线协议面、
跳过了 React 依赖的面、并在实时流上与 React 分歧：

- `ConnectionClient.workspaceList()` POST `workspace/list`，但
  `WorkspaceController` 只提供 `workspace/follow` baseline 加增量 —— 每次调用都
  404，而 `selection_restore.dart` 吞掉了失败，导致持久化的 workspace 选择从未
  被校验。
- 两处 `session/fork` 调用点发送不同的参数形状（chat 用 `{sessionId, atSeq}`，
  sidebar 用裸 `agentId`），`session/rename` 发送 `agentId` 而 host 请求字段是
  `sessionId`。
- React 使用的一些面完全没有 Flutter 调用方：`session/canOpenWorkspacePath`、
  `session/openWorkspacePath`、`settings/replace`、`settings/openSettingsDocument`
  和 `subagents/list|prompt|interruptByParent`。产物行因此没有 host 打开器门控，
  设置页没有文档动作，subagent 子流量没有通往其父授权面的路由。
- 实时 assistant 流把 reasoning 与 text 增量熔进同一个 buffer，流式视图因此
  丢掉了 React `PartialAssistant` 保留的区分。
- `RemoteMuxClient.close()` 在循环内 await 的同时迭代 `_streams.values`；并发的
  generation 可能在该 await 期间改动 map，挂起路径随之以 concurrent modification
  崩溃（表现为 `app_lifecycle_matrix_test.dart` 13 个失败）。

## Decision

`ConnectionClient` 为每个列出的端点提供类型化面，各自匹配 host 请求 schema，并由
`test/api/connection_client_rpc_test.dart` 中的 scripted-host 线协议测试钉住：
`forkSession`、`renameSession`、`workspaceArchiveSession`、`settingsReplace`、
`settingsOpenDocument`、`canOpenWorkspacePath`、`openWorkspacePath`、
`subagentList`、`subagentPrompt`、`subagentInterrupt`。随行修复了三个已提交代码
中的产品缺陷：`session/page` `records` 条目被多剥了一层（`loadOlder` 因此在真实
host 上静默失效）、旧式点分路径 `hostDescribe` fallback 把 401/403 溶进空兼容
stub（被拒绝的 bearer 因此永远到不了 `needsReauth`）、以及目录选择器 probe 会
在远端设备上弹出 host 的原生 OS 对话框（远端调用方现在无 probe 直接解析
`browse`）。

- `workspaceList()` 已退役：改为抛出指名 `workspaceListProvider` follow baseline
  的 `UnsupportedError`，而不是 POST 一个 404。`selection_restore.dart` 用该
  baseline 校验持久化的 workspace id；只匹配合成 `kWorkspaceOptions` fallback 的
  id 视为缺失，过期 id 因此永远无法复活。
- sidebar 与 chat 的 fork 调用点都走 `forkSession`；sidebar 重命名走
  `renameSession`；sidebar 归档走 `workspaceArchiveSession`。参数形状单一来源。
- `settingsReplace` 通过 `_unwrapNamespaceView` 解包，返回完整的
  `SettingsNamespaceView`（`ns`、`value`、`revision`），不做旧式 `value` 层折叠，
  因为返回的 revision 正是下一次写入的 `expectedRevision` fence 要读的值。
- `DeliverablesScreen` 通过 `canOpenHostPathProvider` 轮询 `canOpenWorkspacePath`，
  打开动作经 `openWorkspacePath` 交接；挂载点的 `canOpenPath` prop 与轮询结果
  取或。React 门控里的 `isLoopback` 一半在 Flutter 没有对应物：打开器能力是
  host 桌面事实，打开动作无论何时都在 host 侧执行。
- 设置 General 页仅在 `settings/describe` 回答 `hasDocument` 后渲染
  `openDocument` 动作，并发手势收敛到一个在途打开，失败用本地化的
  `openDocument.error` 行报告；此前注释声称已移植但实际缺失的
  `openDocument`/`openDocument.error` 两个键现已补进两份词典。
- `ConversationController.sendToSubagent` 与 `interruptSubagent` 是被寻址子代理的
  父授权面。`subagent_link.dart` 记录地址推导策略：子代理 `mode` 与父可用性来自
  `subagents/list`，绝不来自 session summary，因此子代理 prompt/stop 只在持有
  地址的调用点走这两个面；在 descriptor-backed selection 工作流把地址贯穿导航
  之前，子代理面保持只读。
- `messagesFromHistory` 分开缓冲 reasoning 与 text 增量，flush 为独立的
  `AssistantBlock`（`reasoning` 在 `text` 前）；纯文本面只承载正文。最终
  `assistant/message` 路径不变。
- `RemoteMuxClient.close()` 在 await 前迭代 `_waiters` 与 `_streams` 的副本。

## Alternatives considered

**各调用点继续保留裸 `callMethod` 形状。** 落选：审计中的 fork 分歧正源于此 ——
两个调用点各自发明 envelope。每端点一个类型化面让 scripted 线协议测试拥有单一
权威。

**在 `ConversationController.send` 内用 session summary 查父级自动路由子代理
发送。** 落选：summary 携带父级但不携带 `mode`；把 one-shot 子代理送进
`subagents/prompt` 会产生 addressed-client 设计在构造上就该阻止的
`subagent/not-resumable` 失败。显式持有地址的调用点保住了 descriptor 门控的
诚实性。

**`settings/replace` 像兄弟写面一样经 `_unwrapValue` 解包。** 落选：
`_unwrapValue` 为历史 wrapper 形状剥掉一层 `value`，也会剥掉 namespace view 自己
的 `value` 并连带丢掉 `ns`/`revision`。兄弟面容忍折叠是因为调用方每次写入后都会
重新 `describe`；replace 面存在的意义就是那个 revision。

**超出 close 副本修复范围去修 lifecycle matrix。** 延后：剩余握手失败在 HEAD
复现（已在 `daa8c5aeae` 的干净 worktree 验证），且位于有在途编辑的面；仅
close 副本修复就把该文件从 13 个失败降到 9 个。

## Consequences

Flutter 客户端现在说出 React 说的每一条线协议面，死掉的 404 路径及其被吞掉的
失败不复存在，过期的持久化选择改为清除而不是对着合成数据校验通过。被审计套件
中十四个此前失败的测试现在通过：`session/list` envelope 期望、六个
devices-navigation 用例、三个 `sendMessage` 图片 payload fixture、三个
`updateQueue` payload fixture、401 传播用例、远端选择器用例，以及 records
rewrap 落地后的 cursor 用例（`session_page_fix`）。reasoning 拆分有专属单元
测试；restore fallback 规则有专属测试。

剩余失败全部属于同一类：连接握手测试（`connection_generation_test` ×2、
`app_lifecycle_matrix_test` ×8）等待 scripted fixture 从不发送的
`$events`/`remote.mux` `ready` 帧，generation 因此到不了 `connected`。它们在
HEAD 上逐字复现（已在 `daa8c5aeae` 的干净 worktree 验证），且位于
`connection_controller.dart` / `live_sync.dart` / `_LifecycleHost` —— 均带在途
编辑，控制器与 fixture 的契约归属该工作流，不属于本次同步。Flutter 仅从携带整数
`cursor` 的 `session/follow` snapshot 替换历史，因此任何 `session/page` 请求都不会继承
合成切点。Busy Enter 行共享接受列表、映射和具名映射形式的 settings namespace reader。上游
extractor 识别 Typert remote subclass 中的每个 `super(ctx, serviceKey)`，其 fallback 使用
`subagents` service key，因此重新生成的 contract 保留实际的 subagent endpoint。
