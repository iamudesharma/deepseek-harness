# @deepseek-ai/dsh-host-remote-notifications

English | [中文](README.zh.md)

Remote push notification foundations for mobile wake-ups (Phase 10A). Provides the privacy-first payload contract, deterministic notification-id derivation, single-registry push-token storage, the authenticated `remote.notifications.register|unregister` API, and the `RemoteNotificationProvider` abstraction (development + `fcm`/`apns` seams). The desktop host remains execution authority; push is an auxiliary wake-up, not a second session-state system. No WebSocket is kept alive in the mobile background.

## Payload contract

`NotificationPayload` carries only opaque identifiers: `hostId`, `deviceId`, `sessionId`, `category` (`turn.completed|turn.failed|approval.required|question.required`), `notificationId`, `timestamp`, `deepLink` (`dsh://session/<hostId>/<sessionId>?category=&notificationId=`). No bearer token, push token, API key, prompt text, assistant text, tool output, or filesystem paths. `NotificationRequest` is the host-side semantic trigger (session + category + triggerId).

## Deterministic notification id

`deriveNotificationId(hostId, sessionId, category, triggerId)` = `hex(sha256(hostId|sessionId|category|triggerId))` truncated to 32 hex chars. Uses the authoritative trigger identity: `seq` for `turn/end`, `approvalId` for approval, `rpcId` for question. Same event processed twice yields the same id without using message text.

## Device push registration

Reuses the single `$DSH_HOME/remote/devices.json` (`0600`, dirs `0700`, `withFileLock` RMW + `writeFileAtomic`). `DeviceRecord.pushRegistration?: { platform: android|ios, pushToken, appVersion, registeredAt, updatedAt }`. `DeviceRegistry.registerPush`/`unregisterPush` are atomic. Revoke (`revoke`/`revokeAll`) clears `pushRegistration` so a revoked device stops future deliveries. `remote.devices` never exposes `pushToken`; push tokens are only in the on-disk file.

## Remote API contract

`src/remote-notifications-service.ts` declares `remote.notifications.register|unregister` as `@Remote` methods on `RemoteNotificationsService` (`namespace: remote.notifications`). Both require bearer `full` auth and `auth.sub == deviceId`, validate `deviceId` (UUID v4), `platform` (`android|ios`), `pushToken` (non-empty, ≤4096), and `appVersion`. Unknown or revoked devices are rejected. Generation via `tsdown --env.DSH_BUILD_FACE host` produces `lib/typert.host.*` + `lib/typert.remote-client.*`; Flutter uses `POST /api/remote.notifications/*` over the existing authenticated channel.

## Provider interface

```ts
interface RemoteNotificationProvider {
  readonly kind: 'development' | 'fcm' | 'apns'
  send(target: { deviceId, platform, pushToken }, payload: NotificationPayload): Promise<DeliveryResult>
}
```

`DevelopmentNotificationProvider` records `{ deviceId, platform, category, sessionId, notificationId, timestamp }` in memory and returns `development-recorded` without contacting FCM/APNs. Production providers return `{ ok, message }`; dispatcher remains transport-agnostic.

## Model Experience

None — notifications move no model-visible content and own no prompt.

#### KV Cache effect

None — no provider request is assembled.

## Known Limitations and Deferred Work

- **No dispatcher yet** — eligibility (running→completed/error, approval/question pending), foreground-suppression, deduplication by `notificationId`, and provider retry live in a later phase; this package only stores registrations and defines the send seam.
- **FCM/APNs not wired** — `fcm`/`apns` providers are interface stubs; delivery for local verification uses the development provider.
- **No host-unavailable notifications** — only `turn.completed|turn.failed|approval.required|question.required` are defined; host unavailable/reconnected is deferred pending product value.
