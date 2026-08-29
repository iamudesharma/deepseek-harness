# Migration Rework System v1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the React→Flutter migration program on enforceable foundations: a real `verify-flutter-tracker` gate, an 18-agent roster with partitioned write authority, 12 reworked/new skills, an honest v1.1 tracker (75 legacy items demoted), and the 11-inventory M0 re-audit.

**Architecture:** Extend the existing tracker JSON in place to schema v1.1 (new lifecycle, multi-state parity, evidence blocks). Add a TypeScript gate script (`scripts/verify-flutter-tracker.ts`) following the repo's checker+spec convention. Evolve `.opencode/agents/migration/` and mirror everything to `.agents/agents/migration/` / `.agents/skills/`.

**Tech Stack:** TypeScript (strict, ESM, NodeNext), vitest, tsx, YAML agent manifests, Markdown SKILL.md files, Python-free (codemods via `python3` one-offs are acceptable for the tracker migration).

**Spec:** `docs/superpowers/specs/2026-08-21-migration-rework-v1.1-design.md` (the plan argues from the spec; executors read both).

## Global Constraints

- ESM everywhere; local imports use `.ts` extensions (`import ... from './x.ts'`).
- Strict TypeScript; exported functions get JSDoc with `@param`/`@returns`; no `any` without justification; no comments except contracts.
- Files end with exactly one trailing newline (`git diff --check` must stay clean).
- Conventional commits (`feat:`, `refactor:`, `docs:`, `test:`).
- Agents live in BOTH `.opencode/agents/migration/` and `.agents/agents/migration/` (identical copies). Skills live in BOTH `.opencode/skills/` and `.agents/skills/`.
- Never mark an item `Verified` in any task of this plan; only the Gatekeeper (a later runtime activity) may.
- No backend/package changes under `packages/`; this plan touches `scripts/`, `migration/`, `.opencode/`, `.agents/`, `package.json`, `docs/superpowers/` only.
- Lifecycle states (exact strings): `Not Started`, `Audited`, `In Progress`, `Migrated`, `Integrated`, `Verified`.
- Parity states (exact strings): `not-applicable`, `missing`, `partial`, `pass`, `fail`.

---

### Task 1: Tracker v1.1 types + schema checks (`verify-flutter-tracker` part 1)

**Files:**
- Create: `scripts/verify-flutter-tracker.ts`
- Test: `scripts/verify-flutter-tracker.spec.ts`

**Interfaces:**
- Consumes: nothing (leaf module).
- Produces (Task 2 and the spec file rely on these exact names): `REPO_ROOT`, `PARITY_STATES`, `ParityState`, `TRACKER_STATUSES`, `TrackerStatus`, `REPLACEMENT_TYPES`, `RUNTIME_MODES`, `INTEGRATION_LEVELS`, `CATEGORIES`, `TrackerItem`, `statusAtLeast(status, min)`, `checkItemSchema(item): string[]`, `knownAgents(): string[]`.

- [ ] **Step 1: Write the failing tests**

Create `scripts/verify-flutter-tracker.spec.ts`:

```ts
/** Behavioral coverage for the Flutter migration tracker gate. */

import { describe, expect, it } from 'vitest'
import {
  checkItemSchema,
  PARITY_STATES,
  statusAtLeast,
  type TrackerItem,
} from './verify-flutter-tracker.ts'

function validItem(overrides: Partial<TrackerItem> = {}): TrackerItem {
  return {
    id: 'component.ui-primitives.Button',
    category: 'component',
    source: 'packages/client/ui-primitives/src/Button.tsx',
    reactPackage: 'ui-primitives',
    responsibility: 'Renders the shared button primitive.',
    flutterTarget: 'apps/flutter/lib/src/widgets/primitives/ds_button.dart',
    replacementType: 'direct',
    notApplicableReason: '',
    status: 'Audited',
    owner: 'react-codebase-auditor',
    reviewer: '',
    dependsOn: ['theme.tokens'],
    blockedBy: null,
    integrationLevel: ['ui'],
    integrationPoints: [],
    runtimeMode: 'replay',
    parityCheck: {
      visual: 'missing',
      behavior: 'missing',
      runtime: 'not-applicable',
      streaming: 'not-applicable',
      reconnect: 'not-applicable',
    },
    platformParity: { web: 'missing', macos: 'missing' },
    tests: [],
    e2eScenarios: [],
    evidence: { testsRun: '', parityReport: '', replayDiff: '', approvedBy: '', approvedAt: '' },
    legacyVerified: false,
    notes: '',
    ...overrides,
  } as TrackerItem
}

describe('statusAtLeast', () => {
  it('orders the v1.1 lifecycle', () => {
    expect(statusAtLeast('Migrated', 'Migrated')).toBe(true)
    expect(statusAtLeast('Integrated', 'Migrated')).toBe(true)
    expect(statusAtLeast('In Progress', 'Migrated')).toBe(false)
    expect(statusAtLeast('Not Started', 'Audited')).toBe(false)
  })
})

describe('checkItemSchema', () => {
  it('accepts a fully valid item', () => {
    expect(checkItemSchema(validItem())).toEqual([])
  })

  it('rejects invalid enums and missing required fields', () => {
    const violations = checkItemSchema(validItem({
      id: '',
      category: 'widget' as never,
      status: 'Tested' as never,
      replacementType: 'ported' as never,
      runtimeMode: 'hybrid' as never,
      responsibility: '',
      reactPackage: '',
    }))
    expect(violations).toHaveLength(7)
    expect(violations.every((v) => v.includes('component.ui-primitives.Button'))).toBe(true)
  })

  it('requires notApplicableReason exactly when replacementType is not-applicable', () => {
    expect(checkItemSchema(validItem({ replacementType: 'not-applicable' })))
      .toEqual(['component.ui-primitives.Button: notApplicableReason is required when replacementType is "not-applicable"'])
    expect(checkItemSchema(validItem({ notApplicableReason: 'unused' }))).toEqual([])
  })

  it('validates all five parity dimensions against the state enum', () => {
    const parityCheck = { visual: 'ok', behavior: 'missing', runtime: 'missing', streaming: 'missing', reconnect: 'missing' }
    const violations = checkItemSchema(validItem({ parityCheck: parityCheck as never }))
    expect(violations).toEqual(['component.ui-primitives.Button: parityCheck.visual must be one of ' + PARITY_STATES.join('|')])
  })

  it('requires platformParity for user-facing categories', () => {
    const item = validItem({ category: 'screen' }) as Record<string, unknown>
    delete item.platformParity
    expect(checkItemSchema(item as TrackerItem))
      .toEqual(['screen.x: platformParity {web,macos} is required for category "screen"'])
  })

  it('requires a non-empty integrationLevel subset', () => {
    expect(checkItemSchema(validItem({ integrationLevel: [] })))
      .toEqual(['component.ui-primitives.Button: integrationLevel must be a non-empty array'])
    expect(checkItemSchema(validItem({ integrationLevel: ['nope'] as never }))[0])
      .toContain('integrationLevel')
  })
})
```

Note: the `platformParity` violation message uses the item id — adjust the expected string to `'component.ui-primitives.Button: platformParity {web,macos} is required for category "screen"'` (keep id prefix consistent; the fixture keeps its own id).

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm vitest run scripts/verify-flutter-tracker.spec.ts`
Expected: FAIL — module `./verify-flutter-tracker.ts` not found.

- [ ] **Step 3: Implement types + `checkItemSchema`**

Create `scripts/verify-flutter-tracker.ts`:

```ts
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
    .filter((file) => file.endsWith('.yaml'))
    .map((file) => file.replace(/\.yaml$/, ''))
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pnpm vitest run scripts/verify-flutter-tracker.spec.ts`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-flutter-tracker.ts scripts/verify-flutter-tracker.spec.ts
git commit -m "feat(migration): add tracker v1.1 schema types and item schema checks"
```

