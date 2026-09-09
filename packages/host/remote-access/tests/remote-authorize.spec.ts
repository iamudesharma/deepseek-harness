import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import { DeviceRegistry } from '../src/device-registry.ts'
import { loadOrCreateHostIdentity, type HostIdentity } from '../src/host-identity.ts'
import { TokenService } from '../src/token-service.ts'
import { remoteAuthStorage } from '../src/auth-middleware.ts'
import { classifyRemoteMethod, isRemoteAuthorized } from '../src/privileged-policy.ts'
import { RemoteAccessFoundation } from '../src/index.ts'

const homes: string[] = []
afterEach(() => {
  for (const home of homes.splice(0)) rmSync(home, { recursive: true, force: true })
})

const DEVICE_ID = '11111111-1111-4111-8111-111111111111'

/** Live foundation: real instance with isolated-home identity and registry. */
async function foundation(overrides: { isEnabled?: boolean } = {}): Promise<{
  foundation: RemoteAccessFoundation
  identity: HostIdentity
  devices: DeviceRegistry
  tokens: TokenService
}> {
  const home = mkdtempSync(join(tmpdir(), 'dsh-remote-authz-'))
  homes.push(home)
  const identity = await loadOrCreateHostIdentity({ dshHome: home })
  const devices = new DeviceRegistry(home)
  const tokens = new TokenService(identity)
  const foundation = new RemoteAccessFoundation(new Context(), { enabled: overrides.isEnabled ?? true })
  foundation.hostIdentity = identity
  foundation.tokenService = tokens
  ;(foundation as unknown as { devices: DeviceRegistry }).devices = devices
  foundation.tlsFingerprint = 'F'.repeat(43)
  foundation.tlsPort = 3443
  return { foundation, identity, devices, tokens }
}

async function addDevice(devices: DeviceRegistry): Promise<void> {
  await devices.add({
    deviceId: DEVICE_ID,
    displayName: 'Pixel',
    publicKey: 'cHVibGlj',
    createdAt: 1000,
    lastSeenAt: 1000,
    revoked: false,
  })
}

function bearer(deviceToken: string): Record<string, string> {
  return { authorization: `Bearer ${deviceToken}` }
}

describe('authorizeApiRequest', () => {
  it('stays rejected when remote access is disabled', async () => {
    const { foundation: f } = await foundation({ isEnabled: false })
    let ran = 0
    const decision = await f.authorizeApiRequest('remote/pair', {}, async () => { ran++ })
    expect(decision).toBe('unauthenticated')
    expect(ran).toBe(0)
  })

  it('lets the pairing bootstrap through without a bearer', async () => {
    const { foundation: f } = await foundation()
    for (const endpoint of ['remote/pair', 'remote/describe']) {
      let ran = 0
      const decision = await f.authorizeApiRequest(endpoint, {}, async () => { ran++ })
      expect([endpoint, decision, ran]).toEqual([endpoint, 'proceed', 1])
    }
  })

  it('rejects bearer-less calls to protected endpoints', async () => {
    const { foundation: f } = await foundation()
    let ran = 0
    expect(await f.authorizeApiRequest('session/list', {}, async () => { ran++ })).toBe('unauthenticated')
    expect(await f.authorizeApiRequest('session/list', { authorization: 'not-bearer' }, async () => { ran++ })).toBe(
      'unauthenticated',
    )
    expect(ran).toBe(0)
  })

  it('runs bearer calls inside the verified ALS context', async () => {
    const { foundation: f, devices, tokens } = await foundation()
    await addDevice(devices)
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60000, now: () => Date.now() })
    let ran = 0
    let observedSub: string | undefined
    const decision = await f.authorizeApiRequest('session/list', bearer(token), async () => {
      ran++
      observedSub = remoteAuthStorage.getStore()?.sub
    })
    expect(decision).toBe('proceed')
    expect(ran).toBe(1)
    expect(observedSub).toBe(DEVICE_ID)
  })

  it('accepts Fetch Headers and rejects unknown or broken devices', async () => {
    const { foundation: f, devices, tokens } = await foundation()
    await addDevice(devices)
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60000, now: () => Date.now() })
    let ran = 0
    const headers = new Headers({ Authorization: `Bearer ${token}` })
    expect(await f.authorizeApiRequest('session/list', headers, async () => { ran++ })).toBe('proceed')
    expect(ran).toBe(1)
    expect(await f.authorizeApiRequest('session/list', new Headers(), async () => { ran++ })).toBe(
      'unauthenticated',
    )
    const stranger = tokens.mint({
      deviceId: '99999999-9999-4999-8999-999999999999',
      ttlMs: 60000,
      now: () => Date.now(),
    })
    expect(await f.authorizeApiRequest('session/list', bearer(stranger), async () => { ran++ })).toBe(
      'unauthenticated',
    )
    const lookup = devices.find.bind(devices)
    devices.find = async (): Promise<never> => { throw new Error('registry down') }
    try {
      expect(await f.authorizeApiRequest('session/list', bearer(token), async () => { ran++ })).toBe(
        'unauthenticated',
      )
    } finally {
      devices.find = lookup
    }
    const updater = devices.update.bind(devices)
    devices.update = async (): Promise<never> => { throw new Error('registry down') }
    try {
      expect(await f.authorizeApiRequest('session/list', bearer(token), async () => { ran++ })).toBe('proceed')
    } finally {
      devices.update = updater
    }
    expect(ran).toBe(2)
  })

  it('forbids privileged endpoints and rejects bad tokens', async () => {
    const { foundation: f, devices, tokens } = await foundation()
    await addDevice(devices)
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60000, now: () => Date.now() })
    let ran = 0
    expect(await f.authorizeApiRequest('credentials/set', bearer(token), async () => { ran++ })).toBe('forbidden')
    expect(await f.authorizeApiRequest('session/list', bearer('not-a-token'), async () => { ran++ })).toBe(
      'unauthenticated',
    )
    expect(await f.authorizeApiRequest('session/list', bearer(token.slice(0, -2) + 'xx'), async () => { ran++ })).toBe(
      'unauthenticated',
    )
    const wsTicket = tokens.mintWsTicket(DEVICE_ID, 60000, () => Date.now())
    expect(await f.authorizeApiRequest('session/list', bearer(wsTicket), async () => { ran++ })).toBe('forbidden')
    await devices.revoke(DEVICE_ID)
    expect(await f.authorizeApiRequest('session/list', bearer(token), async () => { ran++ })).toBe('unauthenticated')
    expect(ran).toBe(0)
  })

  it('rejects expired tokens', async () => {
    const { foundation: f, devices, tokens } = await foundation()
    await addDevice(devices)
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 1000, now: () => 1000 })
    let ran = 0
    expect(await f.authorizeApiRequest('session/list', bearer(token), async () => { ran++ })).toBe('unauthenticated')
    expect(ran).toBe(0)
  })
})

