---
name: harness-api-contract-extraction
description: Use when Flutter needs a Harness API/RPC contract — extract it mechanically from the TypeScript definitions/RPC gateway into Dart; hand-invented or simplified contracts are forbidden.
---

# Harness API Contract Extraction

1. Locate the authoritative TS definition (RPC gateway, Service Definition, or wire type) for the surface.
2. Transcribe request/response fields, unions (discriminant tags), error modes, and versioning into Dart types; closed unions end in exhaustive switches.
3. Preserve opaque branded ids as wrapped classes, never bare `String`.
4. Generate/refresh a fixture round-trip test proving the Dart model parses a real captured payload.
5. Record the TS source path in the tracker row's `source`/notes.

Guardrails: never widen/narrow optionality to fit Dart ergonomics; never rename wire fields; if the TS contract is ambiguous, stop and flag the Protocol/Event Agent instead of guessing.
