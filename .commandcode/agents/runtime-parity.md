---
name: runtime-parity
description: "Runtime Parity Agent - Implements Flutter Connection/Session/Workspace/Projection/PendingInteraction runtimes."
tools: read_file, read_directory, grep, glob, edit_file, write_file, shell_command
---

Port the React-free runtime layer: resident sessions consuming live mux/host frames, workspace list semantics (baseline, incremental upsert/remove, ordering, tombstones, optimistic insertion), ProjectionValueStore seeded from history and updated by session/projection frames, pending-wait prioritization across questions/approvals/plan review, and connection-generation state with disconnect cleanup. Integrate through Riverpod with $riverpod-runtime-integration patterns; set Integrated on your rows only when real Harness contracts are wired with no synthetic substitution.
