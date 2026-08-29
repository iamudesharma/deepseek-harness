/**
 * Server-side pairing state: one-time nonces with short TTL and optional 6-digit PIN.
 *
 * Pairing is the only operation that creates a device without a bearer token.
 * It is guarded by a short-lived, one-use nonce (and optional PIN) that the
 * host's pairing ceremony issued and that the device must present along with
 * its asserted hostId/deviceId. The store is process-local memory only; a host
 * restart invalidates outstanding ceremonies, which is safe (the user simply
 * re-initiates pairing). Replay protection is enforced by consuming the nonce
 * on first successful validation — a second attempt with the same nonce fails.
 *
 * @module @deepseek-ai/dsh-host-remote-access/pairing-store
 */

import { randomUUID, randomInt } from 'node:crypto'

const DEVICE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const HOST_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/
const NONCE_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PIN_PATTERN = /^[0-9]{6}$/

/** One outstanding pairing ceremony. */
export interface PairingEntry {
  /** One-time nonce. */
  readonly nonce: string
  /** Optional 6-digit PIN; when present the device must present it. */
  readonly pin?: string
  /** HostId the ceremony was issued for. */
  readonly hostId: string
  /** Creation epoch milliseconds. */
  readonly createdAt: number
  /** Expiry epoch milliseconds. */
  readonly expiresAt: number
}

/** Options for creating a pairing ceremony. */
export interface CreatePairingOptions {
  /** HostId the ceremony binds to. */
  hostId: string
  /** TTL in milliseconds; defaults to 5 minutes. */
  ttlMs?: number
  /** Whether to mint a 6-digit PIN; defaults to false. */
  withPin?: boolean
  /** Clock, defaults to Date.now. */
  now?: () => number
  /** Nonce generator, defaults to randomUUID. */
  generateNonce?: () => string
  /** PIN generator, defaults to crypto randomInt. */
  generatePin?: () => string
}

/** Validation input for consuming a ceremony. */
export interface ConsumePairingOptions {
  /** Presented nonce. */
  nonce: string
  /** Presented PIN when the ceremony required one (absent otherwise). */
  pin?: string
  /** Device's asserted hostId. */
  hostId: string
  /** Device's asserted deviceId. */
  deviceId: string
  /** Clock, defaults to Date.now. */
  now?: () => number
}

/** Pairing failure codes, mapped to wire errors by the Remote layer. */
export type PairingErrorCode =
  | 'pairing-nonce-unknown'
  | 'pairing-nonce-expired'
  | 'pairing-nonce-reused'
  | 'pairing-pin-invalid'
  | 'pairing-pin-required'
  | 'pairing-host-mismatch'
  | 'pairing-device-invalid'

/** Pairing validation failure. */
export class PairingError extends Error {
  /** Machine code. */
  readonly code: PairingErrorCode

  /**
   * Create a pairing error.
   * @param code - machine code.
   * @param message - human diagnostic.
   */
  constructor(code: PairingErrorCode, message: string) {
    super(message)
    this.name = 'PairingError'
    this.code = code
  }
}

/**
 * In-memory, one-use pairing store with TTL and optional PIN.
 */
export class PairingStore {
  private readonly entries = new Map<string, PairingEntry>()
  private readonly consumed = new Set<string>()

  /**
   * Create a new pairing ceremony.
   * @param options - hostId, ttl, PIN toggle.
   * @returns the issued nonce (and PIN when requested).
   * @throws when hostId is malformed.
   */
  create(options: CreatePairingOptions): PairingEntry {
    if (!HOST_ID_PATTERN.test(options.hostId)) {
      throw new PairingError('pairing-host-mismatch', 'invalid hostId')
    }
    const now = (options.now ?? Date.now)()
    const ttlMs = options.ttlMs ?? 5 * 60 * 1000
    if (ttlMs <= 0 || ttlMs > 30 * 60 * 1000) {
      throw new Error('pairing-store: ttlMs must be positive and at most 30 minutes')
    }
    const nonce = (options.generateNonce ?? randomUUID)()
    if (!NONCE_PATTERN.test(nonce)) {
      throw new Error('pairing-store: nonce must be a UUID')
    }
    if (this.entries.has(nonce) || this.consumed.has(nonce)) {
      throw new Error('pairing-store: nonce collision')
    }
    let pin: string | undefined
    if (options.withPin === true) {
      const generatePin = options.generatePin ?? (() => String(randomInt(0, 1_000_000)).padStart(6, '0'))
      pin = generatePin()
      if (!PIN_PATTERN.test(pin)) {
        throw new Error('pairing-store: PIN must be 6 digits')
      }
    }
    const entry: PairingEntry = {
      nonce,
      hostId: options.hostId,
      createdAt: now,
      expiresAt: now + ttlMs,
      ...(pin === undefined ? {} : { pin }),
    }
    this.entries.set(nonce, entry)
    return entry
  }

  /**
   * Validate and consume a pairing ceremony (one-use, replay-protected).
   * @param options - presented nonce/pin/hostId/deviceId.
   * @throws {@link PairingError} on any validation failure.
   */
  consume(options: ConsumePairingOptions): PairingEntry {
    const now = (options.now ?? Date.now)()
    // DeviceId validation is hostId-agnostic and cheap; fail fast.
    if (!DEVICE_ID_PATTERN.test(options.deviceId)) {
      throw new PairingError('pairing-device-invalid', `invalid deviceId ${JSON.stringify(options.deviceId)}`)
    }
    if (!HOST_ID_PATTERN.test(options.hostId)) {
      throw new PairingError('pairing-host-mismatch', 'invalid hostId')
    }
    if (this.consumed.has(options.nonce)) {
      throw new PairingError('pairing-nonce-reused', 'pairing nonce has already been used')
    }
    const entry = this.entries.get(options.nonce)
    if (entry === undefined) {
      throw new PairingError('pairing-nonce-unknown', 'unknown pairing nonce')
    }
    if (now > entry.expiresAt) {
      this.entries.delete(options.nonce)
      throw new PairingError('pairing-nonce-expired', 'pairing nonce has expired')
    }
    if (entry.hostId !== options.hostId) {
      throw new PairingError('pairing-host-mismatch', 'hostId does not match pairing ceremony')
    }
    if (entry.pin !== undefined) {
      if (options.pin === undefined) {
        throw new PairingError('pairing-pin-required', 'pairing PIN required')
      }
      if (options.pin !== entry.pin) {
        throw new PairingError('pairing-pin-invalid', 'pairing PIN is invalid')
      }
    } else if (options.pin !== undefined) {
      throw new PairingError('pairing-pin-invalid', 'pairing PIN not expected for this ceremony')
    }
    // One-use: move from outstanding to consumed.
    this.entries.delete(options.nonce)
    this.consumed.add(options.nonce)
    return entry
  }

  /** Whether a nonce is currently outstanding (diagnostics). */
  has(nonce: string): boolean {
    return this.entries.has(nonce)
  }

  /** Outstanding count (diagnostics). */
  get size(): number {
    return this.entries.size
  }

  /**
   * Remove expired entries (callers may invoke periodically; expiry is also
   * checked at consume time).
   * @param now - clock.
   * @returns number of entries evicted.
   */
  prune(now: () => number = Date.now): number {
    const at = now()
    let evicted = 0
    for (const [nonce, entry] of this.entries) {
      if (at > entry.expiresAt) {
        this.entries.delete(nonce)
        evicted++
      }
    }
    return evicted
  }

  /** Clear all state (test seam). */
  clear(): void {
    this.entries.clear()
    this.consumed.clear()
  }
}
