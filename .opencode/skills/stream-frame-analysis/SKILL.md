---
name: stream-frame-analysis
description: Use when porting mux/host frame handling — connection generations, readiness, reconnect, backoff, gap recovery, and resync semantics.
---

# Stream Frame Analysis

1. Map the mux and host frame vocabularies from `packages/client/connection` and the SDK transport.
2. Model ConnectionGeneration: frames are generation-scoped; disconnect clears generation-bound state; `hostDescription` exists only after readiness.
3. Specify reconnect: attempt/backoff, resync, history/projection replay, higher-seq-wins for projections.
4. Define the Flutter pump: persistent per-session streams feeding Session -> assembler -> Riverpod; HTTP request completion is NOT delivery.
5. Test: forced-disconnect mid-stream recovers without refresh; no duplicate or lost frames across resync.

Acceptance scenario: send prompt -> user message immediate -> streamed tokens/reasoning/tools -> final response with NO refresh, reload, or polling.