---

### Task 2: Path/status/evidence/cross-reference checks + CLI + package.json wiring

**Files:**
- Modify: `scripts/verify-flutter-tracker.ts` (append)
- Modify: `scripts/verify-flutter-tracker.spec.ts` (append describes)
- Modify: `package.json` (scripts section)

**Interfaces:**
- Consumes: everything from Task 1.
- Produces: `checkItemPaths(item, exists)`, `checkStatusRules(item)`, `checkCrossReferences(items, knownAgentIds)`, `validateTracker(items, options)` returning `string[]`, `main(argv): number` — and the runnable `pnpm run verify-flutter-tracker [--check|--strict]`.

- [ ] **Step 1: Write failing tests (append to spec)**

```ts
import { checkCrossReferences, checkItemPaths, checkStatusRules, validateTracker } from './verify-flutter-tracker.ts'

const existsMap = (paths: string[]) => (candidate: string) => paths.includes(candidate)
const REACT = 'packages/client/ui-primitives/src/Button.tsx'
const TARGET = 'apps/flutter/lib/src/widgets/primitives/ds_button.dart'

describe('checkItemPaths', () => {
  it('accepts existing sources, packages, and migrated targets', () => {
    const item = validItem({ status: 'Migrated' })
    expect(checkItemPaths(item, existsMap([REACT, 'packages/client/ui-primitives', TARGET]))).toEqual([])
  })

  it('strips :Anchor suffixes from sources before checking', () => {
    const item = validItem({ source: `${REACT}:Button` })
    expect(checkItemPaths(item, existsMap([REACT, 'packages/client/ui-primitives']))).toEqual([])
  })

  it('does not require the target file below Migrated', () => {
    expect(checkItemPaths(validItem(), existsMap([REACT, 'packages/client/ui-primitives']))).toEqual([])
  })

  it('reports missing source, package, and target', () => {
    const item = validItem({ status: 'Migrated' })
    const violations = checkItemPaths(item, existsMap([]))
    expect(violations).toHaveLength(3)
    expect(violations.every((v) => v.startsWith('component.ui-primitives.Button:'))).toBe(true)
  })

  it('resolves reactPackage under packages/client or packages/extensions', () => {
    const item = validItem({ reactPackage: 'cordis-client-runner' })
    expect(checkItemPaths(item, existsMap([REACT, 'packages/extensions/cordis-client-runner']))).toEqual([])
  })
})

describe('checkStatusRules', () => {
  it('requires integrationPoints from Integrated onward', () => {
    expect(checkStatusRules(validItem({ status: 'Integrated', integrationPoints: [] })))
      .toEqual(['component.ui-primitives.Button: integrationPoints must be non-empty once status is Integrated or beyond'])
    expect(checkStatusRules(validItem({ status: 'Integrated', integrationPoints: ['riverpod/sessionProvider'] }))).toEqual([])
  })

  it('requires complete external Gatekeeper evidence for Verified', () => {
    const item = validItem({
      status: 'Verified',
      reviewer: 'migration-gatekeeper',
      integrationPoints: ['riverpod/sessionProvider'],
      evidence: { testsRun: '', parityReport: '', replayDiff: '', approvedBy: 'migration-gatekeeper', approvedAt: '2026-08-21' },
    })
    const violations = checkStatusRules(item)
    expect(violations).toContain('component.ui-primitives.Button: evidence.testsRun must name the executed test command')
    expect(violations).toContain('component.ui-primitives.Button: evidence.parityReport must point at a report file')
    expect(violations).toContain('component.ui-primitives.Button: evidence.replayDiff must point at a replay diff file')
  })

  it('rejects Verified approved by anyone but the Gatekeeper', () => {
    const item = validItem({
      status: 'Verified',
      reviewer: 'ui-parity',
      integrationPoints: ['x'],
      evidence: { testsRun: 'pnpm vitest run x', parityReport: 'migration/parity-reports/a.md', replayDiff: 'migration/parity-reports/b.md', approvedBy: 'ui-parity', approvedAt: '2026-08-21' },
    })
    const violations = checkStatusRules(item)
    expect(violations).toContain('component.ui-primitives.Button: Verified requires reviewer "migration-gatekeeper"')
    expect(violations).toContain('component.ui-primitives.Button: Verified requires evidence.approvedBy "migration-gatekeeper"')
  })

  it('requires e2eScenarios for runtime/protocol categories at Integrated+', () => {
    const item = validItem({ category: 'runtime', status: 'Integrated', integrationPoints: ['x'], e2eScenarios: [] })
    expect(checkStatusRules(item))
      .toEqual(['component.ui-primitives.Button: e2eScenarios must be non-empty for category "runtime" at Integrated or beyond'])
  })

  it('forbids undeclared synthetic adapters in live mode', () => {
    const item = validItem({ runtimeMode: 'live', replacementType: 'adapter', notes: 'stand-in for the real service' })
    expect(checkStatusRules(item))
      .toEqual(['component.ui-primitives.Button: live-mode adapter items must declare the adapted Harness contract via notes starting with "adapter-of:"'])
    expect(checkStatusRules(validItem({ runtimeMode: 'live', replacementType: 'adapter', notes: 'adapter-of: dsh-session log stream' }))).toEqual([])
  })

  it('requires complete legacyVerification blocks on demoted items', () => {
    const item = validItem({ legacyVerified: true, legacyVerification: { previousStatus: 'Verified', previousEvidence: [], demotedAt: '', demotionReason: '' } })
    const violations = checkStatusRules(item)
    expect(violations).toContain('component.ui-primitives.Button: legacyVerification.demotedAt is required when legacyVerified is true')
    expect(violations).toContain('component.ui-primitives.Button: legacyVerification.demotionReason is required when legacyVerified is true')
  })

  it('couples Audited items to the auditor and Verified to the gatekeeper reviewer', () => {
    expect(checkStatusRules(validItem({ status: 'Audited', owner: 'flutter-migration' })))
      .toEqual(['component.ui-primitives.Button: Audited items are owned by "react-codebase-auditor"'])
  })
})

describe('checkCrossReferences', () => {
  it('rejects duplicate ids, unknown dependsOn ids, duplicated targets, and unknown agents', () => {
    const other = validItem({ id: 'theme.tokens', flutterTarget: TARGET, owner: 'nobody' })
    const violations = checkCrossReferences([validItem(), other, validItem()], ['react-codebase-auditor'])
    expect(violations).toContain(`duplicate tracker id: component.ui-primitives.Button`)
    expect(violations).toContain('component.ui-primitives.Button: dependsOn references unknown id "theme.tokens"')
    expect(violations).toContain(`flutterTarget claimed by multiple items: ${TARGET}`)
    expect(violations.some((v) => v.includes('owner "nobody" is not a known migration agent'))).toBe(true)
  })
})

describe('validateTracker', () => {
  it('aggregates item and cross-reference violations', () => {
    const violations = validateTracker([validItem({ id: '' })], { knownAgentIds: ['react-codebase-auditor'], exists: existsMap([]) })
    expect(violations.length).toBeGreaterThan(0)
  })

  it('enforces strict mode only when nothing is Verified', () => {
    const options = { knownAgentIds: ['react-codebase-auditor'], exists: existsMap([REACT, 'packages/client/ui-primitives']) }
    expect(validateTracker([validItem()], { ...options, strict: true })).toEqual([
      'strict mode: at least one Verified item is required to claim migration completion',
    ])
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm vitest run scripts/verify-flutter-tracker.spec.ts`
Expected: FAIL — missing exports `checkItemPaths`, `checkStatusRules`, `checkCrossReferences`, `validateTracker`.

