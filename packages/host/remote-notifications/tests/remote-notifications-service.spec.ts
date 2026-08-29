import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import { DeviceRegistry } from '@deepseek-ai/dsh-host-remote-access'
import { RemoteNotificationsService } from '../src/remote-notifications-service.ts'
import { remoteAuthStorage } from '@deepseek-ai/dsh-host-remote-access'

// Minimal foundation stub satisfying RemoteNotificationsService injection.
// Reuses the real DeviceRegistry (0600/locked) so auth/revocation semantics stay real.

const dirs: string[] = []
function tempHome(): string {
  const d = mkdtempSync(join(tmpdir(), 'dsh-rn-service-'))
  dirs.push(d)
  return d
}

afterEach(() => {
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true })
})

async function makeService(home: string) {
  const ctx = new Context()
  const devices = new DeviceRegistry(home)
  const foundation = {
    devices,
    audit: { record: () => {} },
  } as unknown as import('@deepseek-ai/dsh-host-remote-access').RemoteAccessFoundation
  // Provide foundation under the key the service injects
  ;(ctx as unknown as Record<string, unknown>)['remoteAccessFoundation'] = foundation
  const service = new RemoteNotificationsService(ctx as unknown as ConstructorParameters<typeof RemoteNotificationsService>[0])
  // Simulate Service lifecycle: normally ctx.plugin would call init, but our service has no init.
  return { service, devices, ctx }
}

function authFor(deviceId: string) {
  return {
    iss: 'test-host-id-1234567890123456789012345678901',
    sub: deviceId,
    aud: 'dsh-remote',
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
    jti: 'test-jti',
    scope: 'full' as const,
  } as unknown as import('@deepseek-ai/dsh-host-remote-access').TokenPayload
}

