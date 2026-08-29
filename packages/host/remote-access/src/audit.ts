/**
 * Remote-access audit events (redacted, no tokens).
 * @module @deepseek-ai/dsh-host-remote-access/audit
 */

/** Auditable remote event kinds. */
export type AuditEventKind =
  | 'pair-requested'
  | 'pair-approved'
  | 'pair-denied'
  | 'device-authenticated'
  | 'device-revoked'
  | 'device-push-registered'
  | 'device-push-unregistered'
  | 'auth-failure'
  | 'rpc-denied'
  | 'connection-opened'
  | 'connection-closed'

/** Redacted audit event payload (never contains tokens). */
export interface AuditEvent {
  readonly kind: AuditEventKind
  readonly at: number
  readonly deviceId?: string
  readonly hostId?: string
  readonly detail?: string
}

/**
 * Audit sink: host-side events for remote access.
 * In-memory ring; Phase 2 logs via ctx.logger with redaction.
 */
export class AuditLog {
  private readonly events: AuditEvent[] = []
  private readonly max = 200

  /**
   * Record an event (redacted).
   * @param event - audit event without token material.
   */
  record(event: Omit<AuditEvent, 'at'> & { at?: number }): void {
    const entry: AuditEvent = { ...event, at: event.at ?? Date.now() }
    // Never log bearer tokens, WS tickets, private keys, full Authorization headers, credential values.
    // This sink stores only the redacted entry; callers must not pass token strings.
    if (this.events.length >= this.max) this.events.shift()
    this.events.push(entry)
  }

  /** Recent events (copy). */
  recent(): readonly AuditEvent[] {
    return [...this.events]
  }

  /** Clear (test seam). */
  clear(): void {
    this.events.length = 0
  }
}
