/**
 * Client-safe types for the remote-access domain.
 * These are the canonical request/response vocabularies Typert will generate
 * strict codecs for; they contain no Node or Cordis imports.
 *
 * @module @deepseek-ai/dsh-host-remote-access/types
 */

/** Pairing request: device proves its identity and presents the host's pairing nonce/PIN. */
export interface PairRequest {
  /** Stable host identifier the device expects (prevents cross-host replay). */
  readonly hostId: string
  /** Device-generated stable id (UUID v4). */
  readonly deviceId: string
  /** Human label for the device (e.g. "Pixel 7"). */
  readonly displayName: string
  /** Base64 SPKI DER of the device's Ed25519 public key (future PoP; not verified in Phase 1). */
  readonly devicePublicKey: string
  /** One-time pairing nonce issued by the host pairing ceremony. */
  readonly nonce: string
  /** Optional 6-digit PIN when the host issued one. */
  readonly pin?: string
}

/** Pairing result: the host's identity and the bearer token for subsequent calls. */
export interface PairResult {
  /** Confirmed hostId (echoed). */
  readonly hostId: string
  /** Host public key SPKI DER, base64 (for device-side pinning). */
  readonly hostPublicKey: string
  /** Bearer access token (JWT-like, signed by host). */
  readonly deviceToken: string
  /** Token expiry epoch milliseconds. */
  readonly expiresAt: number
}

/** Device directory row. */
export interface DeviceView {
  /** Stable device id. */
  readonly deviceId: string
  /** Human label. */
  readonly displayName: string
  /** Base64 SPKI DER of the device public key. */
  readonly devicePublicKey: string
  /** Creation epoch milliseconds. */
  readonly createdAt: number
  /** Last successful authentication epoch milliseconds. */
  readonly lastSeenAt: number
  /** Whether the device has been revoked. */
  readonly revoked: boolean
  /** When revoked, epoch milliseconds. */
  readonly revokedAt?: number
}

/** List devices result. */
export interface DevicesResult {
  /** All known devices, ordered by most recent lastSeenAt descending. */
  readonly devices: readonly DeviceView[]
}

/** Revoke one device request. */
export interface RevokeRequest {
  /** Device to revoke. */
  readonly deviceId: string
}

/** Refresh token result. */
export interface RefreshResult {
  /** New bearer token (previous jti remains valid until expiry unless revoked). */
  readonly deviceToken: string
  /** New expiry epoch milliseconds. */
  readonly expiresAt: number
}

/** Short-lived WebSocket ticket request. */
export interface WsTicketRequest {
  /** No payload; caller must already be bearer-authenticated. */
  readonly _empty?: never
}

/** Short-lived WebSocket ticket result. */
export interface WsTicketResult {
  /** Opaque ticket (signed, 60s TTL). */
  readonly ticket: string
  /** Expiry epoch milliseconds. */
  readonly expiresAt: number
}

/** Pairing ceremony nonce creation result (server-side ceremony, not a Typert remote yet). */
export interface PairingNonceResult {
  /** One-time nonce. */
  readonly nonce: string
  /** 6-digit PIN when requested. */
  readonly pin?: string
  /** Expiry epoch milliseconds. */
  readonly expiresAt: number
}

/** Shared audience constant for access tokens. */
export const REMOTE_AUDIENCE = 'dsh-remote' as const

/** Token scope constants. */
export const REMOTE_SCOPE_FULL = 'full' as const
export const REMOTE_SCOPE_WS = 'ws' as const
