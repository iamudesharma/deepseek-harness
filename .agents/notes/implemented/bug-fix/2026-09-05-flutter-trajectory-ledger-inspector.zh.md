# Agent Note: Flutter 回放轨迹列表与检查器与 React 一致

Status: implemented

[English](2026-09-05-flutter-trajectory-ledger-inspector.md) | 中文

## Problem

Flutter 回放轨迹把原始历史直接折叠成列表行，而不是 React 的精选投影：每个工具出现两次（调用行加结果行），控制面噪声（`permission/preset`、`sandbox/mode`、`approval/policy`、收件箱拼接、`session/title`）渲染成 React 从不显示的 `SYSTEM` 行，每个 `assistant/chunk` 增量各占一行，无文本助手显示 `—` 而不是 `(tool call only)`，工具行携带 Flutter 自创的分工具语义摘要，而不是 React 的原文 `name args → result-preview`。检查器同样单薄：工具固定 `Overview/Input/Output/Timing` 四个标签，没有 `Schema` 标签，没有条件 Payload/Result 标签，没有层级跳转，没有 token 行，计时只有裸 Started/Duration，新文案全部硬编码英文，没有本地化字典。

## Decision

Flutter 折叠产出与 React `layout.ts` 加 `TrajectoryTable.tsx` 相同的行模型，检查器遵循 React `detailTabs` 矩阵。

- 每个 `callId` 一张工具卡：调用行携带原文 `args`（2048→512 预览上限），结果合并为 `outputDetail`，另以 `resultPreview` 内联展示；错误展示 `error.code`；未配对调用保持 `running` 且时长为空；孤立结果独立成行。`request/header` 只产出系统行（`Initial System Prompt` / `System Prompt Updated`），并从 header 目录为每个工具捕获架构（`description` + `parameters`）。
- Chunk 增量按步骤累积，仅对无落盘消息的步骤输出一行尾行；已终结步骤丢弃其 chunk。仅驱动工具调用的无文本助手（消息块或同步骤调用二者有其一）标记 `(tool call only)`。
- 列表文本执行 `trajectoryPreviewText` 移植（2048 源上限、markdown 转纯文本、单行、512 上限且仅在截断时加 `…`）；全文保留在预览/详情字段。搜索索引与 React 相同语料（参数、结果、思考、架构、callId、来源），多词 AND。
- 检查器按类型切换标签：工具为 Summary（状态、助手消息层级跳转、参数/结果/架构/计时预览段）加条件 Payload/Result 加常驻 Schema（目录描述与参数树，无则 `Schema unavailable`）与 Timing（本地/Unix 开始时间切换、千分位毫秒时长、会话时间戳来源、有 chunk 时间与用量时给出助手 TTFT/生成/吞吐）；消息给出 token 行；用户可跳来源标签；系统行给出系统提示词与目录工具标签。标题为类型徽标加 `Turn N · Step M`。
- 全部新文案归入 `trajectory` 本地化字典（`locales.dart`，中英），含重命名后的标签（Summary/Preview/Raw/Source/Payload/Result/Schema/Timing）。

## Alternatives considered

**保留轨迹行的分工具语义摘要。** 不可行：React 轨迹显示原文参数；语义摘要属于聊天工具卡，两个界面在每个非平凡行都不一致。

**每个 chunk 增量保留一行。** 不可行：React 从不对 chunk 成行；增量原位更新未终结单元，重放历史会喷出数十个碎片行。

**空 usage 宿主助手参与排序/影子引用。** 不可行：回合处理笔记已决；可见内容才拥有序列成员资格，compaction 影子集合才能保持精确。

**同批移植请求检查器与子工具展开。** 不可行：请求编号/用量累积与 `code-dispatch` 子行需要历史折叠尚未具备的 provider 层输入；列表与检查器一致性独立先行。

## Consequences

报障会话的真实日志折叠为 78 个精选行（`USER hi`、`CONTEXT …`、`SYSTEM Initial System Prompt`、`TOOL bash {…} → ls 输出`、`(tool call only)` 助手、回合 2 审计流），架构描述从 header 目录解析。折叠回合摘要、时间线提示/TTFT 分段、请求检查、子工具行仍按计划延后，见新测试范围与既有 tracker 记录。

## Testing

- `trajectory_ledger_parity_test.dart`：12 项通过（工具合并、进行中调用、噪声丢弃、tool-call-only、chunk 累积/消失、header 提示词加架构、用量/来源保留、512 上限规则）。
- `trajectory_ledger_test.dart`（4 项期望更新为 React 行为）、`trajectory_plugin_test.dart`、`trajectory_fold_test.dart`：共 43 项通过。
- 会话 `00b22885` 真实日志折叠验证精选结构，用后即删。
- 两个触及/新增库文件 `flutter analyze`：0 错误（文件他处 6 个既有提示）。
