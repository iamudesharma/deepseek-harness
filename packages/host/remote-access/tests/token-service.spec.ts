import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { loadOrCreateHostIdentity } from '../src/host-identity.ts'
import { DeviceRegistry } from '../src/device-registry.ts'
import { TokenService } from '../src/token-service.ts'

const dirs: string[] = []

function tempHome(): string {
  const dir = mkdtempSync(join(tmpdir(), 'dsh-remote-token-'))
  dirs.push(dir)
  return dir
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
})

const DEVICE_ID = '11111111-1111-4111-8111-111111111111'
const OTHER_DEVICE = '22222222-2222-4222-8222-222222222222'

async function setup() {
  const home = tempHome()
  const identity = await loadOrCreateHostIdentity({ dshHome: home })
  const registry = new DeviceRegistry(home)
  const tokens = new TokenService(identity)
  return { home, identity, registry, tokens }
}

describe('token service — primitives', () => {
  it('mints a signed bearer token with expected claims', async () => {
    const { tokens, identity } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    const payload = await tokens.verify(token, { now: () => 2_000 })
    expect(payload.iss).toBe(identity.hostId)
    expect(payload.sub).toBe(DEVICE_ID)
    expect(payload.aud).toBe('dsh-remote')
    expect(payload.scope).toBe('full')
    expect(payload.jti).toBeDefined()
    expect(payload.exp).toBeGreaterThan(payload.iat)
  })

  it('minted token carries correct deviceId/hostId/aud/expiry/jti/scope', async () => {
    const { tokens, identity } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 90 * 24 * 60 * 60 * 1000, scope: 'full', now: () => 1_000_000 })
    const payload = await tokens.verify(token, { now: () => 1_001_000 })
    expect(payload.iss).toBe(identity.hostId)
    expect(payload.sub).toBe(DEVICE_ID)
    expect(payload.aud).toBe('dsh-remote')
    expect(typeof payload.jti).toBe('string')
    expect(payload.scope).toBe('full')
    expect(payload.exp).toBe(Math.floor((1_000_000 + 90 * 24 * 60 * 60 * 1000) / 1000))
  })

  it('ws ticket is scope ws', async () => {
    const { tokens } = await setup()
    const ticket = tokens.mintWsTicket(DEVICE_ID, 60_000, () => 1_000)
    const payload = await tokens.verifyWsTicket(ticket, { now: () => 2_000 })
    expect(payload.scope).toBe('ws')
  })

  it('device private key is NOT the token credential (mint uses host key, not device key)', async () => {
    const { tokens } = await setup()
    // Tampering with a device key should not affect host-signed token verification.
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    // Verify with same host identity succeeds; different host identity fails.
    const otherHome = tempHome()
    const otherIdentity = await loadOrCreateHostIdentity({ dshHome: otherHome })
    const otherTokens = new TokenService(otherIdentity)
    await expect(otherTokens.verify(token, { now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-host-mismatch' })
  })
})

describe('token service — security', () => {
  it('rejects expired token', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 1_000, now: () => 1_000 })
    await expect(tokens.verify(token, { now: () => 5_000 }))
      .rejects.toMatchObject({ code: 'token-expired' })
  })

  it('rejects wrong hostId', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    const otherHome = tempHome()
    const otherIdentity = await loadOrCreateHostIdentity({ dshHome: otherHome })
    const other = new TokenService(otherIdentity)
    await expect(other.verify(token, { now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-host-mismatch' })
  })

  it('rejects wrong audience', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    await expect(tokens.verify(token, { audience: 'wrong-aud', now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-audience-mismatch' })
  })

  it('rejects revoked device', async () => {
    const { tokens, registry } = await setup()
    await registry.add({
      deviceId: DEVICE_ID,
      displayName: 'Pixel',
      publicKey: 'cHVibGlj',
      createdAt: 1_000,
      lastSeenAt: 1_000,
      revoked: false,
    })
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    await registry.revoke(DEVICE_ID)
    await expect(tokens.verify(token, {
      now: () => 2_000,
      deviceLookup: async (id) => {
        const found = await registry.find(id)
        return found === undefined ? undefined : { revoked: found.revoked }
      },
    })).rejects.toMatchObject({ code: 'token-revoked' })
  })

  it('rejects unknown device when lookup enabled', async () => {
    const { tokens, registry } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    await expect(tokens.verify(token, {
      now: () => 2_000,
      deviceLookup: async (id) => {
        const found = await registry.find(id)
        return found === undefined ? undefined : { revoked: found.revoked }
      },
    })).rejects.toMatchObject({ code: 'token-unknown-device' })
  })

  it('rejects invalid signature (tampered payload)', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    const parts = token.split('.')
    const payload = JSON.parse(Buffer.from(parts[1]!, 'base64url').toString('utf8')) as Record<string, unknown>
    payload['sub'] = OTHER_DEVICE
    const tamperedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url')
    const tampered = `${parts[0]}.${tamperedPayload}.${parts[2]}`
    await expect(tokens.verify(tampered, { now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-signature-invalid' })
  })

  it('rejects malformed token (wrong parts)', async () => {
    const { tokens } = await setup()
    await expect(tokens.verify('not.a.jwt', { now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-malformed' })
    await expect(tokens.verify('only-one-part', { now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-malformed' })
  })

  it('rejects invalid signature (bad base64url)', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    // Corrupt signature bytes (last char)
    const corrupted = token.slice(0, -2) + 'ab'
    await expect(tokens.verify(corrupted, { now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-signature-invalid' })
  })

  it('rejects scope mismatch when requiredScope set', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, scope: 'full', now: () => 1_000 })
    await expect(tokens.verify(token, { requiredScope: 'ws', now: () => 2_000 }))
      .rejects.toMatchObject({ code: 'token-scope-mismatch' })
  })

  it('rejects token issued far in the future (clock skew guard)', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000_000 })
    await expect(tokens.verify(token, { now: () => 1_000 }))
      .rejects.toMatchObject({ code: 'token-malformed' })
  })

  it('revocation lookup: unknown device without lookup is NOT rejected (Phase 1 bearer-only)', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    // Without deviceLookup, unknown device does not fail — bearer is the credential.
    await expect(tokens.verify(token, { now: () => 2_000 })).resolves.toBeDefined()
  })

  it('no plaintext token logging (error messages never echo token)', async () => {
    const { tokens } = await setup()
    const token = tokens.mint({ deviceId: DEVICE_ID, ttlMs: 60_000, now: () => 1_000 })
    const tampered = token + 'x'
    try {
      await tokens.verify(tampered, { now: () => 2_000 })
      expect.unreachable('should have thrown')
    } catch (error) {
      const message = (error as Error).message
      expect(message).not.toContain(token)
    }
  })
})