- [ ] **Step 3: Implement (append to `scripts/verify-flutter-tracker.ts`)**

```ts
type ExistsPredicate = (repoRelativePath: string) => boolean

const defaultExists: ExistsPredicate = (candidate) => existsSync(resolve(REPO_ROOT, candidate))

/** Strip a trailing `:Symbol` anchor from a tracker source reference. */
export function sourcePath(source: string): string {
  const colon = source.lastIndexOf(':')
  return colon > source.lastIndexOf('/') ? source.slice(0, colon) : source
}

function resolveReactPackage(reactPackage: string): string | null {
  for (const base of ['packages/client', 'packages/extensions']) {
    const candidate = `${base}/${reactPackage}`
    if (defaultExists(candidate)) return candidate
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
  if (pkg && !resolveReactPackage(pkg)) {
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
              : `must be recorded`
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
    ...items.flatMap((item) => [...checkItemSchema(item), ...checkItemPaths(item, exists), ...checkStatusRules(item)]),
    ...checkCrossReferences(items, options.knownAgentIds),
  ]
  if (options.strict && !items.some((item) => str(item, 'status') === 'Verified')) {
    violations.push('strict mode: at least one Verified item is required to claim migration completion')
  }
  return violations
}
```

Then the CLI entry (same file):

```ts
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
```

Note: if the direct-execution guard misfires under tsx on macOS, replace the guard with `if (process.env.DSH_VERIFY_TRACKER_CLI)` invoked via a `"dsh:verify-tracker-cli": "DSH_VERIFY_TRACKER_CLI=1 tsx …"` wrapper — do not weaken the library exports either way.

Add to `package.json` scripts (alphabetical neighbors):

```jsonc
"verify-flutter-tracker": "tsx scripts/verify-flutter-tracker.ts",
```

- [ ] **Step 4: Run tests + CLI smoke**

Run: `pnpm vitest run scripts/verify-flutter-tracker.spec.ts && pnpm run verify-flutter-tracker --check`
Expected: tests PASS; CLI exits nonzero with violations (current tracker is still v0 — that is the correct baseline signal).

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-flutter-tracker.ts scripts/verify-flutter-tracker.spec.ts package.json
git commit -m "feat(migration): make verify-flutter-tracker an executable gate"
```

---

### Task 3: Demote the legacy 75 into v1.1 shape

**Files:**
- Modify: `migration/migration-tracker.json` (all 75 items)

**Interfaces:**
- Consumes: the gate from Task 2.
- Produces: a tracker that passes `pnpm run verify-flutter-tracker --check` with 75 `Audited` items carrying `legacyVerification` blocks (Task 10 builds on this file; Tasks 8–9 feed it corrections).

- [ ] **Step 1: Run the demotion codemod**

```bash
python3 - <<'PY'
import json

path = 'migration/migration-tracker.json'
items = json.load(open(path))
TODAY = '2026-08-21'
LEVEL = {
    'screen': ['ui'], 'component': ['ui'], 'route': ['ui'], 'theme': ['ui'],
    'animation': ['ui'], 'dialog': ['ui'], 'form': ['ui'],
    'state': ['state'], 'api': ['protocol'], 'platform': ['platform'],
}
MISSING = 'missing'
NOT_APPLICABLE = 'not-applicable'

def react_package(source: str) -> str:
    for base in ('/packages/client/', '/packages/extensions/'):
        if base in source:
            return source.split(base, 1)[1].split('/', 1)[0]
    return ''

for it in items:
    old_parity = it.get('parityCheck', {})
    old_tests = it.get('tests', [])
    slug = it['id'].split('.', 1)[-1].replace('.', ' ')
    it['reactPackage'] = react_package(it.get('source', ''))
    it['responsibility'] = it.get('notes') or f'{slug} (wording pending M0 re-audit)'
    it['replacementType'] = 'direct'
    it['notApplicableReason'] = ''
    it['status'] = 'Audited'
    it['owner'] = 'react-codebase-auditor'
    it['reviewer'] = ''
    it['integrationLevel'] = LEVEL[it['category']]
    it['integrationPoints'] = []
    it['runtimeMode'] = 'replay'
    it['parityCheck'] = {
        'visual': MISSING, 'behavior': MISSING,
        'runtime': NOT_APPLICABLE, 'streaming': NOT_APPLICABLE, 'reconnect': NOT_APPLICABLE,
    }
    if it['category'] in ('screen', 'route', 'component', 'platform', 'dialog', 'form'):
        it['platformParity'] = {'web': MISSING, 'macos': MISSING}
    it['e2eScenarios'] = []
    it['evidence'] = {'testsRun': '', 'parityReport': '', 'replayDiff': '', 'approvedBy': '', 'approvedAt': ''}
    it['legacyVerified'] = True
    it['legacyVerification'] = {
        'previousStatus': 'Verified',
        'previousEvidence': [{'parityCheck': old_parity, 'tests': old_tests}],
        'demotedAt': TODAY,
        'demotionReason': 'New v1.1 evidence requirements',
    }

json.dump(items, open(path, 'w'), indent=2, ensure_ascii=False)
open(path, 'a').write('\n')
print(f'demoted {len(items)} items')
PY
```

Notes: old boolean claims survive only inside `legacyVerification.previousEvidence`; new parity dims start at `missing`/`not-applicable` honestly. `dependsOn`, `blockedBy`, `tests`, `notes`, `source`, `flutterTarget` stay untouched.

- [ ] **Step 2: Fix dependencies the codemod cannot know**

Some legacy `dependsOn` ids may not exist as rows (e.g. `theme.tokens`, `state.layout`). For each such id reported by the gate, EITHER add a minimal row (`category: 'theme'`/`'state'`, status `Audited`, same field pattern, source = the tokens/store file in `apps/flutter/lib/src/theme/` or equivalent) OR remove the dangling reference when the dependency is genuinely internal to the Flutter target. Prefer adding rows for shared foundations.

Run: `pnpm run verify-flutter-tracker --check`
Expected: violation list shrinks to only genuine data issues; fix each until exit 0.

- [ ] **Step 3: Verify clean**

Run: `pnpm run verify-flutter-tracker --check`
Expected: `verify-flutter-tracker: OK (N items)` where N ≥ 75.

- [ ] **Step 4: Commit**

```bash
git add migration/migration-tracker.json
git commit -m "refactor(migration): demote legacy Verified items to v1.1 audit baseline"
```

---

### Task 4: Evolve the 9 existing agents (both directories)

**Files:**
- Rename + rewrite: `.opencode/agents/migration/frontend-analyzer.yaml` → `.opencode/agents/migration/react-codebase-auditor.yaml`
- Rewrite: `flutter-migration.yaml`, `migration-planner.yaml`, `migration-qa.yaml`, `migration-tracker.yaml`, `ui-parity.yaml`, `flutter-web.yaml`, `flutter-macos.yaml`, `react-perfect-translator.yaml` (same directory)
- Mirror: identical changes in `.agents/agents/migration/`

**Interfaces:**
- Produces: agent ids the validator resolves via `knownAgents()` — the renamed id `react-codebase-auditor` MUST land in the same commit as Task 3's tracker (which sets `owner: react-codebase-auditor`). Execute Task 4 BEFORE running the gate again if done out of order.

- [ ] **Step 1: Rename + rewrite the Auditor (both dirs)**

Delete `frontend-analyzer.yaml`; create `react-codebase-auditor.yaml` with:

```yaml
interface:
  display_name: "React Codebase Auditor"
  short_description: "Re-audits the browser-half architecture into 11 inventories and owns the Audited status."
  default_prompt: "Use $web-codebase-analysis plus direct source reading to audit everything participating in the browser/frontend runtime: packages/client/**, packages/extensions/*client*, API remote surfaces, packages/interaction, packages/boot, host/browser contracts, apps/web. Produce the 11 inventories under migration/audit/ (client-package, runtime-service, slot, api-contract, event, conversation-node, primitive, platform, dependency, plugin-lifecycle, interaction), each citing real files. Validate every tracker source mapping against the repository and fix wrong ones (e.g. Markdown maps to MarkdownText, not TerminalBlock). You alone set tracker status Audited; you never set Migrated or beyond."
