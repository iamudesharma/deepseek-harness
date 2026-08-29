/**
 * @deepseek-ai/dsh-host-remote-notifications — Remote push notification foundation (Phase 10A).
 *
 * Exposes `remote.notifications.register|unregister` over the existing authenticated
 * remote channel. The desktop host remains execution authority; push is auxiliary
 * wake-up. The dispatcher, FCM/APNs providers and foreground-suppression live in
 * later phases; this package establishes the privacy-first payload contract,
 * deterministic notification ids, device push storage, and the authenticated API.
 *
 * Device private key → pairing identity
 * Device access token → authenticated API credential (bearer)
 * Push token          → auxiliary wake-up credential (stored 0600, never in payload)
 *
 * @module @deepseek-ai/dsh-host-remote-notifications
 */

import { Context, Service } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { RemoteNotificationsService } from './remote-notifications-service.ts'

export type {
  NotificationPayload,
  NotificationRequest,
  NotificationCategory,
  PushRegisterRequest,
  PushRegisterResult,
  PushUnregisterRequest,
  PushUnregisterResult,
  DeliveryResult,
} from './types.ts'
export { deriveNotificationId, buildDeepLink } from './notification-id.ts'
export type { RemoteNotificationProvider, PushTarget } from './provider.ts'
export { DevelopmentNotificationProvider } from './development-provider.ts'
export type { RecordedDelivery } from './development-provider.ts'
export { RemoteNotificationsService } from './remote-notifications-service.ts'

declare module '@deepseek-ai/cordis' {
  interface Context {
    /** Remote-notifications foundation (`ctx.remoteNotificationsFoundation`). */
    remoteNotificationsFoundation: RemoteNotificationsFoundation
  }
}

/**
 * Plugin config: enabled when remote access is enabled (default false).
 */
export interface Config {
  /** Whether remote notifications are enabled (requires remote-access enabled). */
  enabled?: boolean
}

/**
 * Foundation service: mounts the authenticated `remote.notifications` API.
 */
export class RemoteNotificationsFoundation extends Service {
  static inject = ['remoteAccessFoundation']
  static Config: z<Config> = z.object({
    enabled: z.boolean().default(false),
  })

  constructor(ctx: Context, private readonly config: Config) {
    super(ctx, 'remoteNotificationsFoundation')
  }

  async [Service.init](): Promise<void> {
    // Mount the Typert remote service under `remote.notifications`.
    this.ctx.plugin(RemoteNotificationsService)
    if (this.config.enabled === true) {
      this.ctx.logger.info('remote-notifications: enabled (remote.notifications.register active)')
    } else {
      this.ctx.logger.info('remote-notifications: ready (enabled=false)')
    }
  }

  /** Whether notifications are enabled. */
  get isEnabled(): boolean {
    return this.config.enabled === true
  }
}

export default RemoteNotificationsFoundation
