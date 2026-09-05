# Agent Note: Flutter 回放轨迹请求、子工具与时间线细节

Status: implemented

[English](2026-09-05-flutter-trajectory-requests-subtools.md) | 中文

## Problem

列表/检查器笔记遗留四项 React 行为未补：按请求的检查（每个请求的选项/用量/计时）、嵌套 `code-dispatch` 子工具行、时间线 TTFT 分段渲染与富提示、折叠回合直方图摘要。折叠行仍对所有回合硬编码 `1 step · N tool calls`，时间线提示只有 `kind · ok|error`，header 行没有请求累积。

## Decision

四项都从同一历史折叠派生，逐项对齐 React 源码。

- 子工具（`trajectory-tool-definition.ts` 边规则）：`tool/code-dispatch-start` 与 `tool/code-dispatch`（`{parentCallId, subCallId, name, arguments, content?, isError?}`）折叠为父行之后的 `subtool` 行，含参数、合并结果预览、错误标记与调用→结果时长。边守卫对齐 `acceptsEdge`（不自指、首个父胜出、拒绝祖先环、256 深度上限）；无父行的孤立边按 React 不可达根即丢弃。
- 请求（`TrajectoryView.tsx` 编号、`REQUEST_TABS`）：按 `request/header` 顺序全局编号；每个 header 行累积其区间工具/子工具数、输入/输出/缓存用量、错误/进行状态与墙钟跨度，检查标签为 Summary（状态、请求编号、服务商、模型、计数、提示词预览跳转）、Options（配置 JSON）、Usage（输入/缓存/输出）、Timing（请求墙钟跨度）。
- 时间线（`timeline.ts`、`TrajectoryTimeline.tsx` 提示）：span 携带记录开始、时长与校验过的 TTFT/解码细节；助手 span 以实色渲染 TTFT 段、半透明渲染解码余段；提示按本地模板为 `KIND / 开始 → 结束 / Total ms · TTFT ms · Decoding ms`。
- 折叠回合（`layout.ts groupDescription`）：行开始时间墙钟跨度（工具贡献开始加自身时长）加按首见顺序的工具直方图（`bash×6`），无时间时回退计数。
- 助手行现打步骤开始→消息墙钟（React `durationSeconds`），计时 Total 与时间线 span 覆盖步骤；用户/上下文行按 `inputCellDetail` 打零时长。

## Alternatives considered

**孤立子工具渲染为顶层工具。** 不可行：React 不渲染根不可达的子节点；虚构父级等于伪造日志没有的层级。

**按回合而非 header 顺序编号请求。** 不可行：React 按请求开始全局编号；回合与请求是独立分桶（一回合可跨多个请求）。

**等宽模式也显示 TTFT 分段。** 不可行：等宽模式设计上无墙钟；分段需要记录跨度，仅在计时模式渲染。

## Consequences

报障会话折叠为一个请求（`#1`、opencode、40 工具、62K/25K token、墙钟跨度），子工具为零（本地尚无 dispatch 事件；合成测试覆盖结构）。本地暂无 `code-dispatch` 流量，子工具渲染有契约覆盖、无真实验证。

## Testing

- `trajectory_ledger_parity_test.dart`：新增 5 例（dispatch 合并、孤立丢弃、环丢弃、请求编号加累积用量、TTFT span 细节）——17 项通过。
- 轨迹全集（`trajectory_ledger_test`、`trajectory_plugin_test`、`trajectory_fold_test`）：48 项通过。
- 会话 `00b22885` 真实日志探针（已删）：请求统计与零 TTFT 缺席符合预期。
- 两个轨迹库文件 `flutter analyze`：0 错误 0 警告。
