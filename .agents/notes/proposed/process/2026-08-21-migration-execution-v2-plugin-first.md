# Agent Note: Migration execution v2 — plugin-first over the v1.1 ledger

Status: proposed

## Problem

Migration Mode v1.1 rebuilt the measurement system honestly and stopped there: all 112 tracker items sit at `Audited`, every `evidence` object is empty, `behavior` parity is `missing` on every item, and `--strict` cannot pass because no Verified path exists. The Flutter app grew meanwhile as a hardcoded widget tree — [main.dart](../../../apps/flutter/lib/main.dart) mounts a fixed router, features import each other directly, and none of the React composition model (slot registry with kinds/scopes/child authorization, service-DI activation, cascade disposal) exists on the Flutter side. A screen-by-screen translation can therefore look complete while the application cannot be assembled the way the React app is: `ui-conversation` alone has 18 packages contributing into its slots. Two concrete blockers also surfaced: legacy `flutterTarget` paths drift from the on-disk snake_case tree, and the 75 legacy parity reports predate the v1.1 gates so nothing can re-promote from prior artifacts alone.

## Proposal

Adopt [migration/plan.md](../../../migration/plan.md) as the execution plan under the unchanged v1.1 contract:

- The migration unit becomes the React plugin package ported layer-by-layer (contract → services/stores → slot registrations → UI → verification), not the component or screen.
- `apps/flutter` gains a Layer-0 host mirroring the React seams: slot registry (`single|list|keyed|chain`, `root|session-maybe|session`, children-as-authorization), a plugin contract (`apply(ctx)` + declared service injections activated by service-wait), a renderer seam, and platform service adapters behind conditional imports.
- Phases run dependency-driven from the audited adjacency list; business plugins port in parallel workstreams that own disjoint `reactPackage` prefixes after their dependencies reach `Integrated`.
- Platform scope stays Web + macOS; Windows/Linux get only the adapter seam, not parity claims.

The tracker stays the single ledger extended in place, per the recorded v1.1 rejection of a fresh tracker file; lifecycle states, write authority, parity enums, synthetic-fallback policy, and Gatekeeper authority are untouched.

## Alternatives considered

**A fresh "Migration v2" tracker schema/file grouping items into plugin manifests.** Rejected: the v1.1 rework explicitly rejected a second ledger because two files invite drift, and the existing fields already express the layers a manifest would add (`reactPackage` groups per package; `runtime|protocol|slot` categories carry non-UI responsibilities). Adding fields would also require extending `verify-flutter-tracker.ts` for no enforcement gain.

**Continue screen-by-screen translation without a host.** Rejected: it reproduces the failure mode this replan exists to fix — every visible screen present while streaming, reconnect, tool topology, and slot extensibility stay unproven or unexpressible; the hub-and-spoke dependency shape (`ui-conversation` gating 18 packages) is invisible to screen-order work.

**A new agent framework for plugin migration.** Rejected for the same reason v1.1 rejected rebuilding agents (~60% overlap recreates a duplicate framework): the 18-agent roster plus domain skills already cover contract extraction, runtime parity, slots, conversation assembly, replay, and gatekeeping; workstreams assign existing agents disjoint prefixes instead.

## Acceptance criteria

- `migration/plan.md` exists as the P0/P1/P2 DAG, respects `dependsOn` edges, and records blockers (path drift, hub serialization).
- After the first actions, `pnpm run verify-flutter-tracker --check` passes with reconciled Layer-0 targets; drifted paths are corrected per-plugin at `Audited → In Progress`.
- P0 exits with a headless Flutter harness that activates the host, folds a recorded session stream, and prints a stable transcript snapshot — no status claims beyond what stage agents legitimately write.
- No item advances status outside the v1.1 write-authority partition; completion claims additionally pass `--strict`.

## Risks

`flutter_gen_ai_chat_ui` may not fit inside the conversation plugin's slot registrations; WS-Chat decides confine-or-replace at `In Progress` and records it on the affected rows. Hub serialization makes P1 throughput depend on early `ui-conversation` completion. Deferring Windows/Linux invites scope pressure; the adapter seam contains it but does not verify it.
