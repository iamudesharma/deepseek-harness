/**
 * Authenticated `remote.notifications.*` Typert service (Phase 10A).
 *
 * Canonical register/unregister over the existing bearer channel, reusing the
 * remote-access foundation's device registry (single `devices.json`) and auth
 * middleware. No second device database.
 *
 * @module @deepseek-ai/dsh-host-remote-notifications/remote-notifications-service
 */

import { Context } from '@deepseek-ai/cordis'
import { TypertRemoteService, Remote } from '@deepseek-ai/dsh-typert-protocol'
import type {
  PushRegisterRequest,
  PushRegisterResult,
  PushUnregisterRequest,
  PushUnregisterResult,
} from './types.ts'
import { remoteAuthStorage } from '@deepseek-ai/dsh-host-remote-access'
import { isValidDeviceId } from '@deepseek-ai/dsh-host-remote-access'

declare module '@deepseek-ai/cordis' {
  interface Context {
    /** Remote notifications service (`ctx.remoteNotifications`). */
    remoteNotifications: RemoteNotificationsService
  }
}

/**
 * Remote notifications service: push registration lifecycle.
 */
export class RemoteNotificationsService extends TypertRemoteService {
  static inject = ['remoteAccessFoundation']

  constructor(ctx: Context) {
    super(ctx, 'remoteNotifications', { namespace: 'remote.notifications' })
  }

  private get foundation(): import('@deepseek-ai/dsh-host-remote-access').RemoteAccessFoundation {
    const found = (this.ctx as unknown as { remoteAccessFoundation?: import('@deepseek-ai/dsh-host-remote-access').RemoteAccessFoundation })
      .remoteAccessFoundation
    if (found === undefined) throw new Error('remote-notifications: foundation not available')
    return found
  }

  /**
   * Register or refresh a push token for the authenticated device.
   * @param request - device, platform, token, app version.
   * @returns ok when stored.
   */
  @Remote('register')
  async register(request: PushRegisterRequest): Promise<PushRegisterResult> {
    const auth = remoteAuthStorage.getStore()
    if (auth === undefined) throw Object.assign(new Error('authentication required'), { code: 'auth-required' })
    if (auth.scope !== 'full') throw Object.assign(new Error('invalid scope'), { code: 'invalid-scope' })
    if (!isValidDeviceId(request.deviceId)) throw Object.assign(new Error('invalid deviceId'), { code: 'invalid-device' })
    if (auth.sub !== request.deviceId) throw Object.assign(new Error('deviceId must match authenticated device'), { code: 'device-mismatch' })
    if (request.platform !== 'android' && request.platform !== 'ios') {
      throw Object.assign(new Error('platform must be android or ios'), { code: 'invalid-platform' })
    }
    if (typeof request.pushToken !== 'string' || request.pushToken.length === 0 || request.pushToken.length > 4096) {
      throw Object.assign(new Error('pushToken must be non-empty'), { code: 'invalid-token' })
    }
    if (typeof request.appVersion !== 'string' || request.appVersion.length === 0) {
      throw Object.assign(new Error('appVersion must be non-empty'), { code: 'invalid-appVersion' })
    }
    const device = await this.foundation.devices.find(request.deviceId)
    if (device === undefined) throw Object.assign(new Error('unknown device'), { code: 'unknown-device' })
    if (device.revoked) throw Object.assign(new Error('revoked device'), { code: 'revoked-device' })

    await this.foundation.devices.registerPush(request.deviceId, {
      platform: request.platform,
      pushToken: request.pushToken,
      appVersion: request.appVersion,
    })

    this.foundation.audit.record({ kind: 'device-push-registered', deviceId: request.deviceId })
    return { ok: true }
  }

  /**
   * Remove push registration for the authenticated device.
   * @param request - device to unregister.
   * @returns ok when removed (idempotent when absent).
   */
  @Remote('unregister')
  async unregister(request: PushUnregisterRequest): Promise<PushUnregisterResult> {
    const auth = remoteAuthStorage.getStore()
    if (auth === undefined) throw Object.assign(new Error('authentication required'), { code: 'auth-required' })
    if (auth.scope !== 'full') throw Object.assign(new Error('invalid scope'), { code: 'invalid-scope' })
    if (!isValidDeviceId(request.deviceId)) throw Object.assign(new Error('invalid deviceId'), { code: 'invalid-device' })
    if (auth.sub !== request.deviceId) throw Object.assign(new Error('deviceId must match authenticated device'), { code: 'device-mismatch' })

    const device = await this.foundation.devices.find(request.deviceId)
    if (device === undefined) throw Object.assign(new Error('unknown device'), { code: 'unknown-device' })

    // Idempotent: no-op when already absent.
    if (device.pushRegistration !== undefined) {
      await this.foundation.devices.unregisterPush(request.deviceId)
      this.foundation.audit.record({ kind: 'device-push-unregistered', deviceId: request.deviceId })
    }
    return { ok: true }
  }
}

export default RemoteNotificationsService
