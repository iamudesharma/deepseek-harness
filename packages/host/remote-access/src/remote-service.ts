/**
 * Canonical Remote API contract for `remote.*` (Typert) — Phase 2 real handlers.
 *
 * This is the single source of truth for the five remote endpoints:
 * `remote.pair`, `remote.devices`, `remote.revoke`, `remote.refresh`,
 * `remote.ws-ticket`. Typert generation produces strict Zod codecs and
 * declaration merges for both Host dispatch and Client `ctx.remote.*`
 * callers; Flutter consumes the same envelope over HTTP (`POST /api/remote/*`)
 * with `http` + `json_serializable`, not a second schema.
 *
 * Pairing (`remote.pair`) is the ONLY intentional unauthenticated entry point
 * and requires a valid nonce/PIN, explicit host approval, and hostId validation.
 * All other endpoints require bearer authentication (verified by auth middleware
 * via AsyncLocalStorage) and are subject to the privileged policy.
 *
 * @module @deepseek-ai/dsh-host-remote-access/remote-service
 */

import { Context } from '@deepseek-ai/cordis'
import { TypertRemoteService, Remote } from '@deepseek-ai/dsh-typert-protocol'
import type {
  DevicesResult,
  PairRequest,
  PairResult,
  RefreshResult,
  RevokeRequest,
  WsTicketResult,
} from './types.ts'
import { remoteAuthStorage } from './auth-middleware.ts'

declare module '@deepseek-ai/cordis' {
  interface Context {
    /** Remote-access service (`ctx.remoteAccess`). */
    remoteAccess: RemoteAccessService
  }
}

/**
 * Remote-access service: Typert endpoints for pairing, device directory,
 * revocation, token refresh, and WebSocket tickets.
 */
export class RemoteAccessService extends TypertRemoteService {
  static inject = ['remoteAccessFoundation']

  constructor(ctx: Context) {
    super(ctx, 'remoteAccess', { namespace: 'remote' })
  }

  private get foundation(): import('./index.ts').RemoteAccessFoundation {
    const foundation = (this.ctx as unknown as { remoteAccessFoundation?: import('./index.ts').RemoteAccessFoundation })
      .remoteAccessFoundation
    if (foundation === undefined) throw new Error('remote-access: foundation not available')
    return foundation
  }

  /**
   * Pair a device using a one-time nonce (and optional PIN).
   * Requires explicit host approval before minting.
   * @param request - pairing presentation.
   * @returns host identity and bearer token.
   */
  @Remote('pair')
  async pair(request: PairRequest): Promise<PairResult> {
    const foundation = this.foundation
    if (request.hostId !== foundation.hostIdentity.hostId) {
      throw Object.assign(new Error('hostId does not match this host'), { code: 'pairing-host-mismatch' })
    }
    let consumed
    try {
      const consumeArgs: import('./pairing-store.ts').ConsumePairingOptions = request.pin === undefined
        ? { nonce: request.nonce, hostId: request.hostId, deviceId: request.deviceId }
        : { nonce: request.nonce, pin: request.pin, hostId: request.hostId, deviceId: request.deviceId }
      consumed = foundation.pairing.consume(consumeArgs)
    } catch (error) {
      foundation.audit.record({ kind: 'pair-requested', detail: String((error as Error).message), deviceId: request.deviceId, hostId: request.hostId })
      throw error
    }
    foundation.audit.record({ kind: 'pair-requested', deviceId: request.deviceId, hostId: request.hostId, detail: `nonce:${request.nonce.slice(0, 8)}…` })
    // Explicit host approval (no auto-approve).
    const approval = foundation.approval.request(request, consumed.nonce)
    // For headless hosts, also log a CLI prompt.
    const pendingMsg = `remote-access: pairing request from "${request.displayName}" (${request.deviceId}) — run "dsh remote approve ${consumed.nonce}" or deny`
    this.ctx.logger.info(pendingMsg)
    const decision = await Promise.race([
      approval.promise,
      new Promise<'timeout'>(resolve => setTimeout(() => resolve('timeout'), 30_000)),
    ])
    if (decision === 'timeout') {
      foundation.audit.record({ kind: 'pair-denied', deviceId: request.deviceId, detail: 'timeout' })
      throw Object.assign(new Error('pairing approval timed out'), { code: 'pairing-timeout' })
    }
    if (decision === 'denied') {
      foundation.audit.record({ kind: 'pair-denied', deviceId: request.deviceId })
      throw Object.assign(new Error('pairing denied by host'), { code: 'pairing-denied' })
    }
    // Approved: add device and mint token.
    const existing = await foundation.devices.find(request.deviceId)
    if (existing !== undefined) {
      throw Object.assign(new Error('device already paired'), { code: 'device-duplicate' })
    }
    const now = Date.now()
    await foundation.devices.add({
      deviceId: request.deviceId,
      displayName: request.displayName,
      publicKey: request.devicePublicKey,
      createdAt: now,
      lastSeenAt: now,
      revoked: false,
    })
    const ttlMs = 90 * 24 * 60 * 60 * 1000
    const deviceToken = foundation.tokenService.mint({ deviceId: request.deviceId, ttlMs, now: () => now })
    const payload = await foundation.tokenService.verify(deviceToken, { now: () => now })
    foundation.audit.record({ kind: 'pair-approved', deviceId: request.deviceId })
    return {
      hostId: foundation.hostIdentity.hostId,
      hostPublicKey: foundation.hostIdentity.publicKeyDer.toString('base64'),
      deviceToken,
      expiresAt: payload.exp * 1000,
    }
  }

