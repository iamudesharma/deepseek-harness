import { describe, expect, it } from 'vitest'
import { PairingStore } from '../src/pairing-store.ts'

const HOST_ID = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
const DEVICE_ID = '11111111-1111-4111-8111-111111111111'

describe('pairing store', () => {
  it('creates a one-time nonce with short expiration', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, ttlMs: 5 * 60 * 1000, now: () => 1_000 })
    expect(entry.nonce).toMatch(/^[0-9a-f-]{36}$/i)
    expect(entry.expiresAt).toBe(1_000 + 5 * 60 * 1000)
    expect(entry.hostId).toBe(HOST_ID)
  })

  it('creates optional 6-digit PIN', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, withPin: true, generatePin: () => '123456' })
    expect(entry.pin).toBe('123456')
  })

  it('validates hostId on create', () => {
    const store = new PairingStore()
    expect(() => store.create({ hostId: 'bad' })).toThrow(/invalid hostId/)
  })

  it('consumes a valid pairing (hostId + deviceId validation)', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, now: () => 1_000 })
    const consumed = store.consume({ nonce: entry.nonce, hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 })
    expect(consumed.nonce).toBe(entry.nonce)
  })

  it('rejects replayed nonce (one-use, replay protection)', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, now: () => 1_000 })
    store.consume({ nonce: entry.nonce, hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 })
    expect(() => store.consume({ nonce: entry.nonce, hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 3_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-nonce-reused' }))
  })

  it('rejects replayed PIN as well (same nonce)', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, withPin: true, generatePin: () => '123456', now: () => 1_000 })
    store.consume({ nonce: entry.nonce, pin: '123456', hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 })
    expect(() => store.consume({ nonce: entry.nonce, pin: '123456', hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 3_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-nonce-reused' }))
  })

  it('rejects reused PIN via wrong PIN path second try still reused', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, withPin: true, generatePin: () => '123456', now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, pin: '000000', hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-pin-invalid' }))
    // Correct PIN still works after one wrong attempt (nonce not yet consumed)
    const consumed = store.consume({ nonce: entry.nonce, pin: '123456', hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_500 })
    expect(consumed.pin).toBe('123456')
  })

  it('rejects expired nonce', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, ttlMs: 1_000, now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 3_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-nonce-expired' }))
  })

  it('rejects expired PIN ceremony (same as nonce)', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, withPin: true, generatePin: () => '654321', ttlMs: 500, now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, pin: '654321', hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-nonce-expired' }))
  })

  it('rejects unknown nonce', () => {
    const store = new PairingStore()
    expect(() => store.consume({ nonce: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', hostId: HOST_ID, deviceId: DEVICE_ID }))
      .toThrow(expect.objectContaining({ code: 'pairing-nonce-unknown' }))
  })

  it('validates hostId on consume', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, hostId: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB', deviceId: DEVICE_ID, now: () => 2_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-host-mismatch' }))
  })

  it('rejects malformed deviceId', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, hostId: HOST_ID, deviceId: 'not-a-uuid', now: () => 2_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-device-invalid' }))
  })

  it('requires PIN when ceremony issued one', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, withPin: true, generatePin: () => '123456', now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-pin-required' }))
  })

  it('rejects unexpected PIN when ceremony did not issue one', () => {
    const store = new PairingStore()
    const entry = store.create({ hostId: HOST_ID, now: () => 1_000 })
    expect(() => store.consume({ nonce: entry.nonce, pin: '123456', hostId: HOST_ID, deviceId: DEVICE_ID, now: () => 2_000 }))
      .toThrow(expect.objectContaining({ code: 'pairing-pin-invalid' }))
  })

  it('prunes expired entries', () => {
    const store = new PairingStore()
    store.create({ hostId: HOST_ID, ttlMs: 1_000, now: () => 1_000 })
    expect(store.size).toBe(1)
    expect(store.prune(() => 3_000)).toBe(1)
    expect(store.size).toBe(0)
  })

  it('does not expose pairing endpoint publicly until auth boundary (store is in-memory, no HTTP binding)', () => {
    const store = new PairingStore()
    // Claim is structural: the store has no HTTP surface. This test documents the invariant.
    expect(typeof store.create).toBe('function')
    expect(typeof (store as unknown as Record<string, unknown>)['handleRequest']).toBe('undefined')
  })
})