```

- [ ] **Step 2: Rewrite the other evolved prompts (both dirs)**

`flutter-migration.yaml`:

```yaml
interface:
  display_name: "Package Migration Agent"
  short_description: "Ports audited React responsibilities to structurally complete Flutter implementations."
  default_prompt: "Migrate one tracker item at a time from its Audited row using $css-to-flutter, $web-component-to-flutter, $web-state-to-flutter, $api-to-dart, $responsive-web-to-flutter, and $react-perfect-translator. Migrated means structurally complete for the audited responsibility and passing package-level compile plus unit/widget tests — never wire synthetic fallbacks for Harness services and never claim integration. Stop at Migrated; Flutter Integration and stage agents own later statuses."
```

`migration-planner.yaml`:

```yaml
interface:
  display_name: "Migration Planner Agent"
  short_description: "Sequences the rework into P0/P1/P2 phases over the v1.1 tracker DAG."
  default_prompt: "Read migration/migration-tracker.json and migration/audit/*.md; emit migration/plan.md as a phased DAG. Order: P0 live connection, session/workspace/projection/interaction runtimes, ConversationNode assembly, streaming, reconnect, tool lifecycle, API contracts; P1 slots/plugins, references, input triggers, subagents, plans/questions/permissions, settings, mutation semantics; P2 primitives polish, brand, accessibility, virtualization, visual regression. Respect dependsOn edges and record blockers."
```

`migration-qa.yaml`:

```yaml
interface:
  display_name: "Migration QA Agent"
  short_description: "Generates and runs three-tier tests; produces evidence; holds no status authority."
  default_prompt: "Use $flutter-test-generation to generate unit/widget/integration tests for Migrated and Integrated items and run them with coverage. Write results to migration/parity-reports/<id>.md as evidence for the Gatekeeper. You never advance tracker statuses; on failure, file the blocker in the report and notify the owning stage agent."
```

`migration-tracker.yaml`:

```yaml
interface:
  display_name: "Migration Tracker Agent"
  short_description: "Atomic bookkeeping of decisions made by stage owners; never determines correctness."
  default_prompt: "Own the file mechanics of migration/migration-tracker.json and migration/TRACKER.md: apply status changes ONLY as decided by the owning agents (Auditor=Audited, Migration=Migrated, Integration-stage=Integrated, Gatekeeper=Verified/demotions), keep dependsOn/blockedBy and counts current, and run pnpm run verify-flutter-tracker --check after every write. You never invent or propose statuses."
```

`ui-parity.yaml`:

```yaml
interface:
  display_name: "Visual Parity Agent"
  short_description: "React-vs-Flutter visual comparison; runs only after Integration; produces evidence."
  default_prompt: "Use $flutter-parity-check and $flutter-ui-visual-check to compare visuals against apps/web AFTER the item reaches Integrated. Write PASS/FAIL with screenshots to migration/parity-reports/<id>.md as Gatekeeper evidence. Visual parity never substitutes for runtime, streaming, reconnect, or interaction parity."
```

`flutter-web.yaml`:

```yaml
interface:
  display_name: "Platform Web Agent"
  short_description: "Validates Flutter Web behavior: keyboard, drag-drop, history, focus, pickers, builds."
  default_prompt: "For platform-affecting items, verify browser behavior (keyboard shortcuts, drag-and-drop, file upload/pickers, deep links, history, scroll, hover/focus, context menus, external URLs, text selection, clipboard formats), run flutter build web, and record platformParity.web evidence in migration/parity-reports/. You produce evidence only; statuses belong to stage owners and the Gatekeeper."
```

`flutter-macos.yaml`:

```yaml
interface:
  display_name: "Platform macOS Agent"
  short_description: "Validates Flutter macOS desktop behavior and production builds."
  default_prompt: "For platform-affecting items, verify macOS windowing, menus, keyboard/mouse, file pickers, native filesystem access, and clipboard; run flutter build macos; record platformParity.macos evidence in migration/parity-reports/. You produce evidence only; statuses belong to stage owners and the Gatekeeper."
```

`react-perfect-translator.yaml`:

```yaml
interface:
  display_name: "React Perfect Translator"
  short_description: "Pixel-faithful component translation used by the Package Migration Agent."
  default_prompt: "Harvest props, CSS-module tokens, stores, inject faces, slot graphs, and popup triggers from the React source, then emit idiomatic Flutter widgets with exact token wiring and backend connections intact. Deliverables count toward Migrated only; integration and verification are owned downstream."
```

- [ ] **Step 3: Mirror to `.agents/agents/migration/`**

Copy each changed/renamed file identically:

```bash
cp .opencode/agents/migration/react-codebase-auditor.yaml .agents/agents/migration/react-codebase-auditor.yaml
rm .agents/agents/migration/frontend-analyzer.yaml
for f in flutter-migration migration-planner migration-qa migration-tracker ui-parity flutter-web flutter-macos react-perfect-translator; do
  cp ".opencode/agents/migration/$f.yaml" ".agents/agents/migration/$f.yaml"
done
```

- [ ] **Step 4: Update stale `$frontend-analyzer` references**

Update `migration/MIGRATION_MODE.md` (agent list line) to name `react-codebase-auditor` and the new roster. Leave `migration/MIGRATION_REPORT.md` untouched (historical record).

Run: `grep -rn "frontend-analyzer" migration/MIGRATION_MODE.md .opencode .agents | grep -v REPORT`
Expected: no hits outside historical reports.

- [ ] **Step 5: Validate + commit**

Run: `pnpm vitest run scripts/verify-flutter-tracker.spec.ts && pnpm run verify-flutter-tracker --check`
Expected: PASS + OK (validator now resolves `react-codebase-auditor` on disk).

```bash
git add .opencode/agents/migration .agents/agents/migration migration/MIGRATION_MODE.md
git commit -m "refactor(migration): evolve agent roster to v1.1 write-authority model"
```

---

### Task 5: Add the 9 new agents (both directories)

**Files:**
- Create in BOTH `.opencode/agents/migration/` and `.agents/agents/migration/`: `dependency-mapping.yaml`, `runtime-parity.yaml`, `protocol-event.yaml`, `conversation-engine.yaml`, `tool-integration.yaml`, `slot-plugin.yaml`, `flutter-integration.yaml`, `e2e-replay.yaml`, `migration-gatekeeper.yaml`

**Interfaces:**
- Produces: agent ids consumed by tracker `owner` values in Task 10 and by `knownAgents()`.

- [ ] **Step 1: Write the nine manifests**

`dependency-mapping.yaml`:

```yaml
interface:
  display_name: "Dependency Mapping Agent"
  short_description: "Maps every npm dependency of migrated surfaces to pub equivalents or explicit decisions."
  default_prompt: "Inventory npm dependencies of each audited React package and decide per dependency: maintained pub package, adapter, custom implementation, or not-applicable (with reason). Record decisions in migration/audit/dependency-inventory.md and the tracker rows you co-own. Prefer maintained dependencies over hand-rolling; never silently substitute a fake for a real capability."
