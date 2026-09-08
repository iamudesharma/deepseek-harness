# Agent Note：Flutter 会话命令（`+`）菜单对齐

Status: implemented

[English](2026-09-08-flutter-plus-command-menu.md) | 中文

## Problem

React 会话 composer 有一个 `+` 按钮（`InputBar.tsx:465-478`），用于打开会话命令菜单——Host 目录（`compact`、`export`、`feedback`、`goal`、`permission`、`plan`）加上客户端自有的 `/model` 行，以“名称 + 描述”列表展示。Flutter composer 没有 `+` 入口：命令只能通过输入 `/` 触达。因此 Host 目录缺少可见入口，`/model` 完全没有菜单行（未注册任何客户端 contribution），`/export` 执行后也从不下载 Host 已准备好的 ZIP。

## Decision

- `InputTriggerController.toggleLauncherSource()` 对齐 React `toggleSource`：用合成 leading hit（空 query、以 live `draftRev` 打戳的折叠 caret span）只播种一个 source 的分组并拉取候选项。选中复用普通 source 回调与 sink 管道；下一次 `track()` 清除 launcher 并按 draft 重新检测，与 React 一致，因此启动后继续输入会回落到检测逻辑。未知 source 与再次 toggle 均为关闭。
- Composer 工具行首位新增 `+` 按钮（React 位置），tooltip 为 `input.commands`（`Commands`/`指令`），composer 不可用/发送中或 trigger 尚未激活时禁用。点击先聚焦输入框，再在 post-frame 中 toggle，以免 focus 引发的选区变化在同一帧清除刚打开的 launcher。打开菜单从不修改 draft。
- `/model` 注册为客户端 contribution，数据源是会话共享的 `ModelDirectory`（与 composer seat 同一 store）：options 由 groups 展平，失败行选中时报错，`onSelect` 经 `directory.select` 落定。描述在注册时从 `model` locale 快照，与 React 一致。同名 Host 行会在候选合成时碰撞并 loud 失败，永不遮蔽。
- `/export` 经 export-aware executor 包装实现下载：admitted 的裸 `/export` 会额外 GET `/api/session.export`（与其他 `/api/*` 调用相同的 cookie/bearer 防线，并剥离 `?token=`），经平台保存面板保存 ZIP（`FilePicker.saveFile`——桌面为原生保存框，移动端为保存/分享面板，Web 为下载）。带参行仍走 Host 用法错误路径；下载失败经 `onExportError` 上报（应用装配中接到 toast），不影响已 admitted 的命令结果；用户取消保存面板视为正常返回。
- `/compact`、`/feedback`、`/goal`、`/plan` 与带参 `/permission` 无需新代码：`+` 菜单列出实时 Host 目录，选中走既有 claim/detached 决策表与既有标准 RPC（`commands/execute`）。
- 裸 `/permission` 经 `command.decorate` 移植打开 picker：`CommandUiService` 新增 decorations 注册表，仅对可解析 Host 行的裸菜单选中/回车生效（带参行仍走 claim 路径）。Options 来自 `live_sync` 在每次 provider 写入时同步喂养的 `PermissionSnapshotCache` 镜像（projection 是 service 层够不到的 Riverpod 状态）；`danger-full-access` 行携带与 seat 相同的 `confirm.*` 风险确认，落定发送同一 `/permission <preset>` 行，Host 拒绝抛入 shell 错误条。

## Alternatives considered

**点击 `+` 时向 draft 插入 `/`。** 零 controller 改动即可复用检测，但用户关闭菜单未选中时 draft 会残留一个 `/`——React launcher 从不修改 draft。

**为 launcher 另建一套菜单模型。** 拒绝：两套模型需要在目录刷新、高亮同步与关闭时联合失效。用合成 hit 的 toggle 复用同一模型。

**按 subagent 会话隐藏 `/model`。** React 经 `subagentAddress` 对 continuable 子会话隐藏该行。Flutter composer seat 本就没有该门控，且 summaries 是 service 层够不到的 Riverpod 状态；只给菜单行加门控会让两个入口行为不一致。两入口共享同一 directory 与其错误，subagent 选中经同一 RPC 路径 loud 失败。

**从 settings scope 读 picker options。** scope 描述的是全局新会话默认值，不是会话值——是错误的数据源。实时 projection 镜像携带按会话的真相。

## Consequences

- `+` 菜单列出内容与输入 `/` 完全一致（Host 目录加 contributions），描述采用 Host 原文，不硬编码任何命令名。
- `ModelSelectionPlugin` 新增注入 `commandUi`，插件按 service 依赖顺序在 `ui-commands` 之后激活（与 cordis fiber 一致）。`PermissionPresetsPlugin` 为其 decoration 声明同样的边。
- `CommandsPlugin` 新增可选 `onExportError`；既有构造不受影响。
- 新增测试：launcher toggle 单元测试、`/model` contribution 测试、permission decoration 测试、export 服务/包装测试、`+` 按钮 widget 测试；既有 slash/contract 套件无改动通过。
