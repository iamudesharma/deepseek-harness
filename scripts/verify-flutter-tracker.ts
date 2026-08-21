/** Mechanical enforcement of the Flutter migration tracker contract (v1.1). */

import { readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/** Repository root, resolved from this script's location under `scripts/`. */
export const REPO_ROOT = resolve(fileURLToPath(import.meta.url), '../..')

/** Evidence states for every parity dimension; booleans are forbidden. */
export const PARITY_STATES = ['not-applicable', 'missing', 'partial', 'pass', 'fail'] as const
export type ParityState = (typeof PARITY_STATES)[number]

/** v1.1 lifecycle; order is significant for `statusAtLeast`. */
export const TRACKER_STATUSES = ['Not Started', 'Audited', 'In Progress', 'Migrated', 'Integrated', 'Verified'] as const
export type TrackerStatus = (typeof TRACKER_STATUSES)[number]

export const REPLACEMENT_TYPES = ['direct', 'adapter', 'custom', 'not-applicable'] as const
export const RUNTIME_MODES = ['live', 'replay', 'offline'] as const
export const INTEGRATION_LEVELS = ['ui', 'state', 'runtime', 'protocol', 'platform'] as const
export const CATEGORIES = [
  'screen', 'component', 'route', 'state', 'api', 'theme', 'animation',
  'dialog', 'form', 'platform', 'runtime', 'protocol', 'slot',
] as const

const PLATFORM_CATEGORIES: readonly string[] = ['screen', 'route', 'component', 'platform', 'dialog', 'form']

/** One tracker row, untyped at this file boundary because the JSON is external input. */
export interface TrackerItem { [field: string]: unknown }

function str(item: TrackerItem, field: string): string {
  const value = item[field]
  return typeof value === 'string' ? value : ''
}

function enumCheck(item: TrackerItem, field: string, allowed: readonly string[]): string[] {
  const value = item[field]
  if (typeof value === 'string' && (allowed as readonly string[]).includes(value)) return []
  return [`${str(item, 'id')}: ${field} must be one of ${allowed.join('|')}`]
}

/** Whether `status` is at or past `min` in the v1.1 lifecycle order. */
export function statusAtLeast(status: string, min: TrackerStatus): boolean {
  return TRACKER_STATUSES.indexOf(status as TrackerStatus) >= TRACKER_STATUSES.indexOf(min)
}

/** Agent ids derived from the migration agent manifests on disk. */
export function knownAgents(): string[] {
  return readdirSync(resolve(REPO_ROOT, '.opencode/agents/migration'))
    .filter(file => file.endsWith('.yaml'))
    .map(file => file.replace(/\.yaml$/, ''))
}

/**
 * Schema validity for one item: required fields, enum membership, conditional
 * requirements (spec §7 checks 1, 4, 8, 9).
 * @returns violations, each prefixed with the item id.
 */
export function checkItemSchema(item: TrackerItem): string[] {
  const id = str(item, 'id')
  const prefixed = (message: string): string => `${id || '<missing id>'}: ${message}`
  const violations: string[] = []

  for (const field of ['id', 'source', 'reactPackage', 'responsibility', 'flutterTarget', 'owner']) {
    if (!str(item, field)) violations.push(prefixed(`${field} is required`))
  }
  violations.push(...enumCheck(item, 'category', CATEGORIES))
  violations.push(...enumCheck(item, 'status', TRACKER_STATUSES))
  violations.push(...enumCheck(item, 'replacementType', REPLACEMENT_TYPES))
  violations.push(...enumCheck(item, 'runtimeMode', RUNTIME_MODES))

  const notApplicable = item.replacementType === 'not-applicable'
  if (notApplicable && !str(item, 'notApplicableReason')) {
    violations.push(prefixed('notApplicableReason is required when replacementType is "not-applicable"'))
  }

  const parity = (item.parityCheck ?? null) as Record<string, unknown> | null
  if (parity === null || typeof parity !== 'object') {
    violations.push(prefixed('parityCheck object with visual/behavior/runtime/streaming/reconnect is required'))
  } else {
    for (const dimension of ['visual', 'behavior', 'runtime', 'streaming', 'reconnect']) {
      const value = parity[dimension]
      if (typeof value !== 'string' || !(PARITY_STATES as readonly string[]).includes(value)) {
        violations.push(prefixed(`parityCheck.${dimension} must be one of ${PARITY_STATES.join('|')}`))
      }
    }
  }

  const category = str(item, 'category')
  if (PLATFORM_CATEGORIES.includes(category)) {
    const platforms = (item.platformParity ?? null) as Record<string, unknown> | null
    if (platforms === null || typeof platforms !== 'object') {
      violations.push(prefixed(`platformParity {web,macos} is required for category "${category}"`))
    } else {
      for (const platform of ['web', 'macos']) {
        const value = platforms[platform]
        if (typeof value !== 'string' || !(PARITY_STATES as readonly string[]).includes(value)) {
          violations.push(prefixed(`platformParity.${platform} must be one of ${PARITY_STATES.join('|')}`))
        }
      }
    }
  }

  const levels = item.integrationLevel
  if (!Array.isArray(levels) || levels.length === 0) {
    violations.push(prefixed('integrationLevel must be a non-empty array'))
  } else {
    for (const level of levels) {
      if (!(INTEGRATION_LEVELS as readonly string[]).includes(level as string)) {
        violations.push(prefixed(`integrationLevel entries must be one of ${INTEGRATION_LEVELS.join('|')}`))
      }
    }
  }

  return violations
}
