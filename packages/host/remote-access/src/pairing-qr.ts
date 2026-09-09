/**
 * Pairing QR payload builder for remote Flutter pairing.
 *
 * The host issues a one-time pairing ceremony (`PairingStore.create`) and
 * renders it as a `dsh://pair?data=base64url(json)` URI. The mobile scans the
 * URI, validates every field before contacting the host, and re-validates the
 * host identity after `remote.pair` to detect MITM. Manual entry uses the same
 * JSON fields without the URI wrapper.
 *
 * @module @deepseek-ai/dsh-host-remote-access/pairing-qr
 */

import { base64urlDecodeJson, base64urlEncodeJson } from './crypto.ts'
import type { CreatePairingOptions, PairingStore } from './pairing-store.ts'

/** QR payload fields shared by the URI wrapper and manual entry. */
export interface PairingQrPayload {
  /** Host base URI (`https://host:port`, no trailing slash, no path). */
  readonly baseUri: string
  /** Pinned hostId (`base64url(sha256(spki))`, 43 chars). */
  readonly hostId: string
  /** Host public key SPKI DER, base64 (for device-side pinning). */
  readonly hostPublicKey: string
  /** One-time pairing nonce (UUID). */
  readonly nonce: string
  /** Optional 6-digit PIN when the ceremony required one. */
  readonly pin?: string
  /** Expiry epoch milliseconds. */
  readonly exp: number
  /** Optional host display label. */
  readonly displayName?: string
  /** Optional TLS certificate fingerprint (`base64url(sha256(der))`, 43 chars). */
  readonly certFp?: string
}

/** Input for issuing a pairing QR from a live ceremony. */
export interface IssuePairingQrOptions {
  /** Host base URI the device connects to (`https://host:port`). */
  baseUri: string
  /** Stable hostId the ceremony binds to. */
  hostId: string
  /** Host public key SPKI DER, base64. */
  hostPublicKey: string
  /** Whether to mint a 6-digit PIN. */
  withPin?: boolean
  /** Ceremony TTL in milliseconds (default 5 minutes). */
  ttlMs?: number
  /** Optional host display label embedded in the payload. */
  displayName?: string
  /** Optional TLS certificate fingerprint embedded for device pinning. */
  certFp?: string
  /** Clock, defaults to `Date.now`. */
  now?: () => number
  /** Nonce generator, defaults to `randomUUID`. */
  generateNonce?: () => string
  /** PIN generator, defaults to crypto `randomInt`. */
  generatePin?: () => string
}

/** Issued pairing ceremony with its renderable forms. */
export interface IssuedPairingQr {
  /** Validated payload. */
  readonly payload: PairingQrPayload
  /** `dsh://pair?data=…` URI for QR rendering. */
  readonly uri: string
  /** Raw JSON payload for manual entry display. */
  readonly json: PairingQrPayload
  /** Expiry epoch milliseconds (mirrors `payload.exp`). */
  readonly expiresAt: number
}

const HOST_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/
const NONCE_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PIN_PATTERN = /^[0-9]{6}$/

/**
 * Normalize a base URI: trim whitespace and strip one trailing slash.
 * @param value - raw base URI.
 * @returns normalized URI without a trailing slash.
 */
export function normalizeBaseUri(value: string): string {
  const trimmed = value.trim()
  if (trimmed.endsWith('/')) return trimmed.slice(0, -1)
  return trimmed
}

/**
 * Validate a base URI has a scheme and authority.
 * @param value - normalized base URI.
 * @returns true when the URI parses with scheme and authority.
 */
function isValidBaseUri(value: string): boolean {
  try {
    const parsed = new URL(value)
    return parsed.protocol === 'https:' || parsed.protocol === 'http:'
  } catch {
    return false
  }
}

/**
 * Validate a host public key is non-empty base64.
 * @param value - candidate key.
 * @returns true when the value decodes as base64.
 */
function isValidHostPublicKey(value: string): boolean {
  if (value.length === 0) return false
  const decoded = Buffer.from(value, 'base64')
  return decoded.length > 0
}

/**
 * Build a validated pairing QR payload.
 * @param payload - candidate payload fields.
 * @returns the validated payload.
 * @throws when any field is malformed.
 */
export function buildPairingQrPayload(payload: PairingQrPayload): PairingQrPayload {
  const baseUri = normalizeBaseUri(payload.baseUri)
  if (!isValidBaseUri(baseUri)) throw new Error('pairing-qr: invalid baseUri')
  if (!HOST_ID_PATTERN.test(payload.hostId)) throw new Error('pairing-qr: invalid hostId')
  if (!isValidHostPublicKey(payload.hostPublicKey)) throw new Error('pairing-qr: invalid hostPublicKey')
  if (!NONCE_PATTERN.test(payload.nonce)) throw new Error('pairing-qr: invalid nonce')
  if (payload.pin !== undefined && !PIN_PATTERN.test(payload.pin)) throw new Error('pairing-qr: invalid PIN')
  if (!Number.isInteger(payload.exp)) throw new Error('pairing-qr: invalid exp')
  if (payload.certFp !== undefined && !HOST_ID_PATTERN.test(payload.certFp)) throw new Error('pairing-qr: invalid certFp')
  return {
    baseUri,
    hostId: payload.hostId,
    hostPublicKey: payload.hostPublicKey,
    nonce: payload.nonce,
    ...(payload.pin === undefined ? {} : { pin: payload.pin }),
    exp: payload.exp,
    ...(payload.displayName === undefined ? {} : { displayName: payload.displayName }),
    ...(payload.certFp === undefined ? {} : { certFp: payload.certFp }),
  }
}

