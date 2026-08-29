# Agent Note: Flutter 中 ui-tool / ui-trajectory / ui-message-feedback 的聊天插件接缝

Status: implemented

[English](2026-08-22-flutter-ws-chat-plugin-seams.md) | 中文

## 问题

React 客户端通过 slot 条目组合 `ui-tool`、`ui-trajectory` 与 `ui-message-feedback`（`conversation.chat.node` 的键 `'tool-call'`、子洞 `tool.call.toolview`、`conversation.view`、`conversation.chat.assistant-actions`）。Flutter 会话插件则经由另一条接缝驱动聊天节点渲染——hub.dart 中的 `ConversationController.renderers`，按节点种类键分发，其中 `ToolNode` 以线上工具名分发——且账本只声明了四个键（`conversation`、`conversation.session.header.actions`、`conversation.composer.dock`、`conversation.details`）。把这三个包按 1:1 移植只会注册进永远无人声明、也永远不会被渲染的洞。

## 决策

每个包作为 `DshPlugin` 落在 `apps/flutter/lib/src/plugins/{tool,trajectory,message_feedback}/`，把 slot 语义翻译到今天真正参与渲染的接缝上：

- **ui-tool** 在 `ConversationController.renderers` 上为每个线上工具名注册一个 chat-node 渲染器——这是 React 键控 `'tool-call'` 条目的 Dart 对应物，因为 Flutter 折叠每次调用保留一个 `ToolNode`。子洞 `tool.call.toolview` 变成服务 `'toolPresentation'`：一个键域开放、`register` 冲突即抛的 `ToolPresentationRegistry`，未认领的名字在分发现场落到通用卡片，与 React 的 `fallback:` 参数一致。内置呈现镜像 React 的注册（bash/read 行、edit/write diff 卡、grep/glob 搜索卡）；todo/web/ask 行暂不认领，保持通用回退直至移植。
- **ui-trajectory** 保留 React 的账本形态：对 `conversation.view`（id `'trajectory'`，order 10）的 wait-and-follow 注入在壳声明该洞后安装，渲染当前选中会话的 provider 版屏幕。React 的 `conversationEvents`/`conversationViews` 服务尚无 Dart 对应物，因此时间线折叠未重新实现。
- **ui-message-feedback** 提供服务 `'messageFeedback'`（每会话控制器），并移植携带真实语义的控制器切片：一次性列表播种、经尾 future 串行化的变更、带版本 CAS 及从 `version-conflict` 回应中权威行和解的行为。assistant-actions 账本条目同时等待未声明的洞与生成的 remote 命名空间。

特性组件连同行为一起迁移：provider 版工具树迁至 `plugins/tool/ui/tool_call_tree.dart`，trajectory 屏幕与 provider 迁至 `plugins/trajectory/`，feedback 屏幕与 provider 迁至 `plugins/message_feedback/`。旧 feature 路径保留两个兼容 re-export 垫片（`features/tool/tool_models.dart`、`features/trajectory/trajectory_screen.dart`），唯一原因是作用域外的引用方（WIP `chat_ui_adapter_test.dart`、`app_router.dart`）仍指向它们；随各自引用方的更新一并删除。

## 曾考虑的替代方案

**仍然向 `conversation.chat.node` 注册账本条目**（排队等待声明）。否决：Dart 组合中没有任何壳声明该子树，注册会成为永久死机器，而真正的分发走的是渲染器注册表。

**扩展 `ChatNodeData` 携带 status/args/sessionId**，让工具渲染器看到完整调用。此处否决：这是属于另一工作流的会话插件契约变更；当前适配器从折叠已确定暴露的内容推导（一行 = running，两行 = settled），共享数据增长后自动变富。

## 后果

工具卡片、trajectory 页签与 feedback 控制器无需启动完整壳即可测试；`test/plugins/ws_chat/` 覆盖按折叠工具名的注册表分发、trajectory 页签的声明即安装、以及 toggle/撤回/冲突控制器语义。详情面板（`conversation.details.tool`）、assistant-actions 接线与 todo/web/ask 摘要行刻意缺席，由各自的集成工作落地——未认领的名字渲染通用卡片而不是失败。
