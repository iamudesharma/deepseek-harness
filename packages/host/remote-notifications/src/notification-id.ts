/**
 * Deterministic notification-id derivation for Phase 10A.
 *
 * Idempotency: the same authoritative event processed twice must yield the
 * same id, without using message text.
 *
 * - `turn.completed` / `turn.failed` → `session event seq`
 * - `approval.required` → `approvalId`
 * - `question.required` → `server-request rpcId`
 *
 * @module @deepseek-ai/dsh-host-remote-notifications/notification-id
 */

import { createHash } from 'node:crypto'
import type { NotificationCategory } from './types.ts'

/**
 * Derive a deterministic notification id from stable inputs.
 *
 * Uses `sha256(hostId|sessionId|category|triggerId)` truncated to 16 bytes
 * hex (32 chars) for readability; collisions are negligible for the volume
 * expected, and provider dedup handles the remainder. Stable across restarts.
 *
 * @param hostId - pinned stable host identifier.
 * @param sessionId - session that owns the trigger.
 * @param category - notification category.
 * @param triggerId - authoritative identity (`seq` for turn, `approvalId` or `rpcId` for interactions).
 * @returns lower-case hex string (32 chars).
 */
export function deriveNotificationId(
  hostId: string,
  sessionId: string,
  category: NotificationCategory,
  triggerId: string,
): string {
  const hash = createHash('sha256')
  hash.update(hostId, 'utf8')
  hash.update('|', 'utf8')
  hash.update(sessionId, 'utf8')
  hash.update('|', 'utf8')
  hash.update(category, 'utf8')
  hash.update('|', 'utf8')
  hash.update(triggerId, 'utf8')
  return hash.digest('hex').slice(0, 32)
}

/**
 * Build an opaque deep link for a notification tap.
 *
 * Validated by the client before any network fetch; never carries bearer or
 * push credentials.
 *
 * @param hostId - pinned host identifier.
 * @param sessionId - session identifier.
 * @param category - notification category for routing hint.
 * @param notificationId - deterministic id for duplicate suppression.
 * @returns deep link string (`dsh://session/...`).
 */
export function buildDeepLink(
  hostId: string,
  sessionId: string,
  category: NotificationCategory,
  notificationId: string,
): string {
  const enc = encodeURIComponent
  return `dsh://session/${enc(hostId)}/${enc(sessionId)}?category=${enc(category)}&notificationId=${enc(notificationId)}`
}
