// @ts-nocheck
import { writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import type { ApiContract, ApiDiff, ChangeRegistry, FileClassification, FlutterContract, FlutterImpact, ParityReport, ReactContract, StreamContract, StreamDiff, UpstreamState } from './types.ts'

export function generateMarkdownReport(params: {
  state: UpstreamState
  classification: FileClassification
  apiCurrent: ApiContract
  apiPrevious: ApiContract
  apiDiff: ApiDiff
  streamCurrent: StreamContract
  streamPrevious: StreamContract
  streamDiff: StreamDiff
  react: ReactContract
  flutter: FlutterContract
  parity: ParityReport
  impact: FlutterImpact
  registry: ChangeRegistry
  commits: { sha: string, subject: string, author: string, date: string }[]
}): string {
  const { state, classification, apiCurrent, apiPrevious, apiDiff, streamCurrent, streamPrevious: _streamPrevious, streamDiff, react, flutter, parity, impact, registry, commits } = params
  const date = new Date().toISOString().slice(0, 10)
  const shortOld = state.lastSynchronizedSha.slice(0, 8)
  const shortNew = state.currentUpstreamSha.slice(0, 8)

  const p0 = impact.bySeverity['P0'] ?? 0
  const p1 = impact.bySeverity['P1'] ?? 0
  const p2 = impact.bySeverity['P2'] ?? 0
  const p3 = impact.bySeverity['P3'] ?? 0
  const breaking = apiDiff.breaking

  const lines: string[] = []
  lines.push(`# Upstream Sync Report — ${date}`)
  lines.push('')
  lines.push(`> Generated: ${new Date().toISOString()}`)
  lines.push(`> Upstream: ${state.upstreamRepository} @ ${state.upstreamBranch}`)
  lines.push(`> Old SHA: \`${state.lastSynchronizedSha}\` (\`${shortOld}\`) → New SHA: \`${state.currentUpstreamSha}\` (\`${shortNew}\`)`)
  lines.push(`> Local HEAD: \`${state.localForkSha.slice(0, 8)}\`  Merge-base: \`${state.mergeBase.slice(0, 8)}\`  Behind: ${state.behindBy}  Ahead: ${state.aheadBy}`)
  lines.push('')

  lines.push('## Summary')
  lines.push('')
  lines.push('| Metric | Value |')
  lines.push('|---|---|')
  lines.push(`| Commits | ${commits.length} |`)
  lines.push(`| Files changed | ${classification.total} |`)
  lines.push(`| File categories | ${Object.entries(classification.byCategory).filter(([, n]) => n > 0).map(([k, n]) => `${k}:${n}`).join(', ')} |`)
  lines.push(`| API operations (prev → current) | ${apiPrevious.operations.length} → ${apiCurrent.operations.length} |`)
  lines.push(`| API changes | ${apiDiff.total} (breaking: ${breaking}, additive: ${apiDiff.additive}) |`)
  lines.push(`| Stream changes | ${streamDiff.total} |`)
  lines.push(`| React surfaces | ${react.totalSurfaces} |`)
  lines.push(`| Flutter call sites | ${flutter.callSites.length} in ${flutter.filesScanned} files |`)
  lines.push(`| Parity | PASS ${parity.pass} / MISSING ${parity.missing} / INCOMPATIBLE ${parity.incompatible} / UNKNOWN ${parity.unknown} |`)
  lines.push(`| Flutter impact | P0 ${p0} · P1 ${p1} · P2 ${p2} · P3 ${p3} |`)
  lines.push(`| Registry entries | ${registry.total} |`)
  lines.push(`| Parity gate | ${parity.incompatible > 0 || p0 > 0 ? '❌ FAIL' : parity.missing > 0 ? '⚠️ MISSING' : '✅ PASS'} |`)
  lines.push(`| Recommended action | ${p0 > 0 ? 'P0 blocking — do not merge Flutter without fixes' : p1 > 0 ? 'P1 degraded — plan migration branch' : 'safe to create sync branch'} |`)
  lines.push('')

  lines.push('## Commits (upstream..new)')
  lines.push('')
  if (commits.length === 0) lines.push('_No commits — already at upstream_')
  else {
    lines.push('| SHA | Subject | Author | Date |')
    lines.push('|---|---|---|---|')
    for (const c of commits.slice(0, 100)) {
      const short = c.sha.slice(0, 8)
      const subj = c.subject.replace(/\|/g, '\\|').slice(0, 120)
      lines.push(`| \`${short}\` | ${subj} | ${c.author} | ${c.date.slice(0, 10)} |`)
    }
    if (commits.length > 100) lines.push(`| … | … ${commits.length - 100} more | … | … |`)
  }
  lines.push('')

  lines.push('## Files changed by category')
  lines.push('')
  lines.push('| Category | Count | Sample files |')
  lines.push('|---|---|---|')
  for (const [cat, count] of Object.entries(classification.byCategory).sort((a, b) => (b[1] as number) - (a[1] as number))) {
    if ((count as number) === 0) continue
    const sample = classification.files.filter(f => f.category === cat).slice(0, 3).map(f => `\`${f.path}\``).join('<br>')
    lines.push(`| ${cat} | ${count} | ${sample} |`)
  }
  lines.push('')

  lines.push('## API changes')
  lines.push('')
  if (apiDiff.entries.length === 0) lines.push('_No API changes detected_')
  else {
    lines.push('| # | Kind | Endpoint | Severity | Description |')
    lines.push('|---|---|---|---|---|')
    apiDiff.entries.slice(0, 80).forEach((e, i) => {
      const ep = (e.newEndpoint ?? e.oldEndpoint ?? '').replace(/\|/g, '\\|')
      lines.push(`| ${i + 1} | ${e.kind} | \`${ep}\` | ${e.severity} | ${e.description.replace(/\|/g, '\\|').slice(0, 200)} |`)
    })
    if (apiDiff.entries.length > 80) lines.push(`| … | … | … | … | … ${apiDiff.entries.length - 80} more |`)
  }
  lines.push('')

  lines.push('## Stream changes')
  lines.push('')
  if (streamDiff.entries.length === 0) lines.push('_No stream changes_')
  else {
    lines.push('| Field | Kind | Old → New | Severity | Description |')
    lines.push('|---|---|---|---|---|')
    for (const e of streamDiff.entries) {
      lines.push(`| ${e.field} | ${e.kind} | \`${e.oldValue ?? '∅'}\` → \`${e.newValue ?? '∅'}\` | ${e.severity} | ${e.description.slice(0, 160)} |`)
    }
  }
  lines.push('')

  lines.push('### Stream endpoints (current)')
  lines.push('')
  lines.push('| Name | Path | Kind | Source |')
  lines.push('|---|---|---|---|')
  for (const ep of streamCurrent.endpoints) lines.push(`| ${ep.name} | \`${ep.path}\` | ${ep.kind} | \`${ep.sourceFile}\` |`)
  lines.push('')
  lines.push(`Heartbeat: ${streamCurrent.features.heartbeatMs}ms · Reconnect: ${streamCurrent.features.reconnect} · Auth: ${streamCurrent.features.authentication}`)
  lines.push('')

  lines.push('## React vs Flutter parity')
  lines.push('')
  lines.push(`| Status | Count |`)
  lines.push(`|---|---|`)
  lines.push(`| PASS | ${parity.pass} |`)
  lines.push(`| MISSING | ${parity.missing} |`)
  lines.push(`| INCOMPATIBLE | ${parity.incompatible} |`)
  lines.push(`| OUTDATED | ${parity.outdated} |`)
  lines.push(`| UNKNOWN | ${parity.unknown} |`)
  lines.push(`| REMOVED | ${parity.removed} |`)
  lines.push('')
  if (parity.entries.length) {
    lines.push('| API | Status | Sev | React → Flutter | Reason |')
    lines.push('|---|---|---|---|---|')
    for (const e of parity.entries.slice(0, 60)) {
      const reactApi = e.reactApi.replace(/\|/g, '\\|')
      const flutterApi = (e.flutterApi ?? '∅').replace(/\|/g, '\\|')
      lines.push(`| \`${reactApi}\` | ${e.status} | ${e.severity} | \`${flutterApi}\` | ${e.reason.replace(/\|/g, '\\|').slice(0, 140)} |`)
    }
    if (parity.entries.length > 60) lines.push(`| … | … | … | … | … ${parity.entries.length - 60} more |`)
  }
  lines.push('')

  lines.push('## Flutter impact')
  lines.push('')
  lines.push(`| Severity | Count |`)
  lines.push(`|---|---|`)
  lines.push(`| P0 (blocks runtime) | ${p0} |`)
  lines.push(`| P1 (feature broken) | ${p1} |`)
  lines.push(`| P2 (compat risk) | ${p2} |`)
  lines.push(`| P3 (informational) | ${p3} |`)
  lines.push('')
  if (impact.entries.length) {
    lines.push('| ID | Change | Sev | Affected Flutter files | Required action |')
    lines.push('|---|---|---|---|---|')
    for (const e of impact.entries.slice(0, 60)) {
      const aff = e.affectedFiles.slice(0, 2).map(f => f.split('/').slice(-2).join('/')).join('<br>') || '—'
      lines.push(`| \`${e.id}\` | ${e.change.replace(/\|/g, '\\|').slice(0, 80)} | ${e.severity} | ${aff} | ${e.requiredAction.slice(0, 120)} |`)
    }
    if (impact.entries.length > 60) lines.push(`| … | … | … | … | … ${impact.entries.length - 60} more |`)
  }
  lines.push('')

  lines.push('## Change registry (excerpt)')
  lines.push('')
  lines.push('| ID | Category | Sev | Old → New | Status | Description |')
  lines.push('|---|---|---|---|---|---|')
  for (const e of registry.entries.slice(0, 50)) {
    const ov = (e.oldValue ?? '∅')?.toString().slice(0, 40).replace(/\|/g, '\\|')
    const nv = (e.newValue ?? '∅')?.toString().slice(0, 40).replace(/\|/g, '\\|')
    lines.push(`| \`${e.id}\` | ${e.category} | ${e.severity} | \`${ov}\` → \`${nv}\` | ${e.migrationStatus} | ${e.description.slice(0, 120)} |`)
  }
  if (registry.entries.length > 50) lines.push(`| … | … | … | … | … | … ${registry.entries.length - 50} more |`)
  lines.push('')

  lines.push('## Model / Type changes (heuristic)')
  lines.push('')
  lines.push(`Namespaces prev → current: ${apiPrevious.namespaces.length} → ${apiCurrent.namespaces.length} (${apiPrevious.namespaces.slice(0, 5).join(', ')} … → ${apiCurrent.namespaces.slice(0, 5).join(', ')} …)`)
  lines.push('')

  lines.push('## Recommended actions')
  lines.push('')
  if (p0 > 0) lines.push('- [ ] Fix all **P0** items before merging sync branch (runtime blockers).')
  if (apiDiff.entries.some(e => e.kind === 'dot-to-slash')) lines.push('- [ ] Audit every `settings.describe`-style dot call; ensure Flutter uses slash (`settings/describe`).')
  if (apiDiff.entries.some(e => e.kind === 'split')) lines.push('- [ ] Handle split endpoints (e.g., `llm.providers` → `llm/listProviders + llm/listConfigurableProviders`) — not a simple rename.')
  if (impact.entries.some(e => e.id.includes('session/page'))) lines.push('- [ ] Verify `session/page throughSeq` cursor discipline — no synthetic sentinel.')
  if (streamDiff.total > 0) lines.push('- [ ] Verify stream contract (`remote.mux`, `$events`, `heartbeat`, `generation`, `reconnect`) against Flutter `connection_controller.dart`.')
  lines.push('- [ ] Run `pnpm upstream:verify` (typecheck + flutter analyze + verify-flutter-tracker).')
  lines.push('- [ ] Create branches as per policy: `sync/upstream/YYYY-MM-DD-<sha>` and `flutter-sync/YYYY-MM-DD-<sha>` (no auto-merge).')
  lines.push('')

  lines.push('## Artifacts')
  lines.push('')
  lines.push('- `migration/upstream-sync/upstream-state.json`')
  lines.push('- `migration/upstream-sync/api-contract-current.json` / `api-contract-previous.json` / `api-diff.json`')
  lines.push('- `migration/upstream-sync/stream-contract-current.json` / `stream-contract-previous.json` / `stream-diff.json`')
  lines.push('- `migration/upstream-sync/react-contract.json`')
  lines.push('- `migration/upstream-sync/flutter-contract.json`')
  lines.push('- `migration/upstream-sync/flutter-impact.json`')
  lines.push('- `migration/upstream-sync/change-registry.json`')
  lines.push('')

  lines.push('---')
  lines.push(`_Report generated by upstream-sync • upstream ${shortOld} → ${shortNew} • local ${state.localForkSha.slice(0, 8)}_`)
  lines.push('')

  return lines.join('\n')
}

export function writeReport(markdown: string): string {
  const date = new Date().toISOString().slice(0, 10)
  const dir = 'migration/upstream-sync/reports'
  mkdirSync(dir, { recursive: true })
  const shaShort = markdown.match(/New SHA: `[^`]+` \(`([^`]+)`\)/)?.[1] ?? 'unknown'
  const filename = `${date}-upstream-sync.md`
  // Avoid collisions: if file exists, append short SHA
  let path = join(dir, filename)
  try {
    const exists = (() => { try { return !!require('node:fs').statSync(path) } catch { return false } })()
    if (exists) path = join(dir, `${date}-upstream-sync-${shaShort}.md`)
  } catch {}
  writeFileSync(path, markdown, 'utf-8')
  // Also write latest symlink-like copy
  writeFileSync(join(dir, 'latest.md'), markdown, 'utf-8')
  return path
}
