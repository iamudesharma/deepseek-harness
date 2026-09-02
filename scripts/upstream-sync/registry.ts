// @ts-nocheck
import type { ApiDiff, ChangeRegistry, ChangeRegistryEntry, FlutterImpact, StreamDiff } from './types.ts'
import { classifyFile } from './classifier.ts'

export function buildChangeRegistry(
  apiDiff: ApiDiff,
  streamDiff: StreamDiff,
  flutterImpact: FlutterImpact,
  fileList: string[],
  oldSha: string,
  newSha: string,
): ChangeRegistry {
  const generatedAt = new Date().toISOString()
  const entries: ChangeRegistryEntry[] = []
  let counter = 0

  function nextId(prefix: string): string {
    counter++
    return `${prefix}-${String(counter).padStart(4, '0')}`
  }

  for (const d of apiDiff.entries) {
    const _category = classifyFile(d.sourceFiles[0] ?? 'packages/api/gateway/src/index.ts')
    void _category
    const affectedFlutterFiles = flutterImpact.entries.find(e => e.id === d.id)?.affectedFiles ?? []
    const reactStatus = d.kind === 'added' ? 'MISSING' as const : d.kind === 'removed' ? 'PASS' as const : 'OUTDATED' as const
    const flutterStatus = affectedFlutterFiles.length ? 'OUTDATED' as const : d.kind === 'added' ? 'MISSING' as const : 'PASS' as const
    entries.push({
      id: nextId('CR'),
      oldValue: d.oldValue,
      newValue: d.newValue,
      category: 'API' as const,
      severity: d.severity,
      reactStatus,
      flutterStatus,
      hostStatus: d.kind === 'removed' ? 'MISSING' : 'CHANGED',
      migrationStatus: 'Detected',
      firstSeenUpstreamSha: oldSha,
      lastSeenUpstreamSha: newSha,
      sourceFiles: d.sourceFiles,
      affectedFlutterFiles,
      description: `[API ${d.kind}] ${d.description}`,
    })
  }

  for (const s of streamDiff.entries) {
    const affectedFlutterFiles = flutterImpact.entries.filter(e => e.category === 'STREAM').flatMap(e => e.affectedFiles).slice(0, 3)
    entries.push({
      id: nextId('CR'),
      oldValue: s.oldValue,
      newValue: s.newValue,
      category: 'STREAM' as const,
      severity: s.severity,
      reactStatus: 'UNKNOWN' as const,
      flutterStatus: 'UNKNOWN' as const,
      hostStatus: 'CHANGED',
      migrationStatus: 'Detected',
      firstSeenUpstreamSha: oldSha,
      lastSeenUpstreamSha: newSha,
      sourceFiles: ['packages/api/gateway/src/stream-protocol.ts'],
      affectedFlutterFiles,
      description: `[STREAM ${s.kind}:${s.field}] ${s.description}`,
    })
  }

  // File-level changes that are not API/stream but may impact Flutter (e.g., BUILD, SECURITY, DOCS ignored)
  // Only add P2+ for REACT/CORE changes that touch files Flutter mirrors
  for (const file of fileList) {
    const cat = classifyFile(file)
    if (['DOCS', 'BUILD', 'TEST', 'OTHER'].includes(cat)) continue
    // If already covered by API diff sourceFiles, skip
    const already = entries.some(e => e.sourceFiles.includes(file))
    if (already) continue
    // Add informational entry for REACT behavioral changes
    if (cat === 'REACT' || cat === 'CLIENT') {
      entries.push({
        id: nextId('CR'),
        oldValue: file,
        newValue: file,
        category: 'REACT' as const,
        severity: 'P2',
        reactStatus: 'PASS' as const,
        flutterStatus: 'UNKNOWN' as const,
        hostStatus: 'PASS',
        migrationStatus: 'Detected',
        firstSeenUpstreamSha: oldSha,
        lastSeenUpstreamSha: newSha,
        sourceFiles: [file],
        affectedFlutterFiles: [],
        description: `[REACT] File changed: ${file} — verify Flutter parity for behavior/state fallback`,
      })
    }
  }

  entries.sort((a, b) => {
    const order = { P0: 0, P1: 1, P2: 2, P3: 3 } as const
    if (order[a.severity] !== order[b.severity]) return order[a.severity] - order[b.severity]
    return a.id.localeCompare(b.id)
  })

  return {
    generatedAt,
    oldSha,
    newSha,
    total: entries.length,
    entries,
  }
}
