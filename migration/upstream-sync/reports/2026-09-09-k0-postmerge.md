# K0 Post-Merge Contract Re-analysis — 2026-09-09

> OLD: `d347e70` (origin/master) · NEW: `5dda764` (merged Host, HEAD == upstream/master, fast-forward, 0 conflicts)
> Flutter ref: `flutter-sync/2026-09-09-5dda764` @ `2b8b3d40` · Method: mechanical extractors + per-category `git show/diff` verification. No production code modified.

## 1. Mechanical regeneration (all 11 files)

| File | Result |
|---|---|
| api-contract-current/previous.json | 92 → 97 ops |
| api-diff.json | 5 additive P2 (`workspaceFiles/*` ×5), 0 breaking |
| stream-contract-current/previous.json, stream-diff.json | total 0 |
| react-contract.json | 1093 surfaces |
| flutter-contract.json | 374 files, 167 call sites, 70 endpoints |
| flutter-impact.json | P0 2 / P1 1 / P2 5 / P3 0 |
| parity.json | PASS 56 / MISSING 3 / INCOMPATIBLE 0 / UNKNOWN 10 |
| change-registry.json | 669 entries |

## 2. Extractor trust verdict: DO NOT TRUST for severity

- api-extractor is endpoint/method/arg-name level only. Blind to: SurfaceOp rename, prompt guard, control resourcing, gateway agentId, goals/get, SystemPromptUpdate, /api/file, messageFeedback rewrite.
- stream-extractor force-adds 7 phantom endpoints, reports heartbeat 30000 (actual 2000 at all revs). stream-diff 0 misses F1–F4.
- parity UNKNOWN 10: independently classified (8 → PASS-equivalent, 1 → INCOMPATIBLE P0 system/message, 1 → P3 dockkit; MISSING 3 = workspaceFiles/files-tab, StatsPills/sessionStats, text-preview).
- `verified-findings.json` (this dir) is authoritative over api-diff/stream-diff severities.

## 3. Verified findings (severity-corrected)

P0 (5): SurfaceOp startSeq/endSeq + strict assert; system/message node-0 + head guard; waterfall no-soft-next; connection 15s hard readiness deadline; workspaceFiles missing (blocks file UX).
P1 (6): prompt/updateQueue bad-request (API face); control inbox resourcing (convergence); goals/get + activation epochs; /api/file client (+security review); ProducedFiles→Sidebar + readCallLine; queue continuable + sending row.
P2 (4): ModelSelect anchoring; commands locale descriptions; sidebar files tab/preview; SystemPromptUpdate capability.
P3 (1): dockkit defer. UNKNOWN: 0.

## 4. Ownership correction (F8 reframed)

Flutter `remote/ws-ticket` + `needsReauth` is NOT stale: it targets the FORK's `packages/host/remote-access` package (tracked on flutter-sync, 22 src files: pairing-qr, operator-console, tls-listener, token-service…), which upstream 5dda764 does not have at all. Decision required: forward-port remote-access onto the Host sync branch, or rebase Flutter transport to upstream cookie+Origin. P0 for any flutter-sync rebase either way.

## 5. Fork-delta inventory (upstream 5dda764 .. flutter-sync @2b8b3d40)

- packages/: 1569 paths (66 added / 219 deleted / 1283 modified / 1 rename). The 219 deletions = the 457-commit upstream gap (expected). 66 adds = forward-port candidates: remote-access pkg, terminal-controller pkg, legacy StatsLine/DetailsPanel/ToolDetails (upstream DELETED these — keep-or-drop decision; Flutter may depend on old UI), mux-upgrade-auth + semantic-parity specs, webworker fs-ext.
- Modified Host files needing 3-way review at rebase: gateway index/types, remotes (client/index, remote-events), session-controller (transport, commands, types, agent), workspace-controller, connection (browser-auth, api-request-trust, fixture).
- apps/flutter/: 747 files (entire implementation — untouched by Host sync by design).
- Other (1627): fork tooling (.agents/, migration/, scripts/, snapshots/) — stays on flutter-sync, never on sync branch.

## 6. Security-sensitive changes in window

- NEW: `/api/file` authed file route (containment, caps, fail-closed) — review fence parity before Flutter client.
- NEW: `workspaceFiles` read surface (2 MiB / 5000 lines / 2000 entries caps, symlink rejection).
- Gateway agentId strictness (waterfall rejection semantics).
- Fork-only remote-access (pairing QR, TLS listener, operator console, token service) — full security review before forward-port.

## 7. Test status (Phase H input)

Run 1 (full, sync branch == upstream): 1174 files / 21258 tests passed; 12 files / 26 tests failed (incl. spill-local boundary timing, typert tools-catalog 30s timeout). HEAD == upstream/master ⇒ failures cannot be merge-caused; resharded resumable re-run in progress for per-file classification.

## 8. Migration plan (STOP — no implementation in K0)

- K1: Decide remote-access (forward-port vs transport rebase) + legacy UI keep-or-drop (StatsLine/DetailsPanel/ToolDetails). Blocks all Flutter work.
- K2: P0 Flutter parity on flutter-sync branch (SurfaceOp, system/message, strict assert, waterfall must-answer, recovery constants) — one feature at a time, P0 first.
- K3: P1 batch (prompt guard, goals activation, workspaceFiles client, /api/file client, ProducedFiles routing, queue continuable).
- K4: `flutter analyze` + focused P0/P1 tests + full suite; parity.json Verified gate (all UNKNOWN already classified).
- K5: Rebase strategy for flutter-sync onto sync branch: 3-way review of modified Host files; never blanket dot→slash; never synthetic cursors; no version bumps.
- Placement: this dir holds the 11 regenerated JSONs + verified-findings.json + fork-delta-*.txt + upstream-state.json. Copy `*.json` → `migration/upstream-sync/` on `flutter-sync/2026-09-09-5dda764` (never on the sync branch), dated report → `migration/upstream-sync/reports/`.
