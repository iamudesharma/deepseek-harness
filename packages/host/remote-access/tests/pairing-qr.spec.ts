import { describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import { base64urlEncodeJson } from '../src/crypto.ts'
import { PairingStore } from '../src/pairing-store.ts'
import {
  buildPairingQrPayload,
  decodePairingQrPayload,
  encodePairingQrPayload,
  issuePairingQr,
  normalizeBaseUri,
  type PairingQrPayload,
} from '../src/pairing-qr.ts'
import { authenticateRequest } from '../src/auth-middleware.ts'
import { loadOrCreateHostIdentity } from '../src/host-identity.ts'
import { DeviceRegistry } from '../src/device-registry.ts'
import { TokenService } from '../src/token-service.ts'
import { AuditLog } from '../src/audit.ts'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const HOST_ID = 'A'.repeat(43)
const HOST_PUB = Buffer.from('fake-spki-bytes').toString('base64')
const NONCE = '11111111-1111-4111-8111-111111111111'
const FUTURE = 9_999_999_999_999

function basePayload(overrides: Partial<PairingQrPayload> = {}): PairingQrPayload {
  return {
    baseUri: 'https://192.168.1.10:3080',
    hostId: HOST_ID,
    hostPublicKey: HOST_PUB,
    nonce: NONCE,
    exp: FUTURE,
    ...overrides,
  }
}

describe('pairing-qr normalize', () => {
  it('strips one trailing slash and trims whitespace', () => {
    expect(normalizeBaseUri('https://h:3080/')).toBe('https://h:3080')
    expect(normalizeBaseUri('  https://h:3080  ')).toBe('https://h:3080')
    expect(normalizeBaseUri('https://h:3080')).toBe('https://h:3080')
  })
})

describe('pairing-qr build', () => {
  it('accepts a minimal payload and normalizes the base URI', () => {
    const built = buildPairingQrPayload(basePayload({ baseUri: 'https://h:3080/' }))
    expect(built.baseUri).toBe('https://h:3080')
    expect(built.pin).toBeUndefined()
    expect(built.displayName).toBeUndefined()
  })

  it('accepts http loopback base URIs', () => {
    const built = buildPairingQrPayload(basePayload({ baseUri: 'http://127.0.0.1:3080' }))
    expect(built.baseUri).toBe('http://127.0.0.1:3080')
  })

  it('keeps pin and displayName when present', () => {
    const built = buildPairingQrPayload(basePayload({ pin: '123456', displayName: 'Desk' }))
    expect(built.pin).toBe('123456')
    expect(built.displayName).toBe('Desk')
  })

  it('keeps certFp when present and rejects malformed ones', () => {
    const fp = 'B'.repeat(43)
    expect(buildPairingQrPayload(basePayload({ certFp: fp })).certFp).toBe(fp)
    expect(() => buildPairingQrPayload(basePayload({ certFp: 'short' }))).toThrow('invalid certFp')
  })

  it('rejects malformed fields', () => {
    expect(() => buildPairingQrPayload(basePayload({ baseUri: 'not-a-url' }))).toThrow('invalid baseUri')
    expect(() => buildPairingQrPayload(basePayload({ hostId: 'short' }))).toThrow('invalid hostId')
    expect(() => buildPairingQrPayload(basePayload({ hostPublicKey: '' }))).toThrow('invalid hostPublicKey')
    expect(() => buildPairingQrPayload(basePayload({ nonce: 'nope' }))).toThrow('invalid nonce')
    expect(() => buildPairingQrPayload(basePayload({ pin: '12' }))).toThrow('invalid PIN')
    expect(() => buildPairingQrPayload(basePayload({ exp: Number.NaN }))).toThrow('invalid exp')
    expect(() => decodePairingQrPayload(JSON.stringify({ ...basePayload(), exp: 'tomorrow' }))).toThrow('invalid exp')
  })
})

describe('pairing-qr encode/decode', () => {
  it('round-trips through dsh://pair?data=…', () => {
    const payload = basePayload({ pin: '654321', displayName: 'Desk', certFp: 'B'.repeat(43) })
    const uri = encodePairingQrPayload(payload)
    expect(uri.startsWith('dsh://pair?data=')).toBe(true)
    expect(decodePairingQrPayload(uri)).toEqual(payload)
  })

  it('round-trips plain JSON and bare base64url', () => {
    const payload = basePayload()
    expect(decodePairingQrPayload(JSON.stringify(payload))).toEqual(payload)
    expect(decodePairingQrPayload(base64urlEncodeJson(payload))).toEqual(payload)
  })

  it('rejects dsh:// without data', () => {
    expect(() => decodePairingQrPayload('dsh://pair')).toThrow('missing data')
    expect(() => decodePairingQrPayload('dsh://pair?data=')).toThrow('missing data')
  })

  it('rejects undecodable dsh:// data', () => {
    expect(() => decodePairingQrPayload('dsh://pair?data=!!!')).toThrow('invalid base64url data')
  })

  it('rejects an invalid dsh:// URI', () => {
    expect(() => decodePairingQrPayload('dsh://[invalid')).toThrow('invalid dsh:// URI')
  })

  it('rejects malformed JSON', () => {
    expect(() => decodePairingQrPayload('{nope')).toThrow('invalid JSON')
    expect(() => decodePairingQrPayload('!!!')).toThrow('invalid payload')
  })

  it('rejects non-object payloads', () => {
    expect(() => decodePairingQrPayload(base64urlEncodeJson(123))).toThrow('invalid payload')
    expect(() => decodePairingQrPayload(JSON.stringify('just-a-string'))).toThrow('invalid payload')
  })

  it('rejects invalid JSON objects', () => {
    expect(() => decodePairingQrPayload(JSON.stringify({ nope: true }))).toThrow('missing required QR fields')
    expect(() => decodePairingQrPayload(JSON.stringify({ ...basePayload(), baseUri: 123 }))).toThrow('invalid payload')
    expect(() => decodePairingQrPayload(JSON.stringify({ ...basePayload(), hostId: 123 }))).toThrow('invalid payload')
    expect(() => decodePairingQrPayload(JSON.stringify({ ...basePayload(), hostPublicKey: 123 }))).toThrow('invalid payload')
    expect(() => decodePairingQrPayload(JSON.stringify({ ...basePayload(), nonce: 123 }))).toThrow('invalid payload')
  })

  it('rejects expired payloads', () => {
    const payload = basePayload({ exp: 1_000 })
    expect(() => decodePairingQrPayload(JSON.stringify(payload), () => 2_000)).toThrow('QR expired')
  })

  it('rejects payloads that fail field validation', () => {
    const payload = { ...basePayload(), hostId: 'short' }
    expect(() => decodePairingQrPayload(JSON.stringify(payload))).toThrow('invalid hostId')
  })
})

describe('pairing-qr issue', () => {
  it('issues a ceremony with defaults (no PIN)', () => {
    const pairing = new PairingStore()
    const issued = issuePairingQr(pairing, {
      baseUri: 'https://192.168.1.10:3080/',
      hostId: HOST_ID,
      hostPublicKey: HOST_PUB,
      now: () => 1_000,
      generateNonce: () => NONCE,
    })
    expect(issued.payload.nonce).toBe(NONCE)
    expect(issued.payload.pin).toBeUndefined()
    expect(issued.payload.exp).toBe(1_000 + 5 * 60 * 1000)
    expect(issued.expiresAt).toBe(issued.payload.exp)
    expect(issued.uri.startsWith('dsh://pair?data=')).toBe(true)
    expect(issued.json).toEqual(issued.payload)
    expect(pairing.has(NONCE)).toBe(true)
  })

  it('issues a ceremony with PIN, TTL, displayName, and custom generators', () => {
    const pairing = new PairingStore()
    const issued = issuePairingQr(pairing, {
      baseUri: 'https://desk:3080',
      hostId: HOST_ID,
      hostPublicKey: HOST_PUB,
      withPin: true,
      ttlMs: 60_000,
      displayName: 'Desk',
      certFp: 'B'.repeat(43),
      now: () => 5_000,
      generateNonce: () => '22222222-2222-4222-8222-222222222222',
      generatePin: () => '123456',
    })
    expect(issued.payload.pin).toBe('123456')
    expect(issued.payload.displayName).toBe('Desk')
    expect(issued.payload.certFp).toBe('B'.repeat(43))
    expect(issued.payload.exp).toBe(65_000)
    const decoded = decodePairingQrPayload(issued.uri, () => 6_000)
    expect(decoded.nonce).toBe('22222222-2222-4222-8222-222222222222')
  })

  it('issues a ceremony with default clock and generators', () => {
    const pairing = new PairingStore()
    const before = Date.now()
    const issued = issuePairingQr(pairing, {
      baseUri: 'https://desk:3080',
      hostId: HOST_ID,
      hostPublicKey: HOST_PUB,
    })
    expect(issued.payload.nonce).toMatch(/^[0-9a-f-]{36}$/i)
    expect(issued.payload.exp).toBeGreaterThanOrEqual(before)
    expect(issued.payload.exp).toBeLessThanOrEqual(Date.now() + 5 * 60 * 1000)
    expect(pairing.has(issued.payload.nonce)).toBe(true)
  })
})

describe('remote/describe is unauthenticated', () => {
  it('allows describe and pair without a bearer', async () => {
    const home = mkdtempSync(join(tmpdir(), 'dsh-remote-describe-'))
    try {
      const identity = await loadOrCreateHostIdentity({ dshHome: home })
      const devices = new DeviceRegistry(home)
      const tokens = new TokenService(identity)
      const audit = new AuditLog()
      await expect(authenticateRequest({ headers: {}, url: '/api/remote.describe' }, 'remote/describe', identity, tokens, devices, audit))
        .resolves.toMatchObject({ kind: 'pairing' })
      await expect(authenticateRequest({ headers: {}, url: '/api/remote.pair' }, 'remote/pair', identity, tokens, devices, audit))
        .resolves.toMatchObject({ kind: 'pairing' })
    } finally {
      rmSync(home, { recursive: true, force: true })
    }
  })

  it('describe returns the public host identity', async () => {
    const home = mkdtempSync(join(tmpdir(), 'dsh-remote-describe-svc-'))
    try {
      const { RemoteAccessService } = await import('../src/remote-service.ts')
      const identity = await loadOrCreateHostIdentity({ dshHome: home })
      const ctx = new Context()
      ;(ctx as unknown as Record<string, unknown>)['remoteAccessFoundation'] = { hostIdentity: identity }
      const service = new RemoteAccessService(ctx)
      const result = await service.describe()
      expect(result.hostId).toBe(identity.hostId)
      expect(result.hostPublicKey).toBe(identity.publicKeyDer.toString('base64'))
      expect(result.tlsFingerprint).toBeUndefined()
    } finally {
      rmSync(home, { recursive: true, force: true })
    }
  })

  it('describe includes the TLS fingerprint when the listener is up', async () => {
    const home = mkdtempSync(join(tmpdir(), 'dsh-remote-describe-tls-'))
    try {
      const { RemoteAccessService } = await import('../src/remote-service.ts')
      const identity = await loadOrCreateHostIdentity({ dshHome: home })
      const ctx = new Context()
      ;(ctx as unknown as Record<string, unknown>)['remoteAccessFoundation'] = {
        hostIdentity: identity,
        tlsFingerprint: 'C'.repeat(43),
      }
      const service = new RemoteAccessService(ctx)
      const result = await service.describe()
      expect(result.tlsFingerprint).toBe('C'.repeat(43))
    } finally {
      rmSync(home, { recursive: true, force: true })
    }
  })
})
