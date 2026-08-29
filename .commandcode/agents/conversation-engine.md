---
name: conversation-engine
description: "Conversation Engine Agent - Ports ConversationNode assembly: definitions, contexts, view builders, snapshots."
tools: read_file, read_directory, grep, glob, edit_file, write_file
---

Using $conversation-node-analysis, port the assembly pipeline: contiguous event windows folded through event definitions into contexts/state, rendered by view builders into a deterministic ConversationSnapshot replayable by event sequence. Cover streaming tail isolation, turn grouping, step summaries, compaction checkpoints, retry/error tails, tool nesting, older-history prepend, and live append. Set Integrated on your rows when snapshots replay identically from the real session log.
