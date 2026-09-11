# Upstream Final Verification — 2026-09-09

> Upstream: `5dda764ed3` (release 0.1.5-alpha.1) · Previous: `d347e703` (0.1.3-alpha.1)
> Merge base (origin/master..upstream): `d347e703` · Commits synchronized: 879
> Branch: `flutter-sync/2026-09-09-5dda764` @ `2b8b3d40` (+ staged K1–K5 work)
> Host sync branch: `sync/upstream/2026-09-09-5dda764` == upstream (fast-forward, 0 conflicts)

## API changes (92 → 97 ops, 0 breaking)

5 additive P2: `workspaceFiles/changes|list|read|readBytes|stat` — all consumed
by the new `WorkspaceFilesClient` (K4). Semantic changes invisible to the
endpoint extractor are authoritative in `verified-findings.json` (K0):
SurfaceOp rename, system/message, waterfall agentId, recovery config,
prompt guards, control resourcing, goals/get, /api/file, SystemPromptUpdate,
messageFeedback rewrite.

## Stream changes

Mechanical `stream-diff`: total 0 (extractor misses path-stable frame
changes — documented). Authoritative findings F1–F8 (verified-findings.json):
waterfall no-soft-next, 15s readiness deadline, inbox-projection control
sourcing, strict wire assert — all addressed in K2/K3.

## React changes (window themes)

session-log-v3 canonical envelopes, visualizer add-then-revert, explicit
agent context, Codex/Claude runtime upgrades, native node-addon-system
rename, StatsPills, system-prompt-in-history, workspaceFiles dual-face
package, dockkit/right-sidebar, local-media, file-through-filesystem.

## Flutter changes (K1–K5, no Host edits)

- K1: v3 wire decode (startSeq/endSeq, system/message, strict assert,
  opaque passthrough, metadata threading, loud drops) + 17 tests.
- K2: recovery parity (warn+deadline, socket hygiene, pump-failure fast
  fail, stale-waterfall guard, attempt resets, completer/cancel fixes).
- K3: mux/$events contract (ready enforcement, id validation, cancel set,
  `next` delegation, approvalId=eventId) + 10 tests; retired 2 harness tests.
- K4: WorkspaceFilesClient, media client, file preview, prose images + tests.
- K5: stats pills (projections first), inspector + update flag, trajectory
  systemPrompts, queueMutable, prompt/updateQueue guards, goal activation,
  readCallLine + preview line.

## P0 results — all PASS

SurfaceOp, system/message head, strict assert, waterfall semantics, 15s
deadline, workspaceFiles, ready/clientId/eventId/agentId binding, cancel→
resolved matching, approval/question round-trips, mux cancel delivery.
No unexplained P0.

## P1 results — all PASS or documented

stats pills, prompt guards, inbox resourcing, goals/get+activation, /api/file,
ProducedFiles routing, queue continuable, inspector, control snapshots.
`remote-mux-ticket`: fork-owned (targets the fork remote-access package,
absent upstream by design) — preserved and tested.

## P2 results — all PASS

ModelSelect anchoring (deferred visual), commands locale descriptions,
sidebar files tab (deferred: no dock host), SystemPromptUpdate capability,
workspaceFiles advisory entries (consumed).

## UNKNOWN classification — 11/11 closed

MISSING 3: all NOT APPLICABLE (Cordis event name, e2e scaffold handler,
fabricated error code — file:line proof in verified-parity.json).
flutter-only 8: 6 PASS with evidence, 2 fork-owned documented.
Tooling impact P0s (page-cursor, settings-list): PASS with tests.

## Host test results

- `pnpm build`: **FAIL (PRODUCT, fork-owned)** — `remote-access/
  operator-console.ts` imports `qrcode`, absent from its deps and lockfile
  (only a docs-site optional peer pulls it). Fork package never declared it.
- `pnpm typecheck` / `lint`: same single root cause (tsc -b host blocks both).
- Direct gates: `tsc -b tsconfig.client.json` FAIL on 2 pre-existing fork
  contract drifts (`ui-workspace/navigation.ts` arity, `directory-picker`
  `readFile` namespace); `oxlint`: 186 errors, 0 in apps/flutter or
  migration/**.
- `pnpm test`: 19055 passed / 29 failed (1117/16 files). Fork-owned:
  qrcode import, remote-access README skeleton (×4), cordis-catalog type
  links (×2), tools-catalog timeout, transform-corpus baseline (9 missing
  built deps incl. mime-types, node-addon-system), semantic-parity mount
  (sessions service missing). Pre-existing/environmental: HMR timing,
  browser-auth cookie regex, code-block grammar timeout, worker OOM/timeouts,
  python timeout, spill boundary, oxlint-contract timeout.

## Flutter test results

Full suite failing-file set identical to K3 and pristine-HEAD baseline
(27/27/28) — zero regressions from K1–K5 across focused runs
(session 72/72, pills 5/5, inspector 7/7, trajectory 3/3, queue 8/8,
recovery 6/6, mux events 10/10, files 9/9, preview 3/3, activation 7/7).

## Analyzer / builds / tracker / parity

- `flutter analyze`: 0 errors project-wide (K1–K5 files clean).
- Web (wasm release): PASS. macOS (debug): PASS.
- Android (debug): BLOCKED-ENVIRONMENT — `irondash_engine_context`
  cargokit `exec()` Gradle incompatibility (third-party native plugin vs
  installed Gradle; no project code involved).
- `verify-flutter-tracker`: OK (112 items).
- Parity: PASS 56, MISSING 3 (not-applicable), UNKNOWN 11 (closed),
  INCOMPATIBLE 0. Registry 669 (mechanical; severity authority in
  verified-findings.json + verified-parity.json).

## Remaining limitations

1. Fork `remote-access` package is unbuildable as committed (missing
   `qrcode` dep + README skeleton + catalog type links) — blocks `pnpm
   build/typecheck/lint/test` green until declared or vendored.
2. transform-corpus baseline failures need rebuilt `lib/` (build blocked
   by (1)) and native prebuilds.
3. Android build needs the Gradle/cargokit toolchain fix (environment).
4. Forward-port decision open: fork remote-access vs transport rebase (K1).
5. `connection_generation_test` retired-transport leftovers partially
   cleaned; tracker statuses still reflect pre-K1 work.
