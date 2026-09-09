# Agent Note: Remote TLS listener, bearer enforcement, and operator console

Status: implemented

English | [中文](2026-09-06-remote-transport-auth-console.zh.md)

## Problem

The pairing contract shipped without a transport: the webserver was plaintext-only, so no `https://` endpoint existed for the QR/manual URL to point at, and the bearer/token/ticket machinery had no enforcement point — `authenticateRequest`, `isRemoteAuthorized`, and WS ticket validation were referenced nowhere outside their own tests. LAN clients were fail-closed (the browser fence 401s cookie-less callers), but there was no path to ever admit them. Operator approval was equally stuck: the pair log line referenced a `dsh remote approve` command that never existed, and the approval store is in-process memory no second process can reach.

## Decision

Remote access is now end-to-end on the host. `WebServer.listenTls` serves the composed routes over HTTPS with the host identity certificate; the `remote-tls-listener` plugin binds it on the LAN interface (`0.0.0.0:3443` by config) when `--remote` is enabled and stays dormant otherwise, leaving plaintext loopback untouched. The connection `/api` route and the gateway `/api/remote.mux` upgrade consult the foundation on fence rejection: public bootstrap proceeds, bearer `full` proceeds inside its verified ALS context subject to the privileged policy, single-use tickets admit mux upgrades, and everything else keeps the fence rejection. The `remote-operator-console` plugin gives the running process a TTY-only stdin console (`qr`, `approve`/`deny` by exact or unambiguous-prefix nonce, `pending`, `devices`, `help`) plus the boot-time QR display; non-TTY hosts stay dormant. Flutter pins the host certificate natively (`certFp` in QR and `tlsFingerprint` in `describe` feed the HTTP and WebSocket callbacks) and documents the one-time browser trust step on web.

## Enforcement design

The fence stays the single front gate and bearer logic never weakens it: browsers with cookies never reach the fallback, loopback without a cookie behaves exactly as before, and the privileged policy (`credentials.*`, `host.*`, `settings.*`, `agentPreset.*`) denies bearer callers while the wire accepts endpoints in slash or dot form. Fixing enforcement activated a latent policy bug — the dot-form vocabulary never matched slash-form wire endpoints, so privileged methods would have classified safe — now covered by slash-form pins. A live `dsh web --remote` smoke run then caught a second latent bug: Flutter sent `remote.pair` (and `remote.revoke`) args flat, but single-argument Typert methods take `args.request` — pairing could never have succeeded against a real host. Both call sites now wrap in `request`, pinned by wire-shape tests. The mux ticket check reuses `WsTicketStore.validate`, preserving single-use and audit. A `RemoteMuxClient.close` iteration race (socket loss clearing the stream table mid-close) crashed disconnect-while-stopping; closing over a snapshot fixed it, verified 6/6 on the previously 75%-flaky reconnect test.

## Alternatives considered

- **Second-process `dsh remote approve` CLI** — rejected: the approval store is process memory, and reaching it from another process needs an authenticated loopback management channel plus launcher-subcommand machinery; the stdin console answers approval, re-issue, and inspection in one place with no new trust surface.
- **TLS on the main port (protocol sniffing) or HTTPS-everywhere** — rejected: sniffing adds a security-sensitive multiplexer, and forcing HTTPS on loopback breaks local tooling, supervisors, and the Flutter `LocalTarget` path; a second listener keeps both postures intact.
- **PINs on by default** — rejected: the unguessable nonce plus explicit host approval already bind the ceremony, so a default PIN buys no security and taxes manual entry; operators opt in per ceremony policy.

## Consequences

- `dsh web --remote` prints a scannable QR plus manual values at boot and re-issues on `qr`; ceremonies still expire in 5 minutes and pairing still needs operator approval within the 30s pair window.
- The host certificate carries only loopback SANs, so browsers show a name-mismatch warning on LAN IPs until a SAN-complete rotation lands; native clients pin by fingerprint and are unaffected, and web needs the one-time manual trust already documented on the manual-entry screen.
- Deferred: LAN SANs in the host certificate, a `remote.issue` endpoint for dashboard-driven re-issue, device proof-of-possession, LAN discovery, and the React dashboard card (React stays read-only without explicit sign-off).

## Verification

- `packages/host/webserver/tests/tls-listener.spec.ts` (3): Loader composition serves routes over HTTPS with production cert material, rejects bad PEM loudly, double-bind fails; existing 4 pass unchanged.
- `packages/host/remote-access/tests/remote-boot.spec.ts` (3): Loader composition with TLS enabled serves HTTPS and reports `tlsPort`/fingerprint/`configSnapshot`; disabled stays loopback-only with no listener; full pairing lifecycle (ceremony, approval, token mint, device record, token verify) through the booted services.
- Live smoke: real `dsh web --remote` serves `remote.describe` over TLS with fingerprint, answers 401 to bearer-less `session/list`, and routes `remote.pair` into pairing validation (this run caught the flat-args bug above).
- `packages/host/remote-access/tests/remote-authorize.spec.ts` (13): tri-states for unary (bootstrap, missing/malformed/unknown/revoked/expired bearer, privileged 403, ws-ticket 403, ALS propagation) and mux (missing/bad/replayed ticket, wrong-scope 403), plus slash-form policy pins.
- `packages/host/remote-access/tests/operator-console.spec.ts` (18): every command, prefix resolution, dormant modes, Loader settle and boot-failure paths, `apply` variants; `pairing-qr.ts` keeps 100% across the board.
- `packages/api/gateway/tests/mux-upgrade-auth.host.spec.ts` (5): fence preserved without a foundation, decline/forbidden mapping, real-TCP 101 on proceed, 401 on checker failure.
- `packages/client/connection/tests/node-half.host.spec.ts` (+4): proceed runs dispatch with the mapped endpoint, forbidden skips dispatch, decline keeps 401, malformed paths never consult the foundation.
- Flutter: `tls_pinning_test.dart` (4) pins match/mismatch/malformed vectors; `qr_payload_test.dart` (+2) and `connection_client_remote_describe_test.dart` (+1) cover `certFp`/`tlsFingerprint`; `connection_client_remote_pair_test.dart` (2) pins the `args.request` pair shape; `test:gui` 4201 pass with only the pre-existing SameSite failure.
- `build:lib:host` and `typecheck:contracts-ready` pass; new/edited host files are oxlint-clean and `verify-export-jsdoc` reports nothing new.