/**
 * Encode a payload as a `dsh://pair?data=…` URI for QR rendering.
 * @param payload - validated payload fields.
 * @returns the scannable URI.
 */
export function encodePairingQrPayload(payload: PairingQrPayload): string {
  const built = buildPairingQrPayload(payload)
  return `dsh://pair?data=${base64urlEncodeJson(built)}`
}

/**
 * Decode a QR string (`dsh://pair?data=…`, bare base64url, or plain JSON).
 * @param raw - scanned string.
 * @param now - clock for expiry check, defaults to `Date.now`.
 * @returns the validated payload.
 * @throws when the string is malformed or expired.
 */
export function decodePairingQrPayload(raw: string, now: () => number = Date.now): PairingQrPayload {
  const trimmed = raw.trim()
  let jsonValue: unknown
  if (trimmed.startsWith('dsh://')) {
    let data: string | null = null
    try {
      data = new URL(trimmed).searchParams.get('data')
    } catch {
      throw new Error('pairing-qr: invalid dsh:// URI')
    }
    if (data === null || data.length === 0) throw new Error('pairing-qr: missing data in dsh:// URI')
    try {
      jsonValue = base64urlDecodeJson(data)
    } catch {
      throw new Error('pairing-qr: invalid base64url data')
    }
  } else if (trimmed.startsWith('{')) {
    try {
      jsonValue = JSON.parse(trimmed)
    } catch {
      throw new Error('pairing-qr: invalid JSON')
    }
  } else {
    try {
      jsonValue = base64urlDecodeJson(trimmed)
    } catch {
      throw new Error('pairing-qr: invalid payload')
    }
  }
  if (typeof jsonValue !== 'object' || jsonValue === null) throw new Error('pairing-qr: invalid payload')
  const record = jsonValue as Record<string, unknown>
  if (record['baseUri'] === undefined || record['hostId'] === undefined
    || record['hostPublicKey'] === undefined || record['nonce'] === undefined
    || record['exp'] === undefined) {
    throw new Error('pairing-qr: missing required QR fields')
  }
  const baseUriRaw = record['baseUri']
  const hostIdRaw = record['hostId']
  const hostPublicKeyRaw = record['hostPublicKey']
  const nonceRaw = record['nonce']
  if (typeof baseUriRaw !== 'string' || typeof hostIdRaw !== 'string'
    || typeof hostPublicKeyRaw !== 'string' || typeof nonceRaw !== 'string') {
    throw new Error('pairing-qr: invalid payload')
  }
  const candidate: PairingQrPayload = {
    baseUri: baseUriRaw,
    hostId: hostIdRaw,
    hostPublicKey: hostPublicKeyRaw,
    nonce: nonceRaw,
    ...(typeof record['pin'] === 'string' ? { pin: record['pin'] } : {}),
    exp: typeof record['exp'] === 'number' ? record['exp'] : Number.NaN,
    ...(typeof record['displayName'] === 'string' ? { displayName: record['displayName'] } : {}),
    ...(typeof record['certFp'] === 'string' ? { certFp: record['certFp'] } : {}),
  }
  const built = buildPairingQrPayload(candidate)
  if (built.exp <= now()) throw new Error('pairing-qr: QR expired')
  return built
}

/**
 * Issue a pairing ceremony and render it as a QR payload.
 * @param pairing - live pairing store.
 * @param options - base URI, host identity, and ceremony options.
 * @returns the issued payload with its URI and JSON forms.
 */
export function issuePairingQr(pairing: PairingStore, options: IssuePairingQrOptions): IssuedPairingQr {
  const now = options.now ?? Date.now
  const createOptions: CreatePairingOptions = {
    hostId: options.hostId,
    ...(options.ttlMs === undefined ? {} : { ttlMs: options.ttlMs }),
    ...(options.withPin === true ? { withPin: true as const } : {}),
    now,
    ...(options.generateNonce === undefined ? {} : { generateNonce: options.generateNonce }),
    ...(options.generatePin === undefined ? {} : { generatePin: options.generatePin }),
  }
  const entry = pairing.create(createOptions)
  const at = now()
  const ttlMs = options.ttlMs ?? 5 * 60 * 1000
  const payload = buildPairingQrPayload({
    baseUri: normalizeBaseUri(options.baseUri),
    hostId: options.hostId,
    hostPublicKey: options.hostPublicKey,
    nonce: entry.nonce,
    ...(entry.pin === undefined ? {} : { pin: entry.pin }),
    exp: at + ttlMs,
    ...(options.displayName === undefined ? {} : { displayName: options.displayName }),
    ...(options.certFp === undefined ? {} : { certFp: options.certFp }),
  })
  return {
    payload,
    uri: encodePairingQrPayload(payload),
    json: payload,
    expiresAt: payload.exp,
  }
}