```

`runtime-parity.yaml`:

```yaml
interface:
  display_name: "Runtime Parity Agent"
  short_description: "Implements Flutter Connection/Session/Workspace/Projection/PendingInteraction runtimes."
  default_prompt: "Port the React-free runtime layer: resident sessions consuming live mux/host frames, workspace list semantics (baseline, incremental upsert/remove, ordering, tombstones, optimistic insertion), ProjectionValueStore seeded from history and updated by session/projection frames, pending-wait prioritization across questions/approvals/plan review, and connection-generation state with disconnect cleanup. Integrate through Riverpod with $riverpod-runtime-integration patterns; set Integrated on your rows only when real Harness contracts are wired with no synthetic substitution."
```

`protocol-event.yaml`:

```yaml
interface:
  display_name: "Protocol/Event Agent"
  short_description: "Preserves SessionEventMap, event ordering, streaming frames, reconnect, and RPC contracts."
  default_prompt: "Extract contracts from the Harness TypeScript definitions using $harness-api-contract-extraction, $session-eventmap-analysis, and $stream-frame-analysis; never invent or simplify wire shapes for Dart convenience. Own protocol/event tracker rows: event ordering, required-on-read semantics, ignorable envelopes, mux/host frame handling, reconnect generations, gap recovery, resync. Set Integrated only with real transports wired end-to-end."
```

`conversation-engine.yaml`:

```yaml
interface:
  display_name: "Conversation Engine Agent"
  short_description: "Ports ConversationNode assembly: definitions, contexts, view builders, snapshots."
  default_prompt: "Using $conversation-node-analysis, port the assembly pipeline: contiguous event windows folded through event definitions into contexts/state, rendered by view builders into a deterministic ConversationSnapshot replayable by event sequence. Cover streaming tail isolation, turn grouping, step summaries, compaction checkpoints, retry/error tails, tool nesting, older-history prepend, and live append. Set Integrated on your rows when snapshots replay identically from the real session log."
```

`tool-integration.yaml`:

```yaml
interface:
  display_name: "Tool Integration Agent"
  short_description: "Splits tool lifecycle/topology from rendering; ports the presentation registry."
  default_prompt: "Using $tool-topology-analysis, keep call/result pairing and recursive subCalls topology in the runtime layer and rendering behind a ToolPresentationRegistry (terminal, read, diff, search, web, todo, ask-question, approval, generic) so tools register renderers instead of editing a central switch. Test nested topologies with out-of-order, partial, failed, and retried events. Set Integrated when real runtime pairing feeds the registry."
```

`slot-plugin.yaml`:

```yaml
interface:
  display_name: "Slot/Plugin Agent"
  short_description: "Ports the SlotRegistry and capability/plugin contribution lifecycle."
  default_prompt: "Using $slot-plugin-migration, implement DshSlotRegistry with register/unregister/inject/resolve/render lifecycle mirroring ui-slots, plus the Flutter capability registry replacing the client module loader (host capabilities -> feature registry -> lazy initialization). Feature contributions communicate through slots and services, never direct feature-to-feature imports. Set Integrated when conversation/tool/sidebar/settings contributions flow through the registry."
```

`flutter-integration.yaml`:

```yaml
interface:
  display_name: "Flutter Integration Agent"
  short_description: "Wires migrated widgets into Riverpod, routing, shell, and real Harness APIs."
  default_prompt: "Take Migrated items and connect them to real Harness services/events/state/platform dependencies using $riverpod-runtime-integration: Riverpod providers over the runtime layer, go_router routes matching the slot composition graph, shell boot, and API consumers generated from extracted contracts. Integrated means working without production synthetic substitution; record integrationPoints on every row you advance."
```

`e2e-replay.yaml`:

```yaml
interface:
  display_name: "E2E Replay Agent"
  short_description: "Replays identical Harness event streams against React and Flutter and diffs semantics."
  default_prompt: "Using $semantic-parity-replay, build replay fixtures from real session logs (prompt -> user message -> assistant tokens -> reasoning -> tool calls/results -> final response, including reconnect and gap scenarios), run them through both apps/web and apps/flutter, and diff state transitions, event ordering, conversation nodes, tool topology, interaction state, projections, and final output. Write diffs to migration/parity-reports/ as Gatekeeper evidence; you hold no status authority."
```

`migration-gatekeeper.yaml`:

```yaml
interface:
  display_name: "Migration Gatekeeper"
  short_description: "Sole authority for Verified; reviews evidence that lives outside the tracker."
  default_prompt: "You alone set Verified and perform demotions. Never infer evidence from tracker fields: verify the external bundle per item (test command + output, replay fixture + diff, source references, parity reports), confirm runtime/streaming/reconnect/interaction/platform parity and absence of production synthetic fallback, then run pnpm run verify-flutter-tracker --strict. Promote legacyVerified items only when prior evidence satisfies v1.1 gates. Record approvedBy/approvedAt in the evidence block you accept."
```

- [ ] **Step 2: Validate + commit**

Run: `pnpm run verify-flutter-tracker --check && ls .opencode/agents/migration | wc -l && ls .agents/agents/migration | wc -l`
Expected: OK; both directories contain 18 YAMLs.

```bash
git add .opencode/agents/migration .agents/agents/migration
git commit -m "feat(migration): add nine v1.1 stage and gatekeeper agents"
```

---

### Task 6: Add the 10 new skills (both directories)

**Files:**
- Create in BOTH `.opencode/skills/<name>/SKILL.md` and `.agents/skills/<name>/SKILL.md` for: `harness-api-contract-extraction`, `session-eventmap-analysis`, `stream-frame-analysis`, `conversation-node-analysis`, `tool-topology-analysis`, `slot-plugin-migration`, `riverpod-runtime-integration`, `semantic-parity-replay`, `dependency-mapping`, `tracker-validation`

**Interfaces:**
- Consumes: agent mandates from Tasks 4–5 reference these by `$name`.
- Produces: skill documents following the existing SKILL.md frontmatter format (`name`, `description`).

- [ ] **Step 1: Write the ten SKILL.md files**

Each file uses the existing two-field frontmatter. Content per skill:

`harness-api-contract-extraction/SKILL.md`:

```markdown
---
name: harness-api-contract-extraction
description: Use when Flutter needs a Harness API/RPC contract — extract it mechanically from the TypeScript definitions/RPC gateway into Dart; hand-invented or simplified contracts are forbidden.
---

# Harness API Contract Extraction

1. Locate the authoritative TS definition (RPC gateway, Service Definition, or wire type) for the surface.
2. Transcribe request/response fields, unions (discriminant tags), error modes, and versioning into Dart types; closed unions end in exhaustive switches.
3. Preserve opaque branded ids as wrapped classes, never bare `String`.
4. Generate/refresh a fixture round-trip test proving the Dart model parses a real captured payload.
5. Record the TS source path in the tracker row's `source`/notes.

