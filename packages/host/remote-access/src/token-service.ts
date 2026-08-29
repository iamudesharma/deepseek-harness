/**
 * Signed bearer tokens for remote access (JWT-like, Ed25519).
 *
 * Tokens are bearer credentials: whoever holds the token string can call the
 * remote API until expiry or revocation. They are signed by the host's
 * Ed25519 private key and verified by its public key. The device's own
 * private key is NOT used for token verification in Phase 1; it is retained
 * only as the device's pairing identity and as a seam for future
 * proof-of-possession (signed-request) capability.
 *
 * Device private key  → pairing identity / future PoP capability
 * Device access token → current authenticated API credential
 *
 * Wire format: `base64url(header).base64url(payload).base64url(signature)`
 * where `signature = Ed25519.Sign(hostPrivateKey, ascii(header.payload))`
 * and header is `{alg:'EdDSA', typ:'JWT'}`.
 *
 * Payload fields (all required unless noted):
 *   iss: hostId, sub: deviceId, aud: 'dsh-remote', exp, iat, jti, scope.
 *
 * Validation checks (all fail-closed):
 *   signature, hostId, audience, expiry, device revocation, unknown device,
 *   scope when required.
 *
 * No plaintext token is ever logged; verifiers compare only digests when
 * emitting diagnostics.
 *
 * @module @deepseek-ai/dsh-host-remote-access/token-service
 */

import { randomUUID } from 'node:crypto'
import { base64urlEncode, base64urlDecode, base64urlEncodeJson, base64urlDecodeJson } from './crypto.ts'
import type { HostIdentity } from './host-identity.ts'
import { REMOTE_AUDIENCE } from './types.ts'

/** Audience bound into every token. */
export const TOKEN_AUDIENCE = REMOTE_AUDIENCE

/** Token payload (decoded, verified). */
export interface TokenPayload {
  /** Issuer: hostId. */
  readonly iss: string
  /** Subject: deviceId. */
  readonly sub: string
  /** Audience. */
  readonly aud: string
  /** Expiry epoch seconds (NOT milliseconds, per JWT). */
  readonly exp: number
  /** Issued-at epoch seconds. */
  readonly iat: number
  /** Unique token id. */
  readonly jti: string
  /** Scope (full or ws). */
  readonly scope: string
}

/** Options for minting a token. */
export interface MintTokenOptions {
  /** Device id. */
  deviceId: string
  /** TTL milliseconds. */
  ttlMs: number
  /** Scope; defaults to 'full'. */
  scope?: string
  /** Clock, defaults to Date.now. */
  now?: () => number
  /** JTI generator, defaults to randomUUID. */
  generateJti?: () => string
}

/** Validation options. */
export interface VerifyTokenOptions {
  /** Audience override, defaults to TOKEN_AUDIENCE. */
  audience?: string
  /** Clock, defaults to Date.now. */
  now?: () => number
  /** Lookup for revocation/unknown-device check. */
  deviceLookup?: (deviceId: string) => Promise<{ revoked: boolean } | undefined>
  /** Required scope when present. */
  requiredScope?: string
}

/** Token validation failure codes. */
export type TokenErrorCode =
  | 'token-malformed'
  | 'token-signature-invalid'
  | 'token-expired'
  | 'token-host-mismatch'
  | 'token-audience-mismatch'
  | 'token-scope-mismatch'
  | 'token-revoked'
  | 'token-unknown-device'

/** Token validation failure. */
export class TokenError extends Error {
  /** Machine code. */
  readonly code: TokenErrorCode

  /**
   * Create a token error.
   * @param code - machine code.
   * @param message - human diagnostic (never echoes the raw token).
   */
  constructor(code: TokenErrorCode, message: string) {
    super(message)
    this.name = 'TokenError'
    this.code = code
  }
}

const HEADER = { alg: 'EdDSA', typ: 'JWT' } as const
const HEADER_B64 = base64urlEncodeJson(HEADER)

const DEVICE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const HOST_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/

function toEpochSeconds(ms: number): number {
  return Math.floor(ms / 1000)
}

/**
 * Host-bound token service (sign + verify).
 */
export class TokenService {
  /**
   * Create a token service bound to a host identity.
   * @param identity - host identity (its keypair and hostId).
   */
  constructor(private readonly identity: HostIdentity) {}

  /** HostId this service mints for. */
  get hostId(): string {
    return this.identity.hostId
  }

  /**
   * Mint a signed bearer token for a device.
   * @param options - deviceId, ttl, scope.
   * @returns token string.
   */
  mint(options: MintTokenOptions): string {
    if (!DEVICE_ID_PATTERN.test(options.deviceId)) {
      throw new Error(`token-service: invalid deviceId ${JSON.stringify(options.deviceId)}`)
    }
    if (options.ttlMs <= 0 || options.ttlMs > 365 * 24 * 60 * 60 * 1000) {
      throw new Error('token-service: ttlMs must be positive and at most 365 days')
    }
    const nowMs = (options.now ?? Date.now)()
    const iat = toEpochSeconds(nowMs)
    const exp = toEpochSeconds(nowMs + options.ttlMs)
    if (exp <= iat) {
      throw new Error('token-service: ttl too short to span one second')
    }
    const jti = (options.generateJti ?? randomUUID)()
    const scope = options.scope ?? 'full'
    const payload: TokenPayload = {
      iss: this.identity.hostId,
      sub: options.deviceId,
      aud: TOKEN_AUDIENCE,
      exp,
      iat,
      jti,
      scope,
    }
    const payloadB64 = base64urlEncodeJson(payload)
    const signingInput = `${HEADER_B64}.${payloadB64}`
    const signature = this.identity.sign(Buffer.from(signingInput, 'utf8'))
    return `${signingInput}.${base64urlEncode(signature)}`
  }

