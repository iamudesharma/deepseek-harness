/**
 * Development-only notification provider for local verification (Phase 10A).
 *
 * Records deliveries in memory without claiming a real push was delivered.
 * Labeled `development` so tests can assert no fake success in production.
 *
 * @module @deepseek-ai/dsh-host-remote-notifications/development-provider
 */

import type { DeliveryResult, NotificationPayload } from './types.ts'
import type { PushTarget, RemoteNotificationProvider } from './provider.ts'

/** One recorded delivery. */
export interface RecordedDelivery {
  /** Target device id. */
  readonly deviceId: string
  /** Platform. */
  readonly platform: 'android' | 'ios'
  /** Category of the notification. */
  readonly category: string
  /** Session id. */
  readonly sessionId: string
  /** Deterministic notification id. */
  readonly notificationId: string
  /** Timestamp from the payload. */
  readonly timestamp: number
}

/**
 * Development notification provider.
 *
 * Stores deliveries in `records` for test assertions; `send` always returns
 * `{ ok: true, message: 'development-recorded' }` without contacting FCM/APNs.
 */
export class DevelopmentNotificationProvider implements RemoteNotificationProvider {
  readonly kind = 'development' as const
  private readonly _records: RecordedDelivery[] = []

  /** Recorded deliveries (copy). */
  get records(): readonly RecordedDelivery[] {
    return [...this._records]
  }

  /** Clear recorded deliveries (test helper). */
  clear(): void {
    this._records.length = 0
  }

  async send(target: PushTarget, payload: NotificationPayload): Promise<DeliveryResult> {
    this._records.push({
      deviceId: target.deviceId,
      platform: target.platform,
      category: payload.category,
      sessionId: payload.sessionId,
      notificationId: payload.notificationId,
      timestamp: payload.timestamp,
    })
    return { ok: true, message: 'development-recorded' }
  }
}