describe('remote.notifications.register / unregister', () => {
  let home: string

  beforeEach(() => {
    home = tempHome()
  })

  it('register requires authentication', async () => {
    const { service } = await makeService(home)
    await expect(service.register({
      deviceId: '11111111-1111-4111-8111-111111111111',
      platform: 'android',
      pushToken: 'tok',
      appVersion: '1.0.0',
    })).rejects.toThrow(/authentication required/)
  })

  it('register requires deviceId == auth.sub', async () => {
    const { service, devices } = await makeService(home)
    const idA = '11111111-1111-4111-8111-111111111111'
    const idB = '22222222-2222-4222-8222-222222222222'
    await devices.add({
      deviceId: idA,
      displayName: 'A',
      publicKey: Buffer.from('pk').toString('base64'),
      createdAt: 1_000,
      lastSeenAt: 1_000,
      revoked: false,
    })
    await expect(remoteAuthStorage.run(authFor(idB), () =>
      service.register({ deviceId: idA, platform: 'android', pushToken: 'tok', appVersion: '1.0' }),
    )).rejects.toThrow(/must match authenticated device/)
  })

  it('register fails when device unknown', async () => {
    const { service } = await makeService(home)
    const id = '33333333-3333-4333-8333-333333333333'
    await expect(remoteAuthStorage.run(authFor(id), () =>
      service.register({ deviceId: id, platform: 'ios', pushToken: 'tok', appVersion: '1.0' }),
    )).rejects.toThrow(/unknown device/)
  })

  it('register fails when device revoked', async () => {
    const { service, devices } = await makeService(home)
    const id = '44444444-4444-4444-8444-444444444444'
    await devices.add({ deviceId: id, displayName: 'D', publicKey: Buffer.from('k').toString('base64'), createdAt: 1_000, lastSeenAt: 1_000, revoked: false })
    await devices.revoke(id)
    await expect(remoteAuthStorage.run(authFor(id), () =>
      service.register({ deviceId: id, platform: 'android', pushToken: 'tok', appVersion: '1.0' }),
    )).rejects.toThrow(/revoked device/)
  })

  it('register validates platform', async () => {
    const { service, devices } = await makeService(home)
    const id = '55555555-5555-4555-8555-555555555555'
    await devices.add({ deviceId: id, displayName: 'D', publicKey: Buffer.from('k').toString('base64'), createdAt: 1_000, lastSeenAt: 1_000, revoked: false })
    await expect(remoteAuthStorage.run(authFor(id), () =>
      service.register({ deviceId: id, platform: 'web' as unknown as 'android', pushToken: 'tok', appVersion: '1.0' }),
    )).rejects.toThrow(/platform must be android or ios/)
  })

  it('register succeeds and stores push token (not exposed via raw service only via registry)', async () => {
    const { service, devices } = await makeService(home)
    const id = '66666666-6666-4666-8666-666666666666'
    await devices.add({ deviceId: id, displayName: 'D', publicKey: Buffer.from('k').toString('base64'), createdAt: 1_000, lastSeenAt: 1_000, revoked: false })
    const res = await remoteAuthStorage.run(authFor(id), () =>
      service.register({ deviceId: id, platform: 'android', pushToken: 'fcm-abc', appVersion: '2.0.0' }),
    )
    expect(res.ok).toBe(true)
    const stored = await devices.find(id)
    expect(stored!.pushRegistration!.pushToken).toBe('fcm-abc')
    expect(stored!.pushRegistration!.platform).toBe('android')
  })

  it('register is upsertable (same device can refresh token)', async () => {
    const { service, devices } = await makeService(home)
    const id = '77777777-7777-4777-8777-777777777777'
    await devices.add({ deviceId: id, displayName: 'D', publicKey: Buffer.from('k').toString('base64'), createdAt: 1_000, lastSeenAt: 1_000, revoked: false })
    await remoteAuthStorage.run(authFor(id), () => service.register({ deviceId: id, platform: 'android', pushToken: 't1', appVersion: '1.0' }))
    await remoteAuthStorage.run(authFor(id), () => service.register({ deviceId: id, platform: 'android', pushToken: 't2', appVersion: '1.1' }))
    const stored = await devices.find(id)
    expect(stored!.pushRegistration!.pushToken).toBe('t2')
  })

  it('unregister requires auth and device match', async () => {
    const { service } = await makeService(home)
    const id = '88888888-8888-4888-8888-888888888888'
    await expect(service.unregister({ deviceId: id })).rejects.toThrow(/authentication required/)
    await expect(
      remoteAuthStorage.run(
        {
          iss: 'test-host-id-1234567890123456789012345678901',
          sub: '99999999-9999-4999-8999-999999999999',
          aud: 'dsh-remote',
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          jti: 'test-jti',
          scope: 'full',
        } as unknown as import('@deepseek-ai/dsh-host-remote-access').TokenPayload,
        () => service.unregister({ deviceId: id }),
      ),
    ).rejects.toThrow(/must match authenticated device/)
  })

  it('unregister removes registration (idempotent)', async () => {
    const { service, devices } = await makeService(home)
    const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    await devices.add({ deviceId: id, displayName: 'D', publicKey: Buffer.from('k').toString('base64'), createdAt: 1_000, lastSeenAt: 1_000, revoked: false })
    await remoteAuthStorage.run(authFor(id), () => service.register({ deviceId: id, platform: 'ios', pushToken: 'tok', appVersion: '1.0' }))
    const first = await remoteAuthStorage.run(authFor(id), () => service.unregister({ deviceId: id }))
    expect(first.ok).toBe(true)
    const second = await remoteAuthStorage.run(authFor(id), () => service.unregister({ deviceId: id }))
    expect(second.ok).toBe(true)
    const stored = await devices.find(id)
    expect(stored!.pushRegistration).toBeUndefined()
  })

  it('unregister fails when device unknown', async () => {
    const { service } = await makeService(home)
    const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    await expect(remoteAuthStorage.run(authFor(id), () => service.unregister({ deviceId: id })))
      .rejects.toThrow(/unknown device/)
  })
})
