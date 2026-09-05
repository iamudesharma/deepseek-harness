# Agent Note: Flutter 工具行派生与 React 一致的摘要且 Markdown 代码高亮

Status: implemented

[English](2026-09-05-flutter-tool-card-markdown-parity.md) | 中文

## Problem

Flutter 聊天工具行显示工具名加原始结果字符串首行，因此 `write` 行打印面向模型的
`<path>/Volumes/…/CartDrawer.jsx</path>` 信封与绝对路径，而不是 React 的
`Write · src/components/CartDrawer.jsx +88 −0`。Flutter 侧不存在 diff 统计、
分工具摘要与路径相对化，而助手 Markdown 经由已停更的 `flutter_markdown`
渲染，其代码块自述无语法高亮。

## Decision

Flutter 拥有与 React 相同的客户端派生展示：行从 wire 工具名加原始参数 JSON
加持久结果元数据派生，绝不从结果文本派生。

- `apps/flutter/lib/src/plugins/tool/presentation/` 承载纯模型：
  `tool_row_model.dart`（变体分类、标题键、参数派生摘要、可打开文件路径、
  错误/中断状态）、`diff_model.dart`（运行时参数意图 diff、 settled 后
  `meta.diffs` 应用 hunks、仅 write 的参数回退、与 React 一致的 `+N −N`
  计数与尾换行规则）、`terminal_model.dart`（前台与 `run_in_background` 区分、
  description 优先摘要、`[exit code: N]` / `[killed by signal: X]` 解析、
  工作目录解析）、`todo_model.dart`（`N/M completed · active` 与并行额外数）、
  `read_model.dart`（信封加元数据收窄）与 `path_utils.dart`
  （`relativizeToCwd` 加既有 home 缩写）。
- `ToolCall` 保留原始 `arguments` JSON 于 `argsRaw`，并保留 `tool/result` 的
  持久 `meta`/`errorCode`；`toolCallsFromHistory` 解码规范的
  `arguments` 字符串形态（兼容旧 map 形态）。`ToolNode` 在 fold、settled、
  子调用投影与聊天视图适配中保留同样三项事实。
- 聊天行（`keyed_tool_card.dart`）、无注册表回退行与旧 `ToolCallTree` 行渲染
  本地化标题（`Write`、`Bash`、`Update to-do list`、`Think`）、参数派生摘要
 （bash 取 description、todo 取计数、文件路径取相对路径）、write/edit 的
  `+N −N` 后缀、错误时失败首行，以及经 `canOpenWorkspacePath` 门控的文件
  host 打开。推理行标题按 locale 显示 `Think`/`思考`。
- Trajectory 账本 `tool/call` 单元格取同样参数摘要，`tool/result` 单元格拍平
  message 内容块，不再预览原始 JSON。
- Markdown 迁移至官方接替包 `flutter_markdown_plus`（已停更
  `flutter_markdown` 的 `replacedBy`），既有 `PreElementBuilder` 原样移植；
  围栏代码经由持续维护的 `syntax_highlight` TextMate 语法按主题高亮，未知语言
  与语法加载完成前回退为等宽纯文本。复制按钮、语言标签、链接消毒与可选文本
  不变。
- 文案归 `conversation` 命名空间字典（`tool.title.*`、`todo.*`、
  `message.think`），中英齐备。

## Alternatives considered

**解析 `<path>` 结果信封得到 write 行。** 放弃：信封是面向模型的文本而非契约；
React 读调用参数（`file_path`）与持久 `meta.diffs`。解析信封会把行绑定到输出措辞，
且在创建文件时失效。

**采用 `markdown_widget` 获得高亮。** 放弃：自 2025 年 4 月起无人维护，且拖入自有渲染器
与陈旧 `highlight 0.7.0`；所选组合保留当前渲染器（直接替换的 fork），仅用
2025 年维护的包增加 VSCode 风格主题高亮。

**整体采用 `gpt_markdown` 渲染器。** 放弃：它一次性替换渲染器、字体与数学栈，
等于视觉重做；本次变更保留 `MarkdownBody` 语义，仅在既有代码块内增加高亮 span。

**手写 Dart 高亮器。** 放弃：仓库要求优先使用持续维护的依赖而非手写；自建语法分支
只会增加无人维护的解析面，没有产品收益。

**透传旧 `HistoryEntry.view` 给行。** 放弃：客户端派生展示决策之后 wire 已不再发送它；
行读 `meta`，旧字段仅保留解码兼容。

## Consequences

工具行与 React 折叠行一致（`Write · <相对路径> +N −N`、`Bash · <description>`、
`Update to-do list · N/M completed · <item>`、`Think ·`），无原始信封文本，无绝对工作区前缀。
代码围栏在双主题下高亮受支持语法，其余回退纯文本。补齐了工作树缺失的
`retireOptimisticWithHistory` 视图助手（任意匹配退役），并把过时的
`sendMessage` 测试替身补上当前 `requestId` 形态。留给各 owner：
删除无引用的 `message_list.dart`、退役 `DsCodeBlock` 硬编码文案，以及对
`component.ui-tool.ToolCallTree`、`screen.ui-tool`、`route.conversation.chat.node`、
`screen.trajectory` 跟踪行按新渲染重新验证。

## Testing

- `test/unit/tool_presentation_test.dart`：23 个单元用例，覆盖行分类/摘要/相对化、
  diff 计数/意图/应用/回退、终端标记/后台/摘要、todo 计数、read 信封与元数据边界、
  wire 解码。
- `test/widgets/tool_row_test.dart`：4 个组件用例，证明折叠行显示相对路径加 `+2 −0`
  且无 `<path>` 文本、bash description、todo 计数行与失败行。
- `test/widgets/code_block_test.dart`、`test/widgets/conversation_test.dart`、
  `test/plugins/conversation_render_test.dart`、
  `test/plugins/ws_chat/tool_plugin_test.dart`（已更新为 ProviderScope 加本地化标题）与
  `test/conversation/chat_ui_adapter_test.dart`：80 项通过。
  `test/widgets/migrated_integration_test.dart` 仍因未动的在途
  `directory_browser.dart` 中 `ResponsiveBreakpoints.responsiveValue` 编译失败。
