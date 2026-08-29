/**
 * Host authentication boundary for remote bearer transport.
 * @module @deepseek-ai/dsh-host-remote-access/auth-middleware
 */

import { AsyncLocalStorage } from 'node:async_hooks'
import type { IncomingHttpHeaders } from 'node:http'
import type { DeviceRegistry } from './device-registry.ts'
import { TokenService, TokenError } from './token-service.ts'
import type { HostIdentity } from './host-identity.ts'
import { AuditLog } from './audit.ts'
import type { TokenPayload } from './token-service.ts'

/** ALS carrying the verified bearer payload for the current Typert invocation. */
export const remoteAuthStorage = new AsyncLocalStorage<TokenPayload>()

/** Authority resolved for one request. */
export type RequestAuthority =
  | { kind: 'loopback' }
  | { kind: 'trusted-host' }
  | { kind: 'bearer'; deviceId: string; scope: string; jti: string }
  | { kind: 'pairing' }

/** HTTP-like request facts the middleware reads. */
export interface AuthRequest {
  readonly headers: IncomingHttpHeaders | Headers
  readonly url?: string
}

/** Pairing endpoint that is intentionally unauthenticated. */
const PAIR_ENDPOINT = 'remote/pair'

function bearerToken(headers: IncomingHttpHeaders | Headers): string | undefined {
  const raw = headers instanceof Headers
    ? headers.get('authorization') ?? headers.get('Authorization') ?? undefined
    : (headers['authorization'] as string | undefined)
  if (raw === undefined) return undefined
  const match = /^Bearer\s+(\S+)$/i.exec(raw.trim())
  return match?.[1]
}

/**
 * Authenticate one RemoteTarget HTTP request.
 * Order: pairing endpoint (no auth) → Bearer token verification → missing token.
 * Local loopback authority is preserved via the existing trust fence; this
 * middleware only handles the remote bearer path (no weakening).
 * @param request - request headers + url.
 * @param endpoint - wire endpoint like 'session.list' or 'remote.pair'.
 * @param hostIdentity - host identity.
 * @param tokenService - token verifier.
 * @param devices - device registry.
 * @param audit - audit sink (redacted).
 * @returns authority or throws with 401/403.
 * @throws {AuthError} with status 401 or 403.
 */
export async function authenticateRequest(
  request: AuthRequest,
  endpoint: string,
  hostIdentity: HostIdentity,
  tokenService: TokenService,
  devices: DeviceRegistry,
  audit: AuditLog,
): Promise<RequestAuthority> {
  if (endpoint === PAIR_ENDPOINT) {
    return { kind: 'pairing' }
  }
  const token = bearerToken(request.headers)
  if (token !== undefined) {
    try {
      const payload = await tokenService.verify(token, {
        requiredScope: 'full',
        deviceLookup: async (deviceId) => {
          const device = await devices.find(deviceId)
          return device === undefined ? undefined : { revoked: device.revoked }
        },
      })
      // Update lastSeen opportunistically (best-effort, not blocking auth).
      void devices.update(payload.sub, current => ({ ...current, lastSeenAt: Date.now(), lastJti: payload.jti }))
        .catch(() => {})
      audit.record({ kind: 'device-authenticated', deviceId: payload.sub, hostId: hostIdentity.hostId })
      return { kind: 'bearer', deviceId: payload.sub, scope: payload.scope, jti: payload.jti }
    } catch (error) {
      const code = (error as TokenError)?.code
      const at = Date.now()
      audit.record({ kind: 'auth-failure', at, detail: String(code ?? 'unknown') })
      if (code === 'token-scope-mismatch') {
        throw new AuthError(403, 'invalid scope', code)
      }
      if (code === 'token-malformed' || code === 'token-signature-invalid'
        || code === 'token-host-mismatch' || code === 'token-audience-mismatch') {
        throw new AuthError(401, 'malformed token', code)
      }
      if (code === 'token-expired') throw new AuthError(401, 'expired token', code)
      if (code === 'token-revoked') throw new AuthError(401, 'revoked device', code)
      if (code === 'token-unknown-device') throw new AuthError(401, 'unknown device', code)
      throw new AuthError(401, 'invalid token', code ?? 'unknown')
    }
  }
  // No bearer → missing token (remote path). Local loopback path is handled by
  // the existing trust fence (isTrustedApiRequest) before this middleware for
  // loopback requests, so we do not weaken it.
  throw new AuthError(401, 'missing token', 'missing-token')
}

/**
 * HTTP-authenticated error with explicit status.
 */
