---
name: tool-topology-analysis
description: Use when porting tool call lifecycle — runtime-owned callId pairing, recursive subCalls topology, and the split from presentation.
---

# Tool Topology Analysis

1. Runtime owns pairing: match calls to results by callId, maintain lifecycle (pending/partial/complete/failed/retried), project recursive subCalls trees.
2. Presentation consumes projected nodes only; renderers never pair or infer topology.
3. Handle out-of-order events (result before call, late results), partial argument streaming, and failure tails.
4. Port ToolPresentationRegistry keyed by tool kind with a generic fallback; tools register renderers, no central switch edits.
5. Test: A->B->C nesting, sibling D, out-of-order and retried events produce identical trees in React and Flutter replays.
