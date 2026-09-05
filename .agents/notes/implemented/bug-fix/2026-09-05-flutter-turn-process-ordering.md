# Agent Note: Flutter turn-process grouping and assistant ordering match React

Status: implemented

English | [中文](2026-09-05-flutter-turn-process-ordering.zh.md)

## Problem

Flutter chat rendered every step's tool cards inline with no turn grouping, so a 13-step turn printed 13 tool cards between the user bubble and the final answer while React collapses them behind one `N tool calls · M message(s)` disclosure. The group label used Flutter-invented copy (`reply`/`replies`, the counts title replaced by a generic word) instead of React `TurnProcessNodeView` strings, open state lived inside the row widget so the list could not suppress member rows, and rows used per-row widths instead of React's 748px content column. Separately, settled `assistant/message` nodes carried no sequence in `sourceSeqs` on durable replay (no live chunks exist to cite), so the anchor sort keyed them at `1<<30` and a turn-1 reply rendered after the turn-2 bubble (session `ed87108e`); turn footers keyed at `min(sourceSeqs)` (turn-start provenance) sorted ahead of the user bubble they close.

## Decision

Flutter owns the same turn presentation React owns: grouping, labels, order, and column width derive from the same event evidence.

- `ToolNode.turn` records the owning turn at fold time (event coordinates, else the folder cursor; null stays ungrouped and never suppresses).
- `turnProcessOpenProvider` (`$sessionId:$turn`) lifts group open state out of `_TurnProcessRow` so `ChatView` suppresses a collapsed settled turn's member `ToolNode` rows; live (tail-less) turns keep streaming rows openly. The row shows React's exact counts label through locale-owned `formatTurnProcessLabel` and renders no inline child (members render in place when expanded).
- `stableChatOrder`/`chatNodeOrderKey`/`hideGroupedTool` mirror `orderedVisibleChatNodes`: system rows sort by `requestPromptAnchor` (step-1 requests anchor at turn start via `_turnStartSeq`/`_stepStartSeq`), footers sort by latest seq (emission position), every other node by earliest seq.
- Settled assistants with visible text or reasoning append their durable seq to `sourceSeqs`; empty usage-host messages stay seq-less (zero-height, non-surface, excluded from compaction shadow citation).
- Chat rows and `TodoPanel` share one centered 748px cap (`--dsh-chat-content-width`).

## Alternatives considered

**Keep per-row open state and hide tools inside the row.** Lost: the row cannot own cards rendered by the list; React's disclosure owns its tool cards at list level, and member rows must leave layout, not just paint.

**Sort every node by minimum seq.** Lost: footer provenance includes turn start, which predates the user bubble; footers mark emission position, so maximum seq is the correct key.

**Always append the durable seq, including empty messages.** Lost: empty assistants are not surface events (`deriveEventMessage` returns null for them); citing them in compaction shadow sets over-claims the replaced range and broke the shadow-price unit test.

**Reorder in the folder instead of the view.** Lost: the folder is the event-order source of truth; presentation anchoring is a view concern in React (`orderedVisibleChatNodes`), and folder order stays the stable tiebreak.

## Consequences

Settled turns collapse to one disclosure with React's exact label (`3 tool calls · 1 message`, singular forms, subagent segment, `Thought for a while` fallback) in English and Chinese; expanding reveals the member tool cards in place. Turn-1 replies sort before the turn-2 bubble on durable replay, verified against the reporting session's real log. System rows anchor ahead of their user bubble per `requestPromptAnchor`. Empty assistants remain invisible and seq-less, preserving the compaction shadow contract.

## Testing

- `test/plugins/conversation_nodes_test.dart` + `test/plugins/conversation_turn_process_test.dart`: 32 green, covering anchor order, tool turn attribution, label formats, collapse/expand suppression, and the settlement-seq citation update (`[3, 4, 5]`).
- Real-log repro (session `ed87108e`, since removed): `a-turn1-step1` and `a-turn1-step14` sort before `u88`, `u88` before `a-turn2-step1`.
- `flutter analyze` on both touched library files: 0 errors.