  /**
   * List known devices (requires bearer full).
   * @returns device directory (no private keys or tokens).
   */
  @Remote('devices')
  async devices(): Promise<DevicesResult> {
    const auth = remoteAuthStorage.getStore()
    if (auth === undefined) throw Object.assign(new Error('authentication required'), { code: 'auth-required' })
    if (auth.scope !== 'full') throw Object.assign(new Error('invalid scope'), { code: 'invalid-scope' })
    const foundation = this.foundation
    const all = await foundation.devices.list()
    return {
      devices: all.map(entry => ({
        deviceId: entry.deviceId,
        displayName: entry.displayName,
        devicePublicKey: entry.publicKey,
        createdAt: entry.createdAt,
        lastSeenAt: entry.lastSeenAt,
        revoked: entry.revoked,
        ...(entry.revokedAt === undefined ? {} : { revokedAt: entry.revokedAt }),
      })),
    }
  }

  /**
   * Revoke one device by id (requires bearer full).
   * @param request - device to revoke.
   */
  @Remote('revoke')
  async revoke(request: RevokeRequest): Promise<void> {
    const auth = remoteAuthStorage.getStore()
    if (auth === undefined) throw Object.assign(new Error('authentication required'), { code: 'auth-required' })
    if (auth.scope !== 'full') throw Object.assign(new Error('invalid scope'), { code: 'invalid-scope' })
    const foundation = this.foundation
    await foundation.devices.revoke(request.deviceId)
    foundation.audit.record({ kind: 'device-revoked', deviceId: request.deviceId })
  }

  /**
   * Refresh the caller's bearer token (requires bearer full).
   * @returns new token.
   */
  @Remote('refresh')
  async refresh(): Promise<RefreshResult> {
    const auth = remoteAuthStorage.getStore()
    if (auth === undefined) throw Object.assign(new Error('authentication required'), { code: 'auth-required' })
    if (auth.scope !== 'full') throw Object.assign(new Error('invalid scope'), { code: 'invalid-scope' })
    const foundation = this.foundation
    const device = await foundation.devices.find(auth.sub)
    if (device === undefined) throw Object.assign(new Error('unknown device'), { code: 'unknown-device' })
    if (device.revoked) throw Object.assign(new Error('revoked device'), { code: 'revoked-device' })
    const now = Date.now()
    const ttlMs = 90 * 24 * 60 * 60 * 1000
    const deviceToken = foundation.tokenService.mint({ deviceId: auth.sub, ttlMs, now: () => now })
    const payload = await foundation.tokenService.verify(deviceToken, { now: () => now })
    await foundation.devices.update(auth.sub, current => ({
      ...current,
      lastSeenAt: now,
      lastJti: payload.jti,
      tokenExpiresAt: payload.exp * 1000,
      tokenIssuedAt: payload.iat * 1000,
    }))
    return { deviceToken, expiresAt: payload.exp * 1000 }
  }

  /**
   * Mint a short-lived WebSocket ticket (requires bearer full).
   * @returns ticket.
   */
  @Remote('ws-ticket')
  async wsTicket(): Promise<WsTicketResult> {
    const auth = remoteAuthStorage.getStore()
    if (auth === undefined) throw Object.assign(new Error('authentication required'), { code: 'auth-required' })
    if (auth.scope !== 'full') throw Object.assign(new Error('invalid scope'), { code: 'invalid-scope' })
    const foundation = this.foundation
    const device = await foundation.devices.find(auth.sub)
    if (device === undefined) throw Object.assign(new Error('unknown device'), { code: 'unknown-device' })
    if (device.revoked) throw Object.assign(new Error('revoked device'), { code: 'revoked-device' })
    const now = Date.now()
    const ticket = foundation.tokenService.mintWsTicket(auth.sub, 60_000, () => now)
    const payload = await foundation.tokenService.verifyWsTicket(ticket, { now: () => now })
    return { ticket, expiresAt: payload.exp * 1000 }
  }
}

export default RemoteAccessService