Guardrails: never widen/narrow optionality to fit Dart ergonomics; never rename wire fields; if the TS contract is ambiguous, stop and flag the Protocol/Event Agent instead of guessing.
```

`session-eventmap-analysis/SKILL.md`:

```markdown
---
name: session-eventmap-analysis
description: Use when analyzing or porting SessionEventMap semantics — event kinds, required-on-read defaults, ignorable envelopes, and declaration-merging extensibility.
---

# SessionEventMap Analysis

1. Enumerate event kinds from the TS `SessionEventMap` and their payloads; note `@mode`/`@param` JSDoc contracts.
2. Mark each member required-on-read by default vs `ignorable: true`; a Flutter build that cannot type an event refuses the log, matching Harness.
3. Capture ordering guarantees and merge-extensible vs closed unions (closed ends in `assertNever` analogues in Dart).
4. Emit a Dart event vocabulary with per-kind decoders plus an unknown-kind policy identical to Harness.
5. Test: replay a captured session log; decode counts must match the TS projection.

Guardrails: never drop event kinds to shrink the Dart surface; unknown kinds fail loud.
```

`stream-frame-analysis/SKILL.md`:

```markdown
---
name: stream-frame-analysis
description: Use when porting mux/host frame handling — connection generations, readiness, reconnect, backoff, gap recovery, and resync semantics.
---

# Stream Frame Analysis

1. Map the mux and host frame vocabularies from `packages/client/connection` and the SDK transport.
2. Model ConnectionGeneration: frames are generation-scoped; disconnect clears generation-bound state; `hostDescription` exists only after readiness.
3. Specify reconnect: attempt/backoff, resync, history/projection replay, higher-seq-wins for projections.
4. Define the Flutter pump: persistent per-session streams feeding Session -> assembler -> Riverpod; HTTP request completion is NOT delivery.
5. Test: forced-disconnect mid-stream recovers without refresh; no duplicate or lost frames across resync.

Acceptance scenario: send prompt -> user message immediate -> streamed tokens/reasoning/tools -> final response with NO refresh, reload, or polling.
```

`conversation-node-analysis/SKILL.md`:

```markdown
---
name: conversation-node-analysis
description: Use when porting ConversationNode assembly — event windows folded through definitions into contexts/state, rendered by view builders into deterministic snapshots.
---

# ConversationNode Analysis

1. Inventory node definitions (assistant, reasoning, tool, compaction, retry/error, step groups) from the client architecture note and `ui-conversation`.
2. Port the pipeline: contiguous event window -> ConversationNodeDefinition<T> fold -> ConversationContext<T>/State<T> -> ViewBuilder -> snapshot.
3. Guarantee deterministic replay by event sequence: same log prefix => same snapshot (reload, reconnect, prepend, append).
4. Isolate the streaming tail: the in-flight turn renders separately from settled nodes.
5. Test: golden snapshots for grouped turns, nested tools, compaction checkpoints, retry tails, and 10K+ event streams.

Guardrails: no giant kind-switch in Session; new behavior arrives as node definitions.
```

`tool-topology-analysis/SKILL.md`:

```markdown
---
name: tool-topology-analysis
description: Use when porting tool call lifecycle — runtime-owned callId pairing, recursive subCalls topology, and the split from presentation.
---

# Tool Topology Analysis

1. Runtime owns pairing: match calls to results by callId, maintain lifecycle (pending/partial/complete/failed/retried), project recursive subCalls trees.
2. Presentation consumes projected nodes only; renderers never pair or infer topology.
3. Handle out-of-order events (result before call, late results), partial argument streaming, and failure tails.
4. Port ToolPresentationRegistry keyed by tool kind with a generic fallback; tools register renderers, no central switch edits.
5. Test: A->B->C nesting, sibling D, out-of-order and retried events produce identical trees in React and Flutter replays.
```

`slot-plugin-migration/SKILL.md`:

```markdown
---
name: slot-plugin-migration
description: Use when porting ui-slots or plugin composition — SlotRegistry declarations, dynamic registration, teardown, renderer composition, and the capability registry replacing the module loader.
---

# Slot/Plugin Migration

1. Port DshSlotRegistry: register/unregister/inject/resolve/render with teardown on plugin disposal.
2. Replace `__DSH_BOOT__`/module loading with a Flutter capability registry: host capabilities -> feature registry -> lazy/conditional initialization.
3. Features contribute through slots and services; direct feature-to-feature imports are forbidden.
4. Compose renderers deterministically (documented slot precedence); unknown slots fail loud.
5. Test: registration order independence, disposal removes contributions, conversation/tool/sidebar/settings slots resolve.
```

`riverpod-runtime-integration/SKILL.md`:

```markdown
---
name: riverpod-runtime-integration
description: Use when wiring Flutter widgets to runtime state — Riverpod providers over Connection/Session/Workspace/Projection/Interaction runtimes without synthetic fallbacks.
---

# Riverpod Runtime Integration

1. Expose each runtime as a Riverpod provider family/notifier fed by real streams; widgets never own sockets, timers, or polling.
2. useSyncExternalStore semantics map to provider subscriptions: same-store identity, synchronous first frame, dispose-safe.
3. Explicit > implicit: defaults resolve in an explicit resolve(request): Spec step in the owning implementation, never hidden `?? default` inside run().
4. Production synthetic fallback is forbidden; replay/offline adapters only via declared runtimeMode.
5. Test: provider state transitions driven by replayed frames; widget rebuilds without manual refresh.
```

`semantic-parity-replay/SKILL.md`:

```markdown
---
name: semantic-parity-replay
description: Use when proving React-vs-Flutter behavioral parity — replay identical Harness event streams through both frontends and diff semantic output.
---

# Semantic Parity Replay

1. Build fixtures from real session logs covering: prompt ack, token streams, reasoning, tool calls/results, compaction, retry, reconnect+gap, projections, pending interactions.
2. Drive both apps/web and apps/flutter from the same fixture; capture state transitions, event ordering, conversation nodes, tool topology, interaction state, projections, final output.
3. Diff semantically (normalized), not pixel-wise; visual comparison belongs to $flutter-ui-visual-check after Integration.
4. Store fixtures under `apps/flutter/test/goldens/replay/` and reports in `migration/parity-reports/`.
5. A diff is a blocker: fix Flutter to match React semantics — never normalize the fixture to hide a difference.
```

`dependency-mapping/SKILL.md`:

```markdown
---
name: dependency-mapping
description: Use when mapping npm dependencies of migrated React surfaces to Flutter/pub — maintained pub, adapter, custom, or not-applicable decisions with recorded rationale.
---

# Dependency Mapping

1. List npm dependencies per audited package (imports, not dev tooling).
2. Decide per dependency: maintained pub package > adapter > custom > not-applicable; record rationale and the pub version.
3. Hand-rolling is justified only when it deletes owned code and tests; otherwise prefer maintained packages.
4. Platform plugins need both web and macOS stories (conditional imports where desktop-only).
5. Output: migration/audit/dependency-inventory.md sections per package + tracker row updates.
```

`tracker-validation/SKILL.md`:

```markdown
---
name: tracker-validation
description: Use when reading or writing migration/migration-tracker.json — the v1.1 schema, write-authority partition, and the executable verify-flutter-tracker gate.
---

# Tracker Validation

