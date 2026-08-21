/** Mechanical enforcement of the Flutter migration tracker contract (v1.1). */

import { existsSync, readdirSync, readFileSync } from 'node:fs'
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
const RUNTIME_CATEGORIES: readonly string[] = ['runtime', 'protocol']
const GATEKEEPER_ID = 'migration-gatekeeper'
const AUDITOR_ID = 'react-codebase-auditor'

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

type ExistsPredicate = (repoRelativePath: string) => boolean

const defaultExists: ExistsPredicate = candidate => existsSync(resolve(REPO_ROOT, candidate))

/** Strip a trailing `:Symbol` anchor from a tracker source reference. */
export function sourcePath(source: string): string {
  const colon = source.lastIndexOf(':')
  return colon > source.lastIndexOf('/') ? source.slice(0, colon) : source
}

function resolveReactPackage(reactPackage: string, exists: ExistsPredicate): string | null {
  for (const base of ['packages/client', 'packages/extensions', 'packages/llm']) {
    const candidate = `${base}/${reactPackage}`
    if (exists(candidate)) return candidate
  }
  // compound reactPackage notation (e.g. ui-directory-picker-browse:ui-directory-picker-native)
  if (reactPackage.includes(':')) {
    for (const part of reactPackage.split(':')) {
      for (const base of ['packages/client', 'packages/extensions', 'packages/llm']) {
        if (exists(`${base}/${part}`)) return `${base}/${part}`
      }
    }
  }
  return null
}

/** Filesystem existence checks for source, package, target, and evidence paths (spec §7 checks 2, 3, 7). */
export function checkItemPaths(item: TrackerItem, exists: ExistsPredicate = defaultExists): string[] {
  const id = str(item, 'id')
  const violations: string[] = []
  const source = sourcePath(str(item, 'source'))
  if (source && !exists(source)) violations.push(`${id}: source path does not exist: ${source}`)
  const pkg = str(item, 'reactPackage')
  if (pkg && !resolveReactPackage(pkg, exists)) {
    violations.push(`${id}: reactPackage directory does not exist under packages/client or packages/extensions: ${pkg}`)
  }
  const target = str(item, 'flutterTarget')
  if (target && statusAtLeast(str(item, 'status'), 'Migrated') && !exists(target)) {
    violations.push(`${id}: flutterTarget must exist on disk once status is Migrated or beyond: ${target}`)
  }
  if (str(item, 'status') === 'Verified') {
    const evidence = (item.evidence ?? {}) as Record<string, unknown>
    for (const field of ['parityReport', 'replayDiff']) {
      const value = evidence[field]
      if (typeof value === 'string' && value && !exists(value)) {
        violations.push(`${id}: evidence.${field} path does not exist: ${value}`)
      }
    }
  }
  return violations
}

/** Status-dependent contract rules (spec §7 checks 5, 6, 7, 10, 13, 14, 15). */
export function checkStatusRules(item: TrackerItem): string[] {
  const id = str(item, 'id')
  const status = str(item, 'status')
  const violations: string[] = []

  if (statusAtLeast(status, 'Integrated') && (!Array.isArray(item.integrationPoints) || item.integrationPoints.length === 0)) {
    violations.push(`${id}: integrationPoints must be non-empty once status is Integrated or beyond`)
  }
  if (status === 'Verified') {
    const evidence = (item.evidence ?? {}) as Record<string, string>
    for (const field of ['testsRun', 'parityReport', 'replayDiff', 'approvedBy', 'approvedAt']) {
      if (!evidence[field]) {
        const detail = field === 'testsRun'
          ? 'must name the executed test command'
          : field === 'parityReport'
            ? 'must point at a report file'
            : field === 'replayDiff'
              ? 'must point at a replay diff file'
              : 'must be recorded'
        violations.push(`${id}: evidence.${field} ${detail}`)
      }
    }
    if (evidence.approvedBy && evidence.approvedBy !== GATEKEEPER_ID) {
      violations.push(`${id}: Verified requires evidence.approvedBy "${GATEKEEPER_ID}"`)
    }
    if (str(item, 'reviewer') !== GATEKEEPER_ID) {
      violations.push(`${id}: Verified requires reviewer "${GATEKEEPER_ID}"`)
    }
  }
  if (statusAtLeast(status, 'Integrated') && RUNTIME_CATEGORIES.includes(str(item, 'category'))
    && (!Array.isArray(item.e2eScenarios) || item.e2eScenarios.length === 0)) {
    violations.push(`${id}: e2eScenarios must be non-empty for category "${str(item, 'category')}" at Integrated or beyond`)
  }
  if (str(item, 'runtimeMode') === 'live' && item.replacementType === 'adapter'
    && !str(item, 'notes').startsWith('adapter-of:')) {
    violations.push(`${id}: live-mode adapter items must declare the adapted Harness contract via notes starting with "adapter-of:"`)
  }
  if (item.legacyVerified === true) {
    const legacy = (item.legacyVerification ?? {}) as Record<string, unknown>
    for (const field of ['previousStatus', 'demotedAt', 'demotionReason']) {
      if (typeof legacy[field] !== 'string' || legacy[field] === '') {
        violations.push(`${id}: legacyVerification.${field} is required when legacyVerified is true`)
      }
    }
    if (!Array.isArray(legacy.previousEvidence)) {
      violations.push(`${id}: legacyVerification.previousEvidence must be an array when legacyVerified is true`)
    }
  }
  if (status === 'Audited' && str(item, 'owner') !== AUDITOR_ID) {
    violations.push(`${id}: Audited items are owned by "${AUDITOR_ID}"`)
  }
  return violations
}

