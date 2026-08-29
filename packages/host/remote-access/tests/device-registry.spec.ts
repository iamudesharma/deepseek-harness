import { mkdtempSync, rmSync, readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { DeviceRegistry } from '../src/device-registry.ts'
import type { DeviceRecord } from '../src/device-registry.ts'
import { resolveDeviceRegistryPath } from '../src/paths.ts'

const dirs: string[] = []

function tempHome(): string {
  const dir = mkdtempSync(join(tmpdir(), 'dsh-remote-dev-'))
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

describe('device registry', () => {
  it('adds and loads a device', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const listed = await registry.list()
    expect(listed).toHaveLength(1)
    expect(listed[0]!.deviceId).toBe(device().deviceId)
  })

  it('persists across restart (new instance reads same file)', async () => {
    const home = tempHome()
    const first = new DeviceRegistry(home)
    await first.add(device())
    const second = new DeviceRegistry(home)
    expect(await second.list()).toHaveLength(1)
  })

  it('updates lastSeenAt and token metadata', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const updated = await registry.update(device().deviceId, current => ({
      ...current,
      lastSeenAt: 2_000,
      lastJti: 'jti-1',
      tokenExpiresAt: 9_999,
    }))
    expect(updated.lastSeenAt).toBe(2_000)
    expect(updated.lastJti).toBe('jti-1')
    const listed = await registry.list()
    expect(listed[0]!.lastJti).toBe('jti-1')
  })

  it('revokes a device', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const revoked = await registry.revoke(device().deviceId, () => 5_000)
    expect(revoked.revoked).toBe(true)
    expect(revoked.revokedAt).toBe(5_000)
    expect((await registry.list())[0]!.revoked).toBe(true)
  })

  it('revoke-all', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device({ deviceId: '11111111-1111-4111-8111-111111111111' }))
    await registry.add(device({ deviceId: '22222222-2222-4222-8222-222222222222', lastSeenAt: 2_000 }))
    await registry.revokeAll(() => 9_000)
    const listed = await registry.list()
    expect(listed.every(entry => entry.revoked)).toBe(true)
    expect(listed.every(entry => entry.revokedAt === 9_000)).toBe(true)
  })

  it('returns empty when file absent', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    expect(await registry.list()).toEqual([])
  })

  it('rejects duplicate deviceId', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    await expect(registry.add(device())).rejects.toThrow(/already exists/)
  })

  it('throws for unknown device on update', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await expect(registry.update('33333333-3333-4333-8333-333333333333', current => current))
      .rejects.toThrow(/unknown deviceId/)
  })

  it('throws for invalid deviceId', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await expect(registry.add(device({ deviceId: 'not-a-uuid' })))
      .rejects.toThrow(/invalid deviceId/)
  })

  it('handles invalid/corrupt file', async () => {
    const home = tempHome()
    const file = resolveDeviceRegistryPath(home)
    mkdirSync(join(home, 'remote'), { recursive: true })
    writeFileSync(file, 'not-json', 'utf8')
    const registry = new DeviceRegistry(home)
    await expect(registry.list()).rejects.toThrow(/not valid JSON/)
  })

  it('handles corrupt device record (missing fields)', async () => {
    const home = tempHome()
    const file = resolveDeviceRegistryPath(home)
    mkdirSync(join(home, 'remote'), { recursive: true })
    writeFileSync(file, JSON.stringify({ version: 1, devices: [{ deviceId: 'bad' }] }), 'utf8')
    const registry = new DeviceRegistry(home)
    await expect(registry.list()).rejects.toThrow(/malformed/)
  })

  it('uses secure file permissions', async () => {
    if (process.platform === 'win32') return
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device())
    const file = resolveDeviceRegistryPath(home)
    expect(statSync(file).mode & 0o777).toBe(0o600)
    expect(statSync(join(home, 'remote')).mode & 0o777).toBe(0o700)
  })

  it('does not log plaintext private keys (stored file contains only publicKey)', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await registry.add(device({ publicKey: 'cHVibGljLW9ubHk=' }))
    const raw = readFileSync(resolveDeviceRegistryPath(home), 'utf8')
    expect(raw).toContain('cHVibGljLW9ubHk=')
    expect(raw).not.toContain('private')
  })

  it('find returns undefined for absent device', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    expect(await registry.find('44444444-4444-4444-8444-444444444444')).toBeUndefined()
  })

  it('atomic writes survive (no partial JSON on concurrent add)', async () => {
    const home = tempHome()
    const registry = new DeviceRegistry(home)
    await Promise.all([
      registry.add(device({ deviceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', lastSeenAt: 100 })),
      registry.add(device({ deviceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', lastSeenAt: 200 })),
    ])
    const listed = await registry.list()
    expect(listed).toHaveLength(2)
    const raw = readFileSync(resolveDeviceRegistryPath(home), 'utf8')
    expect(() => {
      const parsed: unknown = JSON.parse(raw)
      void parsed
    }).not.toThrow()
  })
})
