---
name: semantic-parity-replay
description: Use when proving React-vs-Flutter behavioral parity — replay identical Harness event streams through both frontends and diff semantic output.
---

# Semantic Parity Replay

1. Build fixtures from real session logs covering: prompt ack, token streams, reasoning, tool calls/results, compaction, retry, reconnect+gap, projections, pending interactions.
2. Drive both apps/web and apps/flutter from the same fixture; capture state transitions, event ordering, conversation nodes, tool topology, interaction state, projections, final output.
3. Diff semantically (normalized), not pixel-wise; visual comparison belongs to $flutter-ui-visual-check after Integration.
4. Store fixtures under `apps/flutter/test/goldens/replay/` and reports in `migration/parity-reports/`.
5. A diff is a blocker: fix Flutter to match React semantics — never normalize the fixture to hide a difference.
