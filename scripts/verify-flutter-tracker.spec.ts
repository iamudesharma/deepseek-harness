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
      source: '',
      category: 'widget' as never,
      status: 'Tested' as never,
      replacementType: 'ported' as never,
      runtimeMode: 'hybrid' as never,
      responsibility: '',
      reactPackage: '',
    }))
    expect(violations).toHaveLength(7)
    expect(violations.every(v => v.includes('component.ui-primitives.Button'))).toBe(true)
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
      .toEqual(['component.ui-primitives.Button: platformParity {web,macos} is required for category "screen"'])
  })

  it('requires a non-empty integrationLevel subset', () => {
    expect(checkItemSchema(validItem({ integrationLevel: [] })))
      .toEqual(['component.ui-primitives.Button: integrationLevel must be a non-empty array'])
    expect(checkItemSchema(validItem({ integrationLevel: ['nope'] as never }))[0])
      .toContain('integrationLevel')
  })
})

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
    expect(violations.every(v => v.startsWith('component.ui-primitives.Button:'))).toBe(true)
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
    const other = validItem({ id: 'style.tokens', flutterTarget: TARGET, owner: 'nobody' })
    const violations = checkCrossReferences([validItem(), other, validItem()], ['react-codebase-auditor'])
    expect(violations).toContain('duplicate tracker id: component.ui-primitives.Button')
    expect(violations).toContain('component.ui-primitives.Button: dependsOn references unknown id "theme.tokens"')
    expect(violations).toContain(`flutterTarget claimed by multiple items: ${TARGET}`)
    expect(violations.some(v => v.includes('owner "nobody" is not a known migration agent'))).toBe(true)
  })
})

describe('validateTracker', () => {
  it('aggregates item and cross-reference violations', () => {
    const violations = validateTracker([validItem({ id: '' })], { knownAgentIds: ['react-codebase-auditor'], exists: existsMap([]) })
    expect(violations.length).toBeGreaterThan(0)
  })

  it('enforces strict mode only when nothing is Verified', () => {
    const options = { knownAgentIds: ['react-codebase-auditor'], exists: existsMap([REACT, 'packages/client/ui-primitives']) }
    expect(validateTracker([validItem({ dependsOn: [] })], { ...options, strict: true })).toEqual([
      'strict mode: at least one Verified item is required to claim migration completion',
    ])
  })
})
