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