1. Schema: statuses `Not Started -> Audited -> In Progress -> Migrated -> Integrated -> Verified`; parity dims use `not-applicable|missing|partial|pass|fail`; see the design spec §3 for every field.
2. Write authority: Auditor=Audited, Package Migration=Migrated, Integration-stage agents=Integrated, Gatekeeper=Verified/demotions; the Tracker Agent performs atomic writes only.
3. Evidence lives outside the tracker: test output, replay diffs, parity reports; `parityCheck: pass` is a claim, never proof.
4. After ANY tracker edit run: `pnpm run verify-flutter-tracker --check` (CI mode). Completion claims additionally require `--strict`.
5. Synthetic fallback: live=forbidden, replay=fixtures allowed, offline=declared adapters only (`adapter-of:` notes).
```

- [ ] **Step 2: Mirror to `.agents/skills/`**

```bash
for s in harness-api-contract-extraction session-eventmap-analysis stream-frame-analysis conversation-node-analysis tool-topology-analysis slot-plugin-migration riverpod-runtime-integration semantic-parity-replay dependency-mapping tracker-validation; do
  cp -r ".opencode/skills/$s" ".agents/skills/$s"
done
```

- [ ] **Step 3: Verify + commit**

Run: `ls .opencode/skills | wc -l && ls .agents/skills | wc -l`
Expected: equal counts (25 each).

```bash
git add .opencode/skills .agents/skills
git commit -m "feat(migration): add ten v1.1 domain skills"
```

---

### Task 7: Update `migration-mode` and `migration-code-review` skills (both directories)

**Files:**
- Modify: `.opencode/skills/migration-mode/SKILL.md` + mirror
- Modify: `.opencode/skills/migration-code-review/SKILL.md` + mirror

- [ ] **Step 1: Rewrite `migration-mode/SKILL.md`**

Replace the tracker-contract, workflow, and anti-pattern sections to encode: v1.1 lifecycle and definitions (spec §3.1 verbatim), the write-authority table (spec §4), the real gate (`pnpm run verify-flutter-tracker --check` / `--strict`), the synthetic-fallback policy (spec §3.4), the 18-agent roster with `$` invocations, entry condition (M0 inventories exist under `migration/audit/`), and exit criteria = the spec §9 completion-gate conjunction. Keep the document under 120 lines.

- [ ] **Step 2: Extend `migration-code-review/SKILL.md`**

Add a v1.1 review checklist section: reviewer must confirm (a) no status advanced without its owning agent, (b) `Verified` carries a complete external evidence bundle approved by `migration-gatekeeper`, (c) no `live` runtimeMode item substitutes synthetic adapters, (d) `pnpm run verify-flutter-tracker --check` passes on the PR head, (e) demoted `legacyVerified` items retain intact `legacyVerification` blocks.

- [ ] **Step 3: Mirror + commit**

```bash
for s in migration-mode migration-code-review; do cp ".opencode/skills/$s/SKILL.md" ".agents/skills/$s/SKILL.md"; done
git add .opencode/skills/migration-mode .opencode/skills/migration-code-review .agents/skills/migration-mode .agents/skills/migration-code-review
git commit -m "docs(migration): rework migration-mode and review skill for v1.1 gates"
```

---

### Task 8: M0 audit — inventories 1–6

**Files:**
- Create: `migration/audit/client-package-inventory.md`, `runtime-service-inventory.md`, `slot-inventory.md`, `api-contract-inventory.md`, `event-inventory.md`, `conversation-node-inventory.md`

**Interfaces:**
- Consumes: repository sources (read-only).
- Produces: inventory documents whose cited paths feed Task 10 tracker rows. Every inventory ends with a `## Sources` section listing repo paths.

- [ ] **Step 1: Read the authoritative sources**

Read (at minimum): `packages/client/README.md`, `packages/client/AGENTS.md`, `packages/client/runtime/README.md`, `packages/client/connection/README.md`, `packages/client/ui-slots/` (README + src index), `packages/client/modules/`, `packages/client/ui-conversation/README.md`, the conversation-node assembly note (`.agents/notes/implemented/architecture/2026-08-09-client-conversation-node-assembly.md`), `docs/module-graph.md`, `packages/client/*/src/index.ts` export lists.

- [ ] **Step 2: Write the six inventories**

Each inventory: purpose (2 lines), per-item entries (name, owning package, source path, exported symbols, runtime contract, Flutter disposition `direct|adapter|custom|not-applicable`), open questions, `## Sources`. Required coverage:

1. `client-package-inventory.md` — every `packages/client/*` package (~37) with one-line responsibility.
2. `runtime-service-inventory.md` — session/workspace/projection/pending-interaction/settings-scope/remote-event services with their store semantics (baseline, incremental, ordering, tombstones, generations).
3. `slot-inventory.md` — every declared slot key and contributor.
4. `api-contract-inventory.md` — host.describe, session.*, workspace.*, approval/question/plan responses, commands, feedback, settings, attachments, reference resolution; each with TS definition path.
5. `event-inventory.md` — SessionEventMap members with ignorable/required-on-read flags.
6. `conversation-node-inventory.md` — node definitions, contexts, view builders, snapshot semantics.

- [ ] **Step 3: Verify citations resolve**

```bash
grep -hoE '(packages|apps|docs)/[A-Za-z0-9/._-]+' migration/audit/{client-package,runtime-service,slot,api-contract,event,conversation-node}-inventory.md | sort -u | while read -r p; do test -e "$p" || echo "MISSING: $p"; done
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add migration/audit
git commit -m "docs(migration): M0 inventories for packages, runtime, slots, APIs, events, nodes"
```

---

### Task 9: M0 audit — inventories 7–11

**Files:**
- Create: `migration/audit/primitive-inventory.md`, `platform-inventory.md`, `dependency-inventory.md`, `plugin-lifecycle-inventory.md`, `interaction-inventory.md`

- [ ] **Step 1: Read + write the five inventories**

Sources: `packages/client/ui-primitives/src/index.ts` (actual exports — this fixes the Markdown→TerminalBlock defect), `apps/web/`, `packages/extensions/cordis-client-runner/`, `packages/extensions/ui-cordis/`, `packages/client/hmr/`, `packages/interaction/`, `packages/boot/`, pubspec/npm manifests.

Required coverage:

7. `primitive-inventory.md` — actual exports (TerminalBlock, ReadBlock, DiffBlock, SearchBlock, WebBlock, CodeBlock, JsonBlock, MarkdownText, MessageText, JsonTree, icons, …) with Flutter counterpart status.
8. `platform-inventory.md` — clipboard, pickers, drag-drop, keyboard, window, deep links, history, selection, external URLs, native boundaries; web vs macOS deltas.
9. `dependency-inventory.md` — npm→pub decisions per migrated package (with Dependency Mapping Agent mandate).
10. `plugin-lifecycle-inventory.md` — client modules, `__DSH_BOOT__` graph, plugin injection/loading/lifecycle, cordis-client-runner, HMR disposition (dev-only/not-applicable with reason).
11. `interaction-inventory.md` — approval, ask-user, permission, plan-review routing, pending-wait prioritization, reconnect behavior.

- [ ] **Step 2: Verify citations resolve**

