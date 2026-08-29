import { describe, expect, it } from 'vitest'
import { DevelopmentNotificationProvider } from '../src/development-provider.ts'
import type { NotificationPayload } from '../src/types.ts'

function payload(overrides: Partial<NotificationPayload> = {}): NotificationPayload {
  return {
    hostId: 'host-123',
    deviceId: '11111111-1111-4111-8111-111111111111',
    sessionId: 'sess-1',
    category: 'turn.completed',
    notificationId: 'nid-1',
    timestamp: 1_000,
    deepLink: 'dsh://session/host-123/sess-1?category=turn.completed&notificationId=nid-1',
    ...overrides,
  }
}

describe('RemoteNotificationProvider abstraction', () => {
  it('development provider records deliveries without real push', async () => {
    const provider = new DevelopmentNotificationProvider()
    expect(provider.kind).toBe('development')
    const result = await provider.send(
      { deviceId: '11111111-1111-4111-8111-111111111111', platform: 'android', pushToken: 'tok' },
      payload(),
    )
    expect(result.ok).toBe(true)
    expect(result.message).toBe('development-recorded')
    expect(provider.records).toHaveLength(1)
    expect(provider.records[0]!.deviceId).toBe('11111111-1111-4111-8111-111111111111')
    expect(provider.records[0]!.category).toBe('turn.completed')
  })

  it('records multiple categories', async () => {
    const provider = new DevelopmentNotificationProvider()
    await provider.send({ deviceId: 'd1', platform: 'ios', pushToken: 't1' }, payload({ category: 'approval.required', notificationId: 'n2' }))
    await provider.send({ deviceId: 'd1', platform: 'ios', pushToken: 't1' }, payload({ category: 'question.required', notificationId: 'n3' }))
    expect(provider.records.map(r => r.category)).toEqual(['approval.required', 'question.required'])
  })

  it('clear resets records', async () => {
    const provider = new DevelopmentNotificationProvider()
    await provider.send({ deviceId: 'd1', platform: 'android', pushToken: 't' }, payload())
    provider.clear()
    expect(provider.records).toHaveLength(0)
  })

  it('payload contains no bearer or push credentials', async () => {
    const p = payload()
    const json = JSON.stringify(p)
    expect(json).not.toMatch(/bearer|pushToken|apiKey|private/i)
  })
})
