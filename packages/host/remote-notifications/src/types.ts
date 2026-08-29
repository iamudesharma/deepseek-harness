/**
 * Client-safe types for the remote-notifications domain (Phase 10A).
 *
 * Typert will generate strict codecs for these; they contain no Node or Cordis
 * imports.
 *
 * @module @deepseek-ai/dsh-host-remote-notifications/types
 */

/** Allowed push notification categories (v1). */
export type NotificationCategory =
  | 'turn.completed'
  | 'turn.failed'
  | 'approval.required'
  | 'question.required'

/** Notification payload delivered via push (privacy-first: opaque ids only). */
export interface NotificationPayload {
  /** Stable host id (sha256 SPKI, base64url). */
  readonly hostId: string
  /** Target device id (must equal auth.sub). */
  readonly deviceId: string
  /** Session that triggered the notification. */
  readonly sessionId: string
  /** Category of the triggering event. */
  readonly category: NotificationCategory
  /** Deterministic notification identifier for idempotency. */
  readonly notificationId: string
  /** Epoch milliseconds when the host created the notification. */
  readonly timestamp: number
  /** Secure deep link for the client (`dsh://session/<hostId>/<sessionId>`). */
  readonly deepLink: string
}

/** Semantic request the dispatcher emits (host-side only, not wire). */
export interface NotificationRequest {
  /** Session id that owns the event. */
  readonly sessionId: string
  /** Category derived from the authoritative trigger. */
  readonly category: NotificationCategory
  /** Deterministic trigger identity for id derivation. */
  readonly triggerId: string
  /** Authoritative sequence or rpcId-derived identity. */
  readonly triggerSeq?: number
  /** Timestamp for payload ordering. */
  readonly timestamp: number
}

/** Register push token request. */
export interface PushRegisterRequest {
  /** Device to register (must equal auth.sub). */
  readonly deviceId: string
  /** Target platform. */
  readonly platform: 'android' | 'ios'
  /** Opaque push token (FCM or APNs). */
  readonly pushToken: string
  /** Client app version. */
  readonly appVersion: string
}

/** Register push token result. */
export interface PushRegisterResult {
  /** Whether the registration was stored. */
  readonly ok: true
}

/** Unregister push token request. */
export interface PushUnregisterRequest {
  /** Device to unregister (must equal auth.sub). */
  readonly deviceId: string
}

/** Unregister result. */
export interface PushUnregisterResult {
  /** Whether the registration was removed. */
  readonly ok: true
}

/** Delivery result from a provider. */
export interface DeliveryResult {
  /** Whether the provider accepted the send. */
  readonly ok: boolean
  /** Provider-specific message (never contains pushToken). */
  readonly message?: string
}
