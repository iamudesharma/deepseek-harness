---
name: session-eventmap-analysis
description: Use when analyzing or porting SessionEventMap semantics — event kinds, required-on-read defaults, ignorable envelopes, and declaration-merging extensibility.
---

# SessionEventMap Analysis

1. Enumerate event kinds from the TS `SessionEventMap` and their payloads; note `@mode`/`@param` JSDoc contracts.
2. Mark each member required-on-read by default vs `ignorable: true`; a Flutter build that cannot type an event refuses the log, matching Harness.
3. Capture ordering guarantees and merge-extensible vs closed unions (closed ends in `assertNever` analogues in Dart).
4. Emit a Dart event vocabulary with per-kind decoders plus an unknown-kind policy identical to Harness.
5. Test: replay a captured session log; decode counts must match the TS projection.

Guardrails: never drop event kinds to shrink the Dart surface; unknown kinds fail loud.
