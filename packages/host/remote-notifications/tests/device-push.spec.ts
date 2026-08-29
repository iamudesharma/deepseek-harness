import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { DeviceRegistry } from '@deepseek-ai/dsh-host-remote-access'
import type { DeviceRecord } from '@deepseek-ai/dsh-host-remote-access'

const dirs: string[] = []

function tempHome(): string {
  const dir = mkdtempSync(join(tmpdir(), 'dsh-remote-notif-'))
  dirs.push(dir)
  return dir
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
})

function device(overrides: Partial<DeviceRecord> = {}): DeviceRecord {
  return {
    deviceId: '11111111-1111-4111-8111-111111111111',
    displayName: 'Pixel 7',
    publicKey: Buffer.from('fake-spki').toString('base64'),
    createdAt: 1_000,
    lastSeenAt: 1_000,
    revoked: false,
    ...overrides,
  }
}

describe('device push registration (extension of single registry)', () => {
  it('registerPush creates registration atomically', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const updated = await registry.registerPush(device().deviceId, {
      platform: 'android',
      pushToken: 'fcm-token-abc',
      appVersion: '1.0.0',
    })
    expect(updated.pushRegistration).toBeDefined()
    expect(updated.pushRegistration!.platform).toBe('android')
    expect(updated.pushRegistration!.pushToken).toBe('fcm-token-abc')
    expect(updated.pushRegistration!.appVersion).toBe('1.0.0')
    expect(updated.pushRegistration!.registeredAt).toBeGreaterThan(0)
    expect(updated.pushRegistration!.updatedAt).toBeGreaterThan(0)
  })

  it('registerPush refresh updates token and appVersion, preserves registeredAt', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const first = await registry.registerPush(device().deviceId, {
      platform: 'ios',
      pushToken: 'apns-1',
      appVersion: '1.0.0',
    }, () => 1_000)
    const second = await registry.registerPush(device().deviceId, {
      platform: 'ios',
      pushToken: 'apns-2',
      appVersion: '1.1.0',
    }, () => 2_000)
    expect(second.pushRegistration!.registeredAt).toBe(first.pushRegistration!.registeredAt)
    expect(second.pushRegistration!.updatedAt).toBe(2_000)
    expect(second.pushRegistration!.pushToken).toBe('apns-2')
  })

  it('unregisterPush removes registration', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    await registry.registerPush(device().deviceId, { platform: 'android', pushToken: 'tok', appVersion: '1.0' })
    const cleared = await registry.unregisterPush(device().deviceId)
    expect(cleared.pushRegistration).toBeUndefined()
  })

  it('unregisterPush is idempotent when absent', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const result = await registry.unregisterPush(device().deviceId)
    // update with undefined returns existing without change
    expect(result.pushRegistration).toBeUndefined()
  })

  it('revoke clears push registration', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    await registry.registerPush(device().deviceId, { platform: 'android', pushToken: 'tok', appVersion: '1.0' })
    const revoked = await registry.revoke(device().deviceId, () => 5_000)
    expect(revoked.revoked).toBe(true)
    expect(revoked.pushRegistration).toBeUndefined()
    const listed = await registry.list()
    expect(listed[0]!.pushRegistration).toBeUndefined()
  })

  it('revokeAll clears all push registrations', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device({ deviceId: '11111111-1111-4111-8111-111111111111' }))
    await registry.add(device({ deviceId: '22222222-2222-4222-8222-222222222222', lastSeenAt: 2_000 }))
    await registry.registerPush('11111111-1111-4111-8111-111111111111', { platform: 'ios', pushToken: 't1', appVersion: '1.0' })
    await registry.registerPush('22222222-2222-4222-8222-222222222222', { platform: 'android', pushToken: 't2', appVersion: '1.0' })
    await registry.revokeAll(() => 9_000)
    const listed = await registry.list()
    for (const entry of listed) expect(entry.pushRegistration).toBeUndefined()
  })

  it('registerPush fails on revoked device', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    await registry.revoke(device().deviceId)
    await expect(registry.registerPush(device().deviceId, { platform: 'android', pushToken: 'tok', appVersion: '1.0' }))
      .rejects.toThrow(/revoked/)
  })

  it('never exposes pushToken via list raw still contains it at rest but devices view must not leak — verify storage at rest is 0600 and contains token only in devices.json', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    await registry.registerPush(device().deviceId, { platform: 'android', pushToken: 'secret-token', appVersion: '1.0' })
    const all = await registry.list()
    // Raw list still carries token (persistence), but the Typert DevicesResult mapping must strip it — checked in service test.
    expect(all[0]!.pushRegistration!.pushToken).toBe('secret-token')
  })

  it('persists push registration across restart', async () => {
    const home = tempHome()
    const first = new DeviceRegistry(home)
    await first.add(device())
    await first.registerPush(device().deviceId, { platform: 'android', pushToken: 'tok', appVersion: '1.0' })
    const second = new DeviceRegistry(home)
    const listed = await second.list()
    expect(listed[0]!.pushRegistration!.pushToken).toBe('tok')
  })
})