  /**
   * Verify a bearer token: signature, hostId, audience, expiry, and optional
   * revocation/device-existence via lookup.
   *
   * No plaintext token is logged; diagnostics mention only the failure code and
   * the token's jti prefix when safe.
   *
   * @param token - bearer token string.
   * @param options - audience, clock, revocation lookup, scope.
   * @returns verified payload.
   * @throws {@link TokenError} on any failure.
   */
  async verify(token: string, options: VerifyTokenOptions = {}): Promise<TokenPayload> {
    const parts = token.split('.')
    if (parts.length !== 3) {
      throw new TokenError('token-malformed', 'token must have three dot-separated parts')
    }
    const [headerB64, payloadB64, signatureB64] = parts as [string, string, string]
    if (headerB64 !== HEADER_B64) {
      // Header is fixed for this service; a different header means not our token.
      throw new TokenError('token-malformed', 'token header is not EdDSA JWT')
    }
    let payload: TokenPayload
    try {
      const decoded = base64urlDecodeJson(payloadB64) as Record<string, unknown>
      if (typeof decoded['iss'] !== 'string' || typeof decoded['sub'] !== 'string'
        || typeof decoded['aud'] !== 'string' || typeof decoded['exp'] !== 'number'
        || typeof decoded['iat'] !== 'number' || typeof decoded['jti'] !== 'string'
        || typeof decoded['scope'] !== 'string') {
        throw new Error('missing field')
      }
      payload = decoded as unknown as TokenPayload
    } catch {
      throw new TokenError('token-malformed', 'token payload is malformed')
    }
    let signature: Buffer
    try {
      signature = base64urlDecode(signatureB64)
      if (signature.length !== 64) throw new Error('bad length')
    } catch {
      throw new TokenError('token-malformed', 'token signature is malformed')
    }
    if (!HOST_ID_PATTERN.test(payload.iss)) {
      throw new TokenError('token-host-mismatch', 'token issuer is malformed')
    }
    if (payload.iss !== this.identity.hostId) {
      throw new TokenError('token-host-mismatch', 'token issuer does not match this host')
    }
    const audience = options.audience ?? TOKEN_AUDIENCE
    if (payload.aud !== audience) {
      throw new TokenError('token-audience-mismatch', `token audience ${JSON.stringify(payload.aud)} does not match ${JSON.stringify(audience)}`)
    }
    if (!DEVICE_ID_PATTERN.test(payload.sub)) {
      throw new TokenError('token-malformed', 'token subject is malformed')
    }
    const nowSec = toEpochSeconds((options.now ?? Date.now)())
    if (payload.exp <= nowSec) {
      throw new TokenError('token-expired', 'token has expired')
    }
    if (payload.iat > nowSec + 60) {
      // Allow small clock skew (60s), but reject a token that claims to be from the far future.
      throw new TokenError('token-malformed', 'token issued-at is in the future')
    }
    if (options.requiredScope !== undefined && payload.scope !== options.requiredScope) {
      throw new TokenError('token-scope-mismatch', `token scope ${JSON.stringify(payload.scope)} does not satisfy ${JSON.stringify(options.requiredScope)}`)
    }
    const signingInput = `${headerB64}.${payloadB64}`
    if (!this.identity.verify(Buffer.from(signingInput, 'utf8'), signature)) {
      throw new TokenError('token-signature-invalid', 'token signature is invalid')
    }
    if (options.deviceLookup !== undefined) {
      const device = await options.deviceLookup(payload.sub)
      if (device === undefined) {
        throw new TokenError('token-unknown-device', 'token device is unknown')
      }
      if (device.revoked) {
        throw new TokenError('token-revoked', 'token device has been revoked')
      }
    }
    return payload
  }

  /**
   * Verify a short-lived WebSocket ticket (scope 'ws', audience unchanged).
   * Convenience wrapper for the ticket flow.
   * @param ticket - ticket string.
   * @param options - clock and device lookup.
   * @returns verified payload with scope 'ws'.
   */
  async verifyWsTicket(ticket: string, options: VerifyTokenOptions = {}): Promise<TokenPayload> {
    return this.verify(ticket, { ...options, requiredScope: 'ws', audience: options.audience ?? TOKEN_AUDIENCE })
  }

  /**
   * Mint a short-lived WebSocket ticket.
   * @param deviceId - device id.
   * @param ttlMs - ticket TTL (e.g. 60_000).
   * @param now - clock.
   * @returns ticket string.
   */
  mintWsTicket(deviceId: string, ttlMs: number = 60_000, now?: () => number): string {
    if (now === undefined) return this.mint({ deviceId, ttlMs, scope: 'ws' })
    return this.mint({ deviceId, ttlMs, scope: 'ws', now })
  }
}
