# Agent Note: Flutter 回合处理分组与助手排序与 React 一致

Status: implemented

[English](2026-09-05-flutter-turn-process-ordering.md) | 中文

## Problem

Flutter 聊天把每个步骤的工具卡片全部平铺，没有回合分组，因此一个 13 步的回合会在用户气泡与最终答复之间打印 13 张工具卡，而 React 把它们收纳到一个 `N tool calls · M message(s)` 折叠行之后。分组标签使用 Flutter 自创文案（`reply`/`replies`、计数标题被通用词取代），而不是 React `TurnProcessNodeView` 字符串；展开状态放在行组件内部，列表无法隐藏成员行；行宽各自为政，而不是 React 的 748px 内容列。另外，已落盘的 `assistant/message` 节点在持久回放时 `sourceSeqs` 为空（没有实时 chunk 可引用），锚点排序将其键记为 `1<<30`，导致回合 1 的答复渲染到回合 2 气泡之后（会话 `ed87108e`）；回合页脚以 `min(sourceSeqs)`（回合开始溯源）为键，排到了它所终结的用户气泡之前。

## Decision

Flutter 拥有与 React 相同的回合展示：分组、标签、顺序与列宽都从同一事件证据派生。

- `ToolNode.turn` 在折叠时记录所属回合（事件坐标优先，否则用 folder 游标；null 永不分组、永不隐藏）。
- `turnProcessOpenProvider`（`$sessionId:$turn`）把分组展开状态从 `_TurnProcessRow` 上提，`ChatView` 在折叠的已终结回合隐藏成员 `ToolNode` 行；实时（无尾）回合保持流式行可见。行经本地化的 `formatTurnProcessLabel` 显示与 React 完全一致的计数标签，不再渲染内联子内容（展开时成员卡片在列表原位渲染）。
- `stableChatOrder`/`chatNodeOrderKey`/`hideGroupedTool` 对齐 `orderedVisibleChatNodes`：系统行按 `requestPromptAnchor` 排序（首步请求经 `_turnStartSeq`/`_stepStartSeq` 锚定到回合开始），页脚按最大 seq（落点位置）排序，其余节点按最小 seq 排序。
- 携带可见文本或推理的已终结助手消息将其持久 seq 追加到 `sourceSeqs`；空的 usage 宿主消息保持无 seq（零高度、非 surface，不计入 compaction 影子引用）。
- 聊天行与 `TodoPanel` 共用一个居中 748px 上限（`--dsh-chat-content-width`）。

## Alternatives considered

**保留行内展开状态、在行内隐藏工具。** 不可行：行组件无法拥有列表渲染的卡片；React 的折叠行在列表层拥有其工具卡，成员行必须退出布局，而不仅是不绘制。

**所有节点按最小 seq 排序。** 不可行：页脚溯源包含回合开始，早于用户气泡；页脚标记的是落点位置，最大 seq 才是正确键。

**空消息也追加持久 seq。** 不可行：空助手消息不是 surface 事件（`deriveEventMessage` 对其返回 null）；在 compaction 影子集合中引用它们会夸大替换范围，并破坏了影子价格单测。

**在 folder 而不在视图排序。** 不可行：folder 是事件顺序的事实来源；展示锚点是 React 的视图职责（`orderedVisibleChatNodes`），folder 顺序保留为稳定决胜键。

## Consequences

已终结回合收纳为一个折叠行，标签与 React 完全一致（`3 tool calls · 1 message`、单复数、subagent 段、`Thought for a while` 兜底），中英文皆有；展开后成员工具卡在原位出现。持久回放时回合 1 答复排在回合 2 气泡之前，已用报障会话的真实日志验证。系统行按 `requestPromptAnchor` 排在其用户气泡之前。空助手消息保持不可见且无 seq，compaction 影子契约不受影响。

## Testing

- `test/plugins/conversation_nodes_test.dart` + `test/plugins/conversation_turn_process_test.dart`：32 项通过，覆盖锚点顺序、工具回合归属、标签格式、折叠/展开隐藏与终结 seq 引用更新（`[3, 4, 5]`）。
- 真实日志复现（会话 `ed87108e`，用后即删）：`a-turn1-step1` 与 `a-turn1-step14` 排在 `u88` 之前，`u88` 排在 `a-turn2-step1` 之前。
- 两个修改的库文件 `flutter analyze`：0 错误。
