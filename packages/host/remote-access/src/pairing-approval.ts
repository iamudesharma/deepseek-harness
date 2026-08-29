/**
 * Host-side device approval for pairing.
 * @module @deepseek-ai/dsh-host-remote-access/pairing-approval
 */

import type { PairRequest } from './types.ts'

/** One pending pairing awaiting host approval. */
export interface PendingPairing {
  readonly nonce: string
  readonly request: PairRequest
  readonly requestedAt: number
  /** Resolve when host approves/denies. */
  readonly promise: Promise<'approved' | 'denied'>
  /** Host-side approve/deny (called by approval UI/CLI). */
  approve(): void
  deny(): void
}

/**
 * Host approval store: explicit operator approval required (no auto-approve).
 * Reuses harness command/interaction infrastructure where possible — here as
 * an in-process promise-based approval that the CLI can prompt for and the
 * integration test can drive directly.
 */
export class PairingApprovalStore {
  private readonly pending = new Map<string, PendingPairing & { _resolve: (value: 'approved' | 'denied') => void }>()

  /**
   * Request host approval for a pairing. Returns a handle whose promise settles
   * when the host approves/denies.
   * @param request - device pairing request.
   * @param nonce - consumed nonce (key).
   * @returns pending pairing.
   */
  request(request: PairRequest, nonce: string): PendingPairing {
    if (this.pending.has(nonce)) throw new Error('pairing-approval: duplicate pending nonce')
    let resolve!: (value: 'approved' | 'denied') => void
    const promise = new Promise<'approved' | 'denied'>((res) => { resolve = res })
    const entry = {
      nonce,
      request,
      requestedAt: Date.now(),
      promise,
      _resolve: resolve,
      approve: () => { resolve('approved'); this.pending.delete(nonce) },
      deny: () => { resolve('denied'); this.pending.delete(nonce) },
    }
    this.pending.set(nonce, entry)
    return entry
  }

  /** Find a pending pairing by nonce. */
  get(nonce: string): PendingPairing | undefined {
    return this.pending.get(nonce)
  }

  /** All pending (for host UI listing). */
  list(): readonly PendingPairing[] {
    return [...this.pending.values()]
  }

  /** Approve a pending pairing (host UI/CLI). */
  approve(nonce: string): boolean {
    const entry = this.pending.get(nonce)
    if (entry === undefined) return false
    entry.approve()
    return true
  }

  /** Deny a pending pairing. */
  deny(nonce: string): boolean {
    const entry = this.pending.get(nonce)
    if (entry === undefined) return false
    entry.deny()
    return true
  }

  /** Clear (test seam). */
  clear(): void {
    this.pending.clear()
  }
}
