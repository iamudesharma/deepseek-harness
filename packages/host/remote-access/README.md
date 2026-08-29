# @deepseek-ai/dsh-host-remote-access

English | [中文](README.zh.md)

Secure host identity and remote-access foundation (Phase 1). Provides the persistent Ed25519 host identity, the atomic device registry, the one-time pairing nonce/PIN store, and the signed bearer-token primitives that the later authentication middleware (Phase 2) will enforce. No external listener is exposed and the default host remains `127.0.0.1:3080` — `dsh web` without remote mode behaves exactly as before.

## Host identity

`$DSH_HOME/remote/host-identity.json` (`0600`, dirs `0700`) holds a versioned document with `publicKey` (base64 SPKI DER), `privateKey` (base64 PKCS8 DER), `hostId`, and `createdAt`. Generation uses `node:crypto` `generateKeyPairSync('ed25519')` only when no valid document exists; corruption is rejected rather than silently regenerated so a broken home never forks its identity. `hostId = base64url(sha256(spkiDer))` — the stable issuer bound into every token and validated on pairing.

## Device registry

`$DSH_HOME/remote/devices.json` (`0600`) holds `{version, devices: DeviceRecord[]}`. Each record stores `deviceId` (UUID v4), `displayName`, `publicKey` (base64 SPKI DER, public only — no private key material), `createdAt`, `lastSeenAt`, `revoked`, and `lastJti`/`tokenExpiresAt` metadata. Writes are `mkdir 0700` + `withFileLock` RMW + `writeFileAtomic 0600` so readers see either the old or the new complete document and concurrent writers serialize. No plaintext private keys are stored and no token is logged.

## Pairing

`PairingStore` is in-memory, one-use, with short TTL (default 5 min, max 30 min) and optional 6-digit PIN. `create()` mints a UUID nonce (and PIN when requested); `consume()` validates `hostId`, `deviceId` (UUID), nonce existence, expiry, PIN match, and one-use replay protection (`consumed` set). Expiry is checked both at validation and via `prune()`. The store has no HTTP surface in Phase 1 — the future `/api/remote/pair` handler will call it behind the (still inactive) auth boundary.

## Tokens

Bearer access tokens are `base64url(header).base64url(payload).base64url(Ed25519 signature)` where `signature = Sign(hostPrivateKey, ascii(header.payload))` and `header = {alg: EdDSA, typ: JWT}`. Payload carries `iss` (hostId), `sub` (deviceId), `aud` (`dsh-remote`), `exp`/`iat` (seconds), `jti`, and `scope` (`full` or `ws`). Verification checks signature, issuer, audience, expiry (with 60s future-iat skew allowance), optional `requiredScope`, and an optional `deviceLookup` for revocation/unknown-device. `mintWsTicket` is a `scope: ws` short-lived variant (60s). Bearer token is the actual credential; device private key is the pairing identity and seam for future proof-of-possession.

## Remote API contract

`src/remote-service.ts` declares the canonical Typert `remote.*` endpoints (`pair`, `devices`, `revoke`, `refresh`, `ws-ticket`) as `@Remote` methods on `RemoteAccessService` (`namespace: remote`). Generation via `tsdown --env.DSH_BUILD_FACE host` produces `lib/typert.host.*` + `lib/typert.remote-client.*` strict Zod codecs and declaration merges; Flutter consumes the same envelope over `POST /api/remote/*` with `http` + `json_serializable`, not a second schema.

## Model Experience

None — the foundation moves no model-visible content and owns no prompt assembly.

#### KV Cache effect

None — no provider request is assembled or sent.

## Known Limitations and Deferred Work

- **No external listener in Phase 1** — the Typert `remote.*` contribution is registered but no `0.0.0.0` server or auth middleware is mounted; Phase 2 will gate the transport behind `config.enabled` and the `remote.ws-ticket` ticket flow.
- **Device PoP not enforced** — the device public key is stored at pairing but bearer token verification does not require a request signature; signed-request proof-of-possession is the deferred next step.