/** Whole-tracker cross-reference checks (spec §7 checks 11, 12, plus agent-id membership). */
export function checkCrossReferences(items: TrackerItem[], knownAgentIds: readonly string[]): string[] {
  const violations: string[] = []
  const seenIds = new Set<string>()
  const targets = new Map<string, string>()
  for (const item of items) {
    const id = str(item, 'id')
    if (seenIds.has(id)) violations.push(`duplicate tracker id: ${id}`)
    seenIds.add(id)
    const target = str(item, 'flutterTarget')
    if (targets.has(target)) violations.push(`flutterTarget claimed by multiple items: ${target}`)
    targets.set(target, id)
  }
  for (const item of items) {
    const id = str(item, 'id')
    for (const dependency of Array.isArray(item.dependsOn) ? item.dependsOn as string[] : []) {
      if (!seenIds.has(dependency)) violations.push(`${id}: dependsOn references unknown id "${dependency}"`)
    }
    for (const field of ['owner', 'reviewer']) {
      const agent = str(item, field)
      if (agent && !knownAgentIds.includes(agent)) {
        violations.push(`${id}: ${field} "${agent}" is not a known migration agent`)
      }
    }
  }
  return violations
}

/** Run every check. `strict` additionally demands at least one Verified item. */
export function validateTracker(
  items: TrackerItem[],
  options: { knownAgentIds: readonly string[]; exists?: ExistsPredicate; strict?: boolean },
): string[] {
  const exists = options.exists ?? defaultExists
  const violations = [
    ...items.flatMap(item => [...checkItemSchema(item), ...checkItemPaths(item, exists), ...checkStatusRules(item)]),
    ...checkCrossReferences(items, options.knownAgentIds),
  ]
  if (options.strict && !items.some(item => str(item, 'status') === 'Verified')) {
    violations.push('strict mode: at least one Verified item is required to claim migration completion')
  }
  return violations
}

/** CLI entry: `tsx scripts/verify-flutter-tracker.ts [--check] [--strict]`. Exit 0 only when clean. */
export function main(argv: string[]): number {
  const strict = argv.includes('--strict')
  let items: TrackerItem[]
  try {
    const parsed: unknown = JSON.parse(readFileSync(resolve(REPO_ROOT, 'migration/migration-tracker.json'), 'utf8'))
    if (!Array.isArray(parsed)) throw new Error('top-level JSON value must be an array of items')
    items = parsed as TrackerItem[]
  } catch (error) {
    console.error(`verify-flutter-tracker: cannot load migration/migration-tracker.json (${(error as Error).message})`)
    return 1
  }
  const violations = validateTracker(items, { knownAgentIds: knownAgents(), strict })
  if (violations.length > 0) {
    for (const violation of violations) console.error(`verify-flutter-tracker: ${violation}`)
    console.error(`verify-flutter-tracker: ${violations.length} violation(s)`)
    return 1
  }
  console.log(`verify-flutter-tracker: OK (${items.length} items${strict ? ', strict' : ''})`)
  return 0
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  process.exit(main(process.argv.slice(2)))
}
