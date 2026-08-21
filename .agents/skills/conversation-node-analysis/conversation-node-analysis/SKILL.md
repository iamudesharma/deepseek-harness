---
name: conversation-node-analysis
description: Use when porting ConversationNode assembly — event windows folded through definitions into contexts/state, rendered by view builders into deterministic snapshots.
---

# ConversationNode Analysis

1. Inventory node definitions (assistant, reasoning, tool, compaction, retry/error, step groups) from the client architecture note and `ui-conversation`.
2. Port the pipeline: contiguous event window -> ConversationNodeDefinition\<T> fold -> ConversationContext\<T>/State\<T> -> ViewBuilder -> snapshot.
3. Guarantee deterministic replay by event sequence: same log prefix => same snapshot (reload, reconnect, prepend, append).
4. Isolate the streaming tail: the in-flight turn renders separately from settled nodes.
5. Test: golden snapshots for grouped turns, nested tools, compaction checkpoints, retry tails, and 10K+ event streams.

Guardrails: no giant kind-switch in Session; new behavior arrives as node definitions.