describe('slash-form endpoints classify like dot-form', () => {
  it('privileged slash endpoints stay privileged', () => {
    expect(classifyRemoteMethod('credentials/set')).toBe('privileged')
    expect(classifyRemoteMethod('host/pickDirectory')).toBe('privileged')
    expect(classifyRemoteMethod('settings/unknownVerb')).toBe('privileged')
    expect(classifyRemoteMethod('session/list')).toBe('safe')
    expect(isRemoteAuthorized('credentials/set', 'bearer', 'full')).toBe(false)
    expect(isRemoteAuthorized('session/list', 'bearer', 'full')).toBe(true)
    expect(isRemoteAuthorized('remote/devices', 'bearer', 'full')).toBe(true)
    expect(isRemoteAuthorized('remote/devices', 'bearer', 'ws')).toBe(false)
  })
})

describe('authorizeMuxUpgrade', () => {
  it('stays rejected when remote access is disabled', async () => {
    const { foundation: f } = await foundation({ isEnabled: false })
    expect(await f.authorizeMuxUpgrade('/api/remote.mux?ticket=x')).toBe('unauthenticated')
  })

  it('requires a ticket', async () => {
    const { foundation: f } = await foundation()
    expect(await f.authorizeMuxUpgrade(undefined)).toBe('unauthenticated')
    expect(await f.authorizeMuxUpgrade('/api/remote.mux')).toBe('unauthenticated')
    expect(await f.authorizeMuxUpgrade('/api/remote.mux?ticket=nope')).toBe('unauthenticated')
  })

  it('accepts a fresh ticket once, then rejects the replay', async () => {
    const { foundation: f, devices, tokens } = await foundation()
    await addDevice(devices)
    const ticket = tokens.mintWsTicket(DEVICE_ID, 60000, () => Date.now())
    expect(await f.authorizeMuxUpgrade(`/api/remote.mux?ticket=${ticket}`)).toBe('proceed')
    expect(await f.authorizeMuxUpgrade(`/api/remote.mux?ticket=${ticket}`)).toBe('unauthenticated')
  })

  it('forbids full-scope bearer tokens as mux tickets', async () => {
    const { foundation: f, devices, tokens } = await foundation()
    await addDevice(devices)
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60000, now: () => Date.now() })
    expect(await f.authorizeMuxUpgrade(`/api/remote.mux?ticket=${token}`)).toBe('forbidden')
  })
})
