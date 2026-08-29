/**
 * @deepseek-ai/dsh-host-remote-access — Secure host identity and remote-access foundation (Phase 2: auth transport).
 *
 * Provides host identity, device registry, pairing, tokens, explicit host
 * approval, TLS cert, audit, and the authentication boundary that Phase 2
 * enforces before any remote listener is enabled. Default remains
 * loopback-only; `dsh web --remote` opts into authenticated remote access.
 *
 * Device private key  → pairing identity / future PoP capability
 * Device access token → current authenticated API credential (bearer)
 *
 * @module @deepseek-ai/dsh-host-remote-access
 */

import { Context, Service } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'

import { DeviceRegistry } from './device-registry.ts'
import { loadOrCreateHostIdentity, type HostIdentity } from './host-identity.ts'
import { PairingStore } from './pairing-store.ts'
import { PairingApprovalStore } from './pairing-approval.ts'
import { TokenService } from './token-service.ts'
import { RemoteAccessService } from './remote-service.ts'
import { AuditLog } from './audit.ts'
import { WsTicketStore } from './auth-middleware.ts'
import { ensureHostCertificate } from './tls.ts'

export type { HostIdentity } from './host-identity.ts'
export { loadOrCreateHostIdentity, loadHostIdentity, hostIdOf } from './host-identity.ts'
export type { DeviceRecord, PushRegistration } from './device-registry.ts'
export { DeviceRegistry, isValidDeviceId, generateDeviceId } from './device-registry.ts'
export { PairingStore, PairingError } from './pairing-store.ts'
export type { PairingEntry, CreatePairingOptions, ConsumePairingOptions } from './pairing-store.ts'
export { PairingApprovalStore } from './pairing-approval.ts'
export type { PendingPairing } from './pairing-approval.ts'
export { TokenService, TokenError } from './token-service.ts'
export type { TokenPayload, MintTokenOptions, VerifyTokenOptions } from './token-service.ts'
export { RemoteAccessService } from './remote-service.ts'
export { AuditLog } from './audit.ts'
export type { AuditEvent, AuditEventKind } from './audit.ts'
export { WsTicketStore, remoteAuthStorage, ticketFromUrl, redactedLogContext, authenticateRequest, AuthError } from './auth-middleware.ts'
export { classifyRemoteMethod, isRemoteAuthorized } from './privileged-policy.ts'
export { ensureHostCertificate, certFingerprint, hasHostCertificate } from './tls.ts'
export * from './types.ts'
export * from './paths.ts'
export * from './crypto.ts'

declare module '@deepseek-ai/cordis' {
  interface Context {
    /** Remote-access foundation (`ctx.remoteAccessFoundation`). */
    remoteAccessFoundation: RemoteAccessFoundation
  }
}

/**
 * Plugin config: remote-access is disabled unless explicitly enabled via --remote.
 */
export interface Config {
  /** Whether remote access is enabled. */
  enabled?: boolean
}

/**
 * Remote-access foundation service.
 */
export class RemoteAccessFoundation extends Service {
  static Config: z<Config> = z.object({
    enabled: z.boolean().default(false),
  })

  /** Persistent host identity (stable across restarts). */
  hostIdentity!: HostIdentity

  /** Device registry. */
  readonly devices: DeviceRegistry

  /** Pairing nonce/PIN store (in-memory, one-use). */
  readonly pairing: PairingStore

  /** Explicit host approval for pairing. */
  readonly approval: PairingApprovalStore

  /** Audit log (redacted). */
  readonly audit: AuditLog

  /** WS ticket replay store (single-use). */
  readonly wsTickets: WsTicketStore

  /** Token service bound to the host identity (set after identity loads). */
  tokenService!: TokenService

  /** TLS fingerprint when remote enabled. */
  tlsFingerprint?: string

  /** Whether remote access is enabled (explicit opt-in). */
  get isEnabled(): boolean {
    return this.config.enabled === true
  }

  /** Raw config (for describe). */
  get configSnapshot(): Config {
    return { ...this.config }
  }

  constructor(ctx: Context, private readonly config: Config) {
    super(ctx, 'remoteAccessFoundation')
    this.devices = new DeviceRegistry()
    this.pairing = new PairingStore()
    this.approval = new PairingApprovalStore()
    this.audit = new AuditLog()
    this.wsTickets = new WsTicketStore()
  }

  async [Service.init](): Promise<void> {
    this.hostIdentity = await loadOrCreateHostIdentity({})
    this.tokenService = new TokenService(this.hostIdentity)
    this.ctx.plugin(RemoteAccessService)
    if (this.config.enabled === true) {
      try {
        const { fingerprint } = await ensureHostCertificate(this.hostIdentity.hostId)
        this.tlsFingerprint = fingerprint
        this.ctx.logger.info(
          `remote-access: enabled hostId ${this.hostIdentity.hostId.slice(0, 8)}… fingerprint ${fingerprint.slice(0, 8)}… (TLS active)`,
        )
      } catch (error) {
        this.ctx.logger.error('remote-access: TLS certificate generation failed — remote listener will not start')
        this.ctx.logger.error(error)
        throw error
      }
      this.audit.record({ kind: 'connection-opened', detail: 'remote-enabled' })
    } else {
      this.ctx.logger.info(
        `remote-access: hostId ${this.hostIdentity.hostId.slice(0, 8)}… ready (enabled=false, loopback-only)`,
      )
    }
  }
}

export default RemoteAccessFoundation
