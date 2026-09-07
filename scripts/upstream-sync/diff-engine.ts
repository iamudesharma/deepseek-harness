// @ts-nocheck
import type { ApiContract, ApiDiff, ApiDiffEntry, ApiOperation } from './types.ts'

export function diffApiContracts(oldC: ApiContract, newC: ApiContract): ApiDiff {
  const generatedAt = new Date().toISOString()
  const entries: ApiDiffEntry[] = []

  const oldByEndpoint = new Map<string, ApiOperation>(oldC.operations.map(o => [o.endpoint, o]))
  const newByEndpoint = new Map<string, ApiOperation>(newC.operations.map(o => [o.endpoint, o]))

  const oldEndpoints = new Set(oldC.endpoints)
  const newEndpoints = new Set(newC.endpoints)

  // Removed
  for (const ep of oldC.endpoints) {
    if (!newEndpoints.has(ep)) {
      // Check if it's a dot->slash rename: e.g., settings.describe vs settings/describe
      const slashVariant = ep.replace('.', '/')
      const dotVariant = ep.replace('/', '.')
      let renamedTo: string | null = null
      if (newEndpoints.has(slashVariant)) renamedTo = slashVariant
      else if (newEndpoints.has(dotVariant)) renamedTo = dotVariant
      // Check namespace rename: try to find similar operation under different namespace
      const oldOp = oldByEndpoint.get(ep)!
      const candidateRenames = newC.operations.filter(o => o.operation === oldOp.operation && o.namespace !== oldOp.namespace)
      const pluralCandidate = newC.operations.find(o => pluralVariant(oldOp.namespace) === o.namespace && o.operation === oldOp.operation)

      if (renamedTo) {
        entries.push({
          id: `dot-slash:${ep}->${renamedTo}`,
          kind: 'dot-to-slash',
          oldEndpoint: ep,
          newEndpoint: renamedTo,
          oldValue: ep,
          newValue: renamedTo,
          severity: 'P0',
          description: `Endpoint dot→slash rename: ${ep} → ${renamedTo}. Wire path changes from /api/${ep} to /api/${renamedTo}. Flutter _wireEndpoint handles this but Host gateway exact match may 404 if not updated.`,
          sourceFiles: [oldOp.sourceFile],
        })
      } else if (pluralCandidate || candidateRenames.length === 1) {
        const newEp = (pluralCandidate ?? candidateRenames[0]).endpoint
        const kind = pluralCandidate ? 'pluralization' as const : 'namespace-rename' as const
        entries.push({
          id: `${kind}:${ep}->${newEp}`,
          kind,
          oldEndpoint: ep,
          newEndpoint: newEp,
          oldValue: ep,
          newValue: newEp,
          severity: 'P0',
          description: `Namespace ${kind}: ${ep} → ${newEp}`,
          sourceFiles: [oldOp.sourceFile, (pluralCandidate ?? candidateRenames[0]).sourceFile],
        })
      } else {
        // Check split: one old operation became multiple new ones
        const splits = newC.operations.filter(o => o.operation.startsWith(oldOp.operation) || oldOp.operation.startsWith(o.operation))
        if (splits.length > 1 && splits.length <= 4) {
          entries.push({
            id: `split:${ep}`,
            kind: 'split',
            oldEndpoint: ep,
            newEndpoint: splits.map(s => s.endpoint).join(' + '),
            oldValue: ep,
            newValue: splits.map(s => s.endpoint).join(', '),
            severity: 'P1',
            description: `Endpoint split: ${ep} → ${splits.map(s => s.endpoint).join(' + ')} (e.g., llm.providers → llm/listProviders + llm/listConfigurableProviders)`,
            sourceFiles: [oldOp.sourceFile, ...splits.map(s => s.sourceFile)],
          })
        } else {
          entries.push({
            id: `removed:${ep}`,
            kind: 'removed',
            oldEndpoint: ep,
            newEndpoint: null,
            oldValue: ep,
            newValue: null,
            severity: 'P0',
            description: `Endpoint removed: ${ep} (service ${oldOp.serviceKey}, namespace ${oldOp.namespace}) from ${oldOp.sourceFile}:${oldOp.line}`,
            sourceFiles: [oldOp.sourceFile],
          })
        }
      }
    }
  }

  // Added
  for (const ep of newC.endpoints) {
    if (!oldEndpoints.has(ep)) {
      // Skip if already accounted as dot-slash or rename target
      const already = entries.some(e => e.newEndpoint === ep && (e.kind === 'dot-to-slash' || e.kind === 'namespace-rename' || e.kind === 'pluralization'))
      if (already) continue
      // Check if this is part of split already
      const splitCovered = entries.some(e => e.kind === 'split' && e.newValue?.includes(ep))
      if (splitCovered) continue
      const newOp = newByEndpoint.get(ep)!
      entries.push({
        id: `added:${ep}`,
        kind: 'added',
        oldEndpoint: null,
        newEndpoint: ep,
        oldValue: null,
        newValue: ep,
        severity: 'P2',
        description: `Endpoint added: ${ep} (service ${newOp.serviceKey}, mode ${newOp.mode}) from ${newOp.sourceFile}:${newOp.line}`,
        sourceFiles: [newOp.sourceFile],
      })
    }
  }

  // For overlapping endpoints, check for mode/transport changes, request wrapper, etc.
  for (const ep of oldC.endpoints) {
    if (!newEndpoints.has(ep)) continue
    const oldOp = oldByEndpoint.get(ep)!
    const newOp = newByEndpoint.get(ep)!
    if (oldOp.mode !== newOp.mode) {
      entries.push({
        id: `transport:${ep}`,
        kind: 'transport',
        oldEndpoint: ep,
        newEndpoint: ep,
        oldValue: oldOp.mode,
        newValue: newOp.mode,
        severity: 'P0',
        description: `Transport changed for ${ep}: ${oldOp.mode} → ${newOp.mode}`,
        sourceFiles: [oldOp.sourceFile, newOp.sourceFile],
      })
    }
    if (oldOp.requestShape !== newOp.requestShape && oldOp.requestShape && newOp.requestShape) {
      // Heuristic: check wrapper changes like args wrapping
      const oldHasArgs = oldOp.requestShape.includes('args') || oldOp.args.includes('request')
      const newHasArgs = newOp.requestShape.includes('args') || newOp.args.includes('request')
      if (oldHasArgs !== newHasArgs) {
        entries.push({
          id: `request-wrapper:${ep}`,
          kind: 'request-wrapper',
          oldEndpoint: ep,
          newEndpoint: ep,
          oldValue: oldOp.requestShape,
          newValue: newOp.requestShape,
          severity: 'P0',
          description: `Request wrapper changed for ${ep}: payload shape differs. Old: ${oldOp.requestShape} New: ${newOp.requestShape}`,
          sourceFiles: [oldOp.sourceFile, newOp.sourceFile],
        })
      }
    }
    // Authorization changes
    if (oldOp.authorization !== newOp.authorization) {
      entries.push({
        id: `auth:${ep}`,
        kind: 'authorization',
        oldEndpoint: ep,
        newEndpoint: ep,
        oldValue: oldOp.authorization,
        newValue: newOp.authorization,
        severity: 'P1',
        description: `Authorization changed for ${ep}: ${oldOp.authorization} → ${newOp.authorization}`,
        sourceFiles: [oldOp.sourceFile, newOp.sourceFile],
      })
    }
  }

  // Specific known breaking patterns from Harness history
  // Detect settings.describe List vs Map, session/page throughSeq etc. by scanning diff in sourceFiles?
  // We'll add synthetic entries if we detect relevant file changes but endpoints unchanged

  const breaking = entries.filter(e => e.severity === 'P0').length
  const additive = entries.filter(e => e.kind === 'added').length

  // Sort: breaking first
  entries.sort((a, b) => {
    const sevOrder = { P0: 0, P1: 1, P2: 2, P3: 3 } as const
    if (sevOrder[a.severity] !== sevOrder[b.severity]) return sevOrder[a.severity] - sevOrder[b.severity]
    return a.id.localeCompare(b.id)
  })

  return {
    generatedAt,
    oldSha: oldC.rev,
    newSha: newC.rev,
    total: entries.length,
    breaking,
    additive,
    entries,
  }
}

function pluralVariant(s: string): string {
  if (s.endsWith('s')) return s.slice(0, -1)
  return s + 's'
}
