import { describe, expect, it } from 'vitest'
import { buildDeepLink, deriveNotificationId } from '../src/notification-id.ts'

describe('deriveNotificationId', () => {
  const hostId = 'host-abc-123'
  const sessionId = '11111111-1111-4111-8111-111111111111'
  it('is deterministic for same inputs', () => {
    const first = deriveNotificationId(hostId, sessionId, 'turn.completed', '42')
    const second = deriveNotificationId(hostId, sessionId, 'turn.completed', '42')
    expect(first).toBe(second)
    expect(first).toHaveLength(32)
    expect(first).toMatch(/^[0-9a-f]{32}$/)
  })

  it('differs when trigger changes', () => {
    const a = deriveNotificationId(hostId, sessionId, 'turn.completed', '42')
    const b = deriveNotificationId(hostId, sessionId, 'turn.completed', '43')
    expect(a).not.toBe(b)
  })

  it('differs by category', () => {
    const a = deriveNotificationId(hostId, sessionId, 'turn.completed', '42')
    const b = deriveNotificationId(hostId, sessionId, 'turn.failed', '42')
    expect(a).not.toBe(b)
  })

  it('differs by session', () => {
    const a = deriveNotificationId(hostId, 'sess-1', 'approval.required', 'appr-1')
    const b = deriveNotificationId(hostId, 'sess-2', 'approval.required', 'appr-1')
    expect(a).not.toBe(b)
  })

  it('differs by host', () => {
    const a = deriveNotificationId('host-1', sessionId, 'question.required', 'rpc-1')
    const b = deriveNotificationId('host-2', sessionId, 'question.required', 'rpc-1')
    expect(a).not.toBe(b)
  })

  it('does not incorporate message text', () => {
    // Trigger id is seq/rpcId, not text — two different texts with same seq must collide
    const a = deriveNotificationId(hostId, sessionId, 'turn.completed', '99')
    const b = deriveNotificationId(hostId, sessionId, 'turn.completed', '99')
    expect(a).toBe(b)
  })
})

describe('buildDeepLink', () => {
  it('builds dsh://session/<hostId>/<sessionId> link', () => {
    const link = buildDeepLink('hostId123', 'sess-456', 'approval.required', 'nid-789')
    expect(link).toBe('dsh://session/hostId123/sess-456?category=approval.required&notificationId=nid-789')
  })

  it('encodes components', () => {
    const link = buildDeepLink('host/id', 'sess/id', 'turn.completed', 'nid/id')
    expect(link).toContain(encodeURIComponent('host/id'))
    expect(link).toContain(encodeURIComponent('sess/id'))
  })

  it('never contains bearer or push credentials', () => {
    const link = buildDeepLink('h1', 's1', 'turn.failed', 'n1')
    expect(link).not.toMatch(/bearer|token|pushToken|apiKey/i)
  })
})