export class AuthError extends Error {
  /** HTTP status. */
  readonly status: 401 | 403
  /** Token code for diagnostics (redacted). */
  readonly tokenCode: string | undefined

  /**
   * @param status - 401 or 403.
   * @param message - short reason.
   * @param tokenCode - underlying token/pairing code.
   */
  constructor(status: 401 | 403, message: string, tokenCode?: string) {
    super(message)
    this.name = 'AuthError'
    this.status = status
    this.tokenCode = tokenCode
  }
}

/**
 * Validate a WS ticket (scope ws, single-use).
 */
export class WsTicketStore {
  private readonly used = new Set<string>()
  private readonly issued = new Map<string, { payload: Awaited<ReturnType<TokenService['verify']>>; expiresAt: number }>()

  /**
   * Validate one WS ticket query value (raw ticket string).
   * @param ticket - ticket from ?ticket=.
   * @param tokenService - verifier.
   * @param devices - registry.
   * @returns payload when valid, throws AuthError (401/403) otherwise.
   */
  async validate(
    ticket: string | undefined,
    tokenService: TokenService,
    devices: DeviceRegistry,
    audit: AuditLog,
  ): Promise<{ deviceId: string; scope: string }> {
    if (ticket === undefined || ticket === '') {
      audit.record({ kind: 'auth-failure', detail: 'ws-missing-ticket' })
      throw new AuthError(401, 'missing ticket', 'ws-missing-ticket')
    }
    if (this.used.has(ticket)) {
      audit.record({ kind: 'auth-failure', detail: 'ws-replayed-ticket' })
      throw new AuthError(401, 'replayed ticket', 'ws-replayed')
    }
    try {
      const payload = await tokenService.verifyWsTicket(ticket, {
        deviceLookup: async (deviceId) => {
          const device = await devices.find(deviceId)
          return device === undefined ? undefined : { revoked: device.revoked }
        },
      })
      this.used.add(ticket)
      // Single-use: remember but do not allow second use.
      return { deviceId: payload.sub, scope: payload.scope }
    } catch (error) {
      const code = (error as TokenError)?.code
      if (code === 'token-expired') throw new AuthError(401, 'expired ticket', code)
      if (code === 'token-scope-mismatch') throw new AuthError(403, 'invalid ticket scope', code)
      if (code === 'token-revoked' || code === 'token-unknown-device') throw new AuthError(401, String(code), code)
      if (code === 'token-host-mismatch' || code === 'token-audience-mismatch'
        || code === 'token-signature-invalid' || code === 'token-malformed') {
        throw new AuthError(401, String(code), code)
      }
      throw new AuthError(401, 'invalid ticket', code ?? 'unknown')
    }
  }

  /** Clear used set (test seam). */
  clear(): void {
    this.used.clear()
    this.issued.clear()
  }
}

/**
 * Extract ticket from a request URL (?ticket=).
 * Never logs the value — caller must redact.
 * @param url - request url like '/api/events.mux?ticket=...'
 * @returns ticket when present.
 */
export function ticketFromUrl(url: string | undefined): string | undefined {
  if (url === undefined) return undefined
  try {
    const parsed = new URL(url, 'http://x')
    const ticket = parsed.searchParams.get('ticket')
    return ticket === null ? undefined : ticket
  } catch {
    return undefined
  }
}

/**
 * Redact Authorization header and ticket query for logging.
 * @param headers - request headers.
 * @param url - request url.
 * @returns redacted copy for audit.
 */
export function redactedLogContext(
  headers: IncomingHttpHeaders | Headers,
  url?: string,
): { headers: Record<string, string>; url?: string } {
  const out: Record<string, string> = {}
  const entries = headers instanceof Headers
    ? [...headers.entries()]
    : Object.entries(headers as Record<string, unknown>).filter(([, v]) => typeof v === 'string') as [string, string][]
  for (const [key, value] of entries) {
    if (key.toLowerCase() === 'authorization') out[key] = '[REDACTED]'
    else out[key] = value
  }
  let redactedUrl: string | undefined = url
  if (url !== undefined) {
    try {
      const parsed = new URL(url, 'http://x')
      if (parsed.searchParams.has('ticket')) {
        parsed.searchParams.set('ticket', '[REDACTED]')
        redactedUrl = `${parsed.pathname}?${parsed.searchParams.toString()}${parsed.hash}`
      }
    } catch {}
  }
  return { ...(redactedUrl === undefined ? {} : { url: redactedUrl }), headers: out }
}