Same loop as Task 8 Step 3 over the five new files. Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add migration/audit
git commit -m "docs(migration): M0 inventories for primitives, platform, deps, plugins, interactions"
```

---

### Task 10: Apply audit corrections + add missing tracker rows

**Files:**
- Modify: `migration/migration-tracker.json`

**Interfaces:**
- Consumes: Tasks 8–9 inventories; gate from Task 2; agent ids from Tasks 4–5.
- Produces: the complete v1.1 tracker passing `--check`.

- [ ] **Step 1: Correct legacy rows**

Per the inventories: fix wrong `source` mappings (Markdown → `packages/client/ui-primitives/src/MarkdownText.tsx`; verify every other row the same way), fill real `responsibility` text (replace all "pending M0 re-audit" placeholders), set honest `replacementType` (e.g. hmr rows → `not-applicable` with reason "dev-only Vite HMR replaced by Flutter hot reload"), and refine `integrationLevel`.

- [ ] **Step 2: Add the missing rows**

Append rows (status `Audited`, owner `react-codebase-auditor`, runtimeMode `replay`, parity dims `missing`/`not-applicable`, planned `flutterTarget` paths under `apps/flutter/lib/src/…`) at minimum:

```
runtime.session-store            runtime   packages/client/runtime
runtime.workspace-store          runtime   packages/client/runtime
runtime.projection-store         runtime   packages/client/runtime
runtime.pending-interactions     runtime   packages/client/runtime
runtime.remote-event-dispatch    runtime   packages/client/runtime
runtime.settings-scope           runtime   packages/client/runtime
runtime.host-born-sessions       runtime   packages/client/runtime
runtime.reconnect-generations    runtime   packages/client/connection
protocol.session-eventmap        protocol  packages/client/runtime
protocol.mux-host-frames         protocol  packages/client/connection
protocol.streaming-frames        protocol  packages/client/connection
protocol.rpc-contracts           protocol  packages/client/modules
protocol.reconnect-gap-recovery  protocol  packages/client/connection
slot.registry                    slot      packages/client/ui-slots
slot.tool-renderer-registry      slot      packages/client/ui-tool
modules.client-plugin-loading    slot      packages/client/modules
plugin.client-lifecycle          slot      packages/extensions/cordis-client-runner
component.brand-official         component packages/client/ui-brand-official
conversation.node-assembler      runtime   packages/client/ui-conversation
conversation.streaming-tail      runtime   packages/client/ui-conversation
conversation.turn-grouping       runtime   packages/client/ui-conversation
conversation.step-summary        runtime   packages/client/ui-conversation
conversation.compaction          runtime   packages/client/ui-conversation
conversation.retry-error-states  runtime   packages/client/ui-conversation
state.streaming-assistant        state     packages/client/runtime
state.streaming-reasoning        state     packages/client/runtime
state.streaming-tool             state     packages/client/runtime
tool.lifecycle-pairing           runtime   packages/client/ui-tool
tool.subcall-topology            runtime   packages/client/ui-tool
interaction.plane                runtime   packages/interaction
settings.runtime-scope           runtime   packages/client/ui-settings
locale.service-dictionaries      runtime   packages/client/locale
subagent.runtime-link            runtime   packages/client/ui-subagent
reference.composer-integration   runtime   packages/client/ui-reference
input-trigger.suggestion-engine  runtime   packages/client/ui-input-trigger
platform.keyboard-shortcuts      platform  apps/web
platform.drag-drop               platform  apps/web
platform.open-external           platform  apps/web
```

Refine sources/anchors from the inventories where they differ; add further rows the inventories expose.

- [ ] **Step 3: Validate**

Run: `pnpm run verify-flutter-tracker --check`
Expected: OK. Investigate any violation as a data bug, never by weakening the gate.

- [ ] **Step 4: Commit**

```bash
git add migration/migration-tracker.json
git commit -m "refactor(migration): apply M0 audit corrections and add missing v1.1 rows"
```

---

### Task 11: Regenerate TRACKER.md + update MIGRATION_MODE.md

**Files:**
- Modify: `migration/TRACKER.md`, `migration/MIGRATION_MODE.md`

- [ ] **Step 1: Regenerate TRACKER.md**

Replace hand-written tables with a generated projection:

```bash
python3 - <<'PY'
import json, collections
items = json.load(open('migration/migration-tracker.json'))
by_status = collections.Counter(i['status'] for i in items)
by_cat = collections.Counter(i['category'] for i in items)
lines = ['# Migration Tracker (generated)', '',
         f"Total: {len(items)} items", '',
         '## By status', '']
for k, v in sorted(by_status.items()):
    lines.append(f'- {k}: {v}')
lines += ['', '## By category', '']
for k, v in sorted(by_cat.items()):
    lines.append(f'- {k}: {v}')
lines += ['', '| id | category | status | owner | runtimeMode |', '|---|---|---|---|---|']
for i in sorted(items, key=lambda x: x['id']):
    lines.append(f"| {i['id']} | {i['category']} | {i['status']} | {i['owner']} | {i['runtimeMode']} |")
open('migration/TRACKER.md', 'w').write('\n'.join(lines) + '\n')
print('regenerated')
PY
```

- [ ] **Step 2: Update MIGRATION_MODE.md**

Update: agent roster line (18 agents incl. `react-codebase-auditor` + the nine new), skill roster line (+10 new), lifecycle section → v1.1 states with one-line definitions, gate commands (`verify-flutter-tracker --check` / `--strict`), entry condition (M0 inventories present), exit criteria → spec §9 conjunction. Keep the file coherent; do not leave v0 lifecycle prose anywhere (`grep -n "Tested" migration/MIGRATION_MODE.md` must return no lifecycle hits).

- [ ] **Step 3: Commit**

```bash
git add migration/TRACKER.md migration/MIGRATION_MODE.md
git commit -m "docs(migration): regenerate tracker projection and v1.1 mode documentation"
```

---

### Task 12: Agent Note + final verification

**Files:**
- Create: `.agents/notes/implemented/process/2026-08-21-migration-rework-v1.1.md`

- [ ] **Step 1: Write the Agent Note**

Follow `.agents/notes/README.md` conventions (frontmatter/format of neighboring notes). Content: why the 75/75 Verified baseline was unsound (collapsed migration/integration/verification), what v1.1 changes (lifecycle, authority partition, executable gate, evidence-outside-tracker rule, 11 inventories), and the decision that legacy items demote with preserved `legacyVerification` rather than silent resets.

- [ ] **Step 2: Run the verification battery**

```bash
pnpm vitest run scripts/verify-flutter-tracker.spec.ts
pnpm run verify-flutter-tracker --check
pnpm run typecheck
git diff --check
```
Expected: spec PASS; gate OK; typecheck clean; no whitespace errors.

- [ ] **Step 3: Final consistency sweep**

```bash
grep -rn "frontend-analyzer" .opencode .agents migration/MIGRATION_MODE.md docs/superpowers 2>/dev/null | grep -v "specs/2026-08-21"
diff <(ls .opencode/agents/migration) <(ls .agents/agents/migration) && echo AGENTS-MIRRORED
diff <(ls .opencode/skills) <(ls .agents/skills) && echo SKILLS-MIRRORED
```
Expected: no stale references; both MIRRORED echoes.

- [ ] **Step 4: Commit**

```bash
git add .agents/notes
git commit -m "docs(agents): add migration rework v1.1 agent note"
```

---

## Self-Review Notes

- Spec coverage: §3 schema → Tasks 1–3, 10; §4 authority → Tasks 4–5, 7; §5 roster → Tasks 4–5; §6 skills → Tasks 6–7; §7 gate → Tasks 1–2; §8 M0 → Tasks 8–10; §9 gates → Task 7/11 exit criteria; §10 acceptance → Task 12; §11 testing → Tasks 1–2 specs + Task 12 battery.
- Type consistency: `checkItemSchema/checkItemPaths/checkStatusRules/checkCrossReferences/validateTracker/main` signatures align across Tasks 1–2; `statusAtLeast` reused in Task 2; agent ids in tracker rows match YAML filenames exactly.
- Known execution-order coupling: Task 4 (rename to `react-codebase-auditor`) must precede any gate run over the Task 3 tracker, because `owner: react-codebase-auditor` must resolve via `knownAgents()`.
