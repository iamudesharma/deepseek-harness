# Agent Note: Remote pairing QR issuance and unauthenticated host describe

Status: implemented

English | [中文](2026-09-06-remote-pairing-qr-describe.zh.md)

## Problem

Flutter remote pairing had a QR consumer with no host producer: `AddComputerScreen` tells the user to run `dsh web --remote` and scan a QR, but no host code minted the ceremony or rendered the `dsh://pair` payload, so the only working path was hand-copying `hostId`/`nonce`/`PIN` from wherever the operator could find them. Manual entry compounded the gap by sending `hostPublicKey: 'placeholder'`, which skipped the host-pinning guarantee the QR path enforces and re-validates after `remote.pair`.

## Decision

The host owns QR issuance in `packages/host/remote-access/src/pairing-qr.ts`: `issuePairingQr` mints the `PairingStore` entry (nonce, optional PIN, TTL) and returns the validated payload with its `dsh://pair?data=base64url(json)` URI, JSON form, and expiry; `encodePairingQrPayload`/`decodePairingQrPayload` share the field validation the Flutter `QrPayload` enforces, and the module is exported from the package index. A new unauthenticated `remote.describe` endpoint returns only the public host identity (`hostId`, `hostPublicKey`) so manual URL entry pins the host before pairing; the auth middleware treats it like `remote.pair` (public, no bearer). On Flutter, `ManualEntryScreen` fetches `remote.describe` into the host-ID and public-key fields before the nonce/PIN step (no placeholder key reaches the wire), `ConnectionClient.remoteDescribe` is the typed face, `QrPayload.toQrUri` mirrors the host encoder, and pairing mints one random 32-byte device key per attempt with a platform-labelled display name.

## Host QR wire

The payload is `{baseUri, hostId, hostPublicKey, nonce, pin?, exp, displayName?}` with the same patterns both sides enforce (43-char base64url `hostId`, UUID `nonce`, 6-digit `pin`, integer `exp` checked against the clock at decode). `issuePairingQr` takes the live `PairingStore` plus base URI, host identity, and ceremony options (`withPin`, `ttlMs` default 5 minutes, `displayName`, `now`/generator seams for tests); expiry is `now + ttlMs`, not the store entry's clock, so the two stay consistent by construction.

## Alternatives considered

- **Host renders the QR image itself (terminal ascii / web dashboard card)** — rejected for this change: image rendering is presentation, while the missing piece was the ceremony-to-payload contract both sides share; the URI/JSON forms unblock CLI, dashboard, and Flutter work independently, and rendering follows without contract risk.
- **Reuse `host.describe` for manual identity fetch** — rejected: that endpoint is retired on the host (the Flutter controller treats it as opportunistic and proceeds on `404`), while `remote.describe` is versioned with the pairing contract and carries exactly the two public fields manual entry needs.
- **Make `hostPublicKey` optional in manual entry and trust the `pair` response** — rejected: it moves pinning after first contact, so a MITM on the first exchange is undetectable; fetching `describe` first keeps manual entry equivalent to QR scanning.

## Consequences

- Manual entry now pins before pairing: a mismatched or hostile host is rejected at the confirm screen, matching scanned-QR behavior, and the placeholder-key bypass is gone.
- `remote.describe` is public surface by design (key material only, no tokens or device data); the privileged policy is untouched and every other `remote.*` endpoint still requires bearer `full`.
- Deferred at this note's writing: host QR rendering, TLS fingerprint display in Flutter, LAN discovery/mDNS, and device proof-of-possession. Host QR rendering (ASCII plus manual block) and TLS fingerprint plumbing landed in the [transport/auth/console note](2026-09-06-remote-transport-auth-console.md); LAN discovery, device proof-of-possession, LAN SANs, and the React dashboard remain open.

## Verification

- `packages/host/remote-access/tests/pairing-qr.spec.ts` (20): build/encode/decode round-trips (URI, JSON, bare base64url), every malformed shape, expiry, issue with defaults and with PIN/TTL/displayName/custom generators, `describe`+`pair` unauthenticated, and `describe` returning the live host identity; `pairing-qr.ts` holds 100% statements/branches/functions/lines.
- `apps/flutter/test/features/devices/qr_payload_test.dart` (5): JSON parse, `toQrUri` round-trip, bare base64url, expiry and malformed rejection.
- `apps/flutter/test/api/connection_client_remote_describe_test.dart` (2): `remoteDescribe` posts `/api/remote/describe` and returns the identity; missing fields throw `FormatException`.
- `pnpm run build:lib:host` regenerates `lib/typert.host.js` / `lib/typert.remote-client.js` with `describe`; `typecheck:contracts-ready` passes; the two new/edited host files are oxlint-clean.
