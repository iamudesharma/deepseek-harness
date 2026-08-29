/**
 * Push provider abstraction for Phase 10A.
 *
 * Session runtime emits a semantic {@link NotificationPayload}; the provider
 * handles transport. No bearer or push credentials enter the payload.
 *
 * @module @deepseek-ai/dsh-host-remote-notifications/provider
 */

import type { DeliveryResult, NotificationPayload } from './types.ts'

/**
 * Target device for a push send.
 */
export interface PushTarget {
  /** Device id (matches `NotificationPayload.deviceId`). */
  readonly deviceId: string
  /** Platform determines APNs vs FCM. */
  readonly platform: 'android' | 'ios'
  /** Opaque push token (never logged in full). */
  readonly pushToken: string
}

/**
 * Host-side notification provider.
 *
 * Each implementation (FCM, APNs, development) owns one `kind` and implements
 * `send` idempotently; dispatcher remains transport-agnostic.
 */
export interface RemoteNotificationProvider {
  /** Provider kind for diagnostics and tests. */
  readonly kind: 'development' | 'fcm' | 'apns'

  /**
   * Attempt to deliver one notification to one target.
   *
   * Must not throw for provider-side failure; return `{ ok: false }` instead
   * so the dispatcher can retry or record. Throwing is reserved for
   * programming errors.
   *
   * @param target - device and push token.
   * @param payload - privacy-first payload (no bearer/push credentials).
   * @returns delivery result.
   */
  send(target: PushTarget, payload: NotificationPayload): Promise<DeliveryResult>
}
