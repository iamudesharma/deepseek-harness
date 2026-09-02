#!/usr/bin/env tsx
// @ts-nocheck
/**
 * Upstream sync CLI — Phases 0-20
 *
 * Commands:
 *  pnpm upstream:check   → tells whether upstream has changed
 *  pnpm upstream:diff    → API/schema/stream diff
 *  pnpm upstream:report  → markdown + JSON report
 *  pnpm upstream:impact  → affected Flutter files/features
 *  pnpm upstream:sync    → create synchronization branch/PR draft
 *  pnpm upstream:verify  → run compatibility gates
 *
 * File outputs (migration/upstream-sync/):
 *  upstream-state.json, api-contract-current/previous.json, api-diff.json,
 *  stream-contract-current/previous.json, stream-diff.json,
 *  react-contract.json, flutter-contract.json, flutter-impact.json, change-registry.json, reports/
 */

import { execSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

import { getUpstreamState, readExistingState, getCommits, getChangedFiles, ensureUpstreamFetched, fileAtRev } from './git.ts'
import { classifyFiles } from './classifier.ts'
import { extractApiContract } from './api-extractor.ts'
import { extractStreamContract, diffStreamContracts } from './stream-extractor.ts'
import { extractReactContract } from './react-extractor.ts'
import { extractFlutterContract } from './flutter-extractor.ts'
import { diffApiContracts } from './diff-engine.ts'
import { analyzeFlutterImpact, buildParity } from './impact-analyzer.ts'
import { buildChangeRegistry } from './registry.ts'
import { generateMarkdownReport, writeReport } from './report.ts'
import type { ApiContract, StreamContract } from './types.ts'

const OUT_DIR = 'migration/upstream-sync'
const STATE_PATH = join(OUT_DIR, 'upstream-state.json')

function sh(cmd: string): string {
  return execSync(cmd, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }).trim()
}

function ensureOutDir() {
  mkdirSync(OUT_DIR, { recursive: true })
  mkdirSync(join(OUT_DIR, 'reports'), { recursive: true })
}

function writeJson(path: string, data: unknown) {
  writeFileSync(path, JSON.stringify(data, null, 2) + '\n', 'utf-8')
}

function loadOrGenerate(): {
  state: ReturnType<typeof getUpstreamState>
  apiCurrent: ApiContract
  apiPrevious: ApiContract
  streamCurrent: StreamContract
  streamPrevious: StreamContract
} {
  ensureOutDir()
  ensureUpstreamFetched()
  const state = getUpstreamState()
  writeJson(STATE_PATH, state)

  const apiCurrent = extractApiContract(state.currentUpstreamSha)
  const apiPrevious = extractApiContract(state.lastSynchronizedSha)
  const streamCurrent = extractStreamContract(state.currentUpstreamSha)
  const streamPrevious = extractStreamContract(state.lastSynchronizedSha)

  writeJson(join(OUT_DIR, 'api-contract-current.json'), apiCurrent)
  writeJson(join(OUT_DIR, 'api-contract-previous.json'), apiPrevious)
  writeJson(join(OUT_DIR, 'stream-contract-current.json'), streamCurrent)
  writeJson(join(OUT_DIR, 'stream-contract-previous.json'), streamPrevious)

  return { state, apiCurrent, apiPrevious, streamCurrent, streamPrevious }
}

async function cmdCheck() {
  ensureOutDir()
  ensureUpstreamFetched()
  const state = getUpstreamState()
  writeJson(STATE_PATH, state)
  const changed = state.currentUpstreamSha !== state.lastSynchronizedSha
  const behind = state.behindBy
  console.log(JSON.stringify({
    changed,
    behindBy: behind,
    oldSha: state.lastSynchronizedSha.slice(0, 8),
    newSha: state.currentUpstreamSha.slice(0, 8),
    localHead: state.localForkSha.slice(0, 8),
    message: changed ? `upstream has ${behind} new commits (${state.lastSynchronizedSha.slice(0, 8)}..${state.currentUpstreamSha.slice(0, 8)})` : 'upstream unchanged',
  }, null, 2))
  // Also print human
  if (changed) console.log(`\n↑ upstream HAS changed: ${behind} commits behind. Run pnpm upstream:diff / report`)
  else console.log(`\n✓ upstream unchanged`)
  process.exit(changed ? 0 : 0)
}

async function cmdDiff() {
  const { state, apiCurrent, apiPrevious, streamCurrent, streamPrevious } = loadOrGenerate()
  const apiDiff = diffApiContracts(apiPrevious, apiCurrent)
  const streamDiff = diffStreamContracts(streamPrevious, streamCurrent)
  const changedFiles = getChangedFiles(state.lastSynchronizedSha, state.currentUpstreamSha)
  const classification = classifyFiles(state.lastSynchronizedSha, state.currentUpstreamSha, changedFiles)

  writeJson(join(OUT_DIR, 'api-diff.json'), apiDiff)
  writeJson(join(OUT_DIR, 'stream-diff.json'), streamDiff)
  writeJson(join(OUT_DIR, 'file-classification.json'), classification)

  console.log(JSON.stringify({
    oldSha: state.lastSynchronizedSha.slice(0, 8),
    newSha: state.currentUpstreamSha.slice(0, 8),
    api: { total: apiDiff.total, breaking: apiDiff.breaking, additive: apiDiff.additive },
    stream: { total: streamDiff.total },
    files: { total: classification.total, byCategory: classification.byCategory },
  }, null, 2))
  console.log(`\nAPI diff: ${apiDiff.total} (${apiDiff.breaking} breaking) | Stream diff: ${streamDiff.total} | Files: ${classification.total}`)
  for (const e of apiDiff.entries.slice(0, 20)) {
    console.log(` - [${e.severity}] ${e.kind}: ${e.oldEndpoint ?? ''} → ${e.newEndpoint ?? ''} :: ${e.description.slice(0, 120)}`)
  }
  if (apiDiff.entries.length > 20) console.log(` ... and ${apiDiff.entries.length - 20} more`)
}

async function cmdImpact() {
  const { state, apiCurrent, apiPrevious, streamCurrent, streamPrevious } = loadOrGenerate()
  const apiDiff = diffApiContracts(apiPrevious, apiCurrent)
  const streamDiff = diffStreamContracts(streamPrevious, streamCurrent)
  writeJson(join(OUT_DIR, 'api-diff.json'), apiDiff)
  writeJson(join(OUT_DIR, 'stream-diff.json'), streamDiff)

  const flutter = extractFlutterContract()
  writeJson(join(OUT_DIR, 'flutter-contract.json'), flutter)

  const impact = analyzeFlutterImpact(apiDiff, flutter, state.lastSynchronizedSha, state.currentUpstreamSha)
  writeJson(join(OUT_DIR, 'flutter-impact.json'), impact)

  console.log(JSON.stringify({
    total: impact.entries.length,
    bySeverity: impact.bySeverity,
  }, null, 2))
  for (const e of impact.entries) {
    console.log(` - [${e.severity}] ${e.id}: ${e.change} → ${e.affectedFiles.slice(0, 2).join(', ')} | ${e.requiredAction}`)
  }
}

async function cmdReport() {
  const { state, apiCurrent, apiPrevious, streamCurrent, streamPrevious } = loadOrGenerate()
  const apiDiff = diffApiContracts(apiPrevious, apiCurrent)
  const streamDiff = diffStreamContracts(streamPrevious, streamCurrent)
  const changedFiles = getChangedFiles(state.lastSynchronizedSha, state.currentUpstreamSha)
  const classification = classifyFiles(state.lastSynchronizedSha, state.currentUpstreamSha, changedFiles)
  const commits = getCommits(state.lastSynchronizedSha, state.currentUpstreamSha)
  const flutter = extractFlutterContract()
  const react = extractReactContract(state.currentUpstreamSha)
  const parity = buildParity(react, flutter)
  const impact = analyzeFlutterImpact(apiDiff, flutter, state.lastSynchronizedSha, state.currentUpstreamSha)
  const registry = buildChangeRegistry(apiDiff, streamDiff, impact, classification.files.map(f => f.path), state.lastSynchronizedSha, state.currentUpstreamSha)

  writeJson(join(OUT_DIR, 'api-diff.json'), apiDiff)
  writeJson(join(OUT_DIR, 'stream-diff.json'), streamDiff)
  writeJson(join(OUT_DIR, 'file-classification.json'), classification)
  writeJson(join(OUT_DIR, 'react-contract.json'), react)
  writeJson(join(OUT_DIR, 'flutter-contract.json'), flutter)
  writeJson(join(OUT_DIR, 'flutter-impact.json'), impact)
  writeJson(join(OUT_DIR, 'change-registry.json'), registry)
  // Also write a parity file for convenience
  writeJson(join(OUT_DIR, 'parity.json'), parity)

  const md = generateMarkdownReport({
    state, classification, apiCurrent, apiPrevious, apiDiff,
    streamCurrent, streamPrevious, streamDiff,
    react, flutter, parity, impact, registry, commits,
  })
  const reportPath = writeReport(md)
  console.log(`\nReport written: ${reportPath}`)
  console.log(`Parity: PASS ${parity.pass} / MISSING ${parity.missing} / INCOMPATIBLE ${parity.incompatible} | Impact P0 ${impact.bySeverity['P0'] ?? 0} P1 ${impact.bySeverity['P1'] ?? 0}`)
  console.log(`API changes: ${apiDiff.total} breaking ${apiDiff.breaking} | Stream changes: ${streamDiff.total} | Registry: ${registry.total}`)
  // Also dump JSON summary to stdout for CI
  console.log(JSON.stringify({
    report: reportPath,
    oldSha: state.lastSynchronizedSha.slice(0, 8),
    newSha: state.currentUpstreamSha.slice(0, 8),
    commits: commits.length,
    files: classification.total,
    apiDiff: apiDiff.total,
    breaking: apiDiff.breaking,
    streamDiff: streamDiff.total,
    parity: { pass: parity.pass, missing: parity.missing, incompatible: parity.incompatible, unknown: parity.unknown },
    impact: impact.bySeverity,
    registry: registry.total,
  }, null, 2))
}

async function cmdSync() {
  const { state } = loadOrGenerate()
  // Create sync branch name — must branch from our/master (origin/master), not from feature branch
  const date = new Date().toISOString().slice(0, 10)
  const short = state.currentUpstreamSha.slice(0, 7)
  const branch = `sync/upstream/${date}-${short}`
  const flutterBranch = `flutter-sync/${date}-${short}`
  const exists = (() => {
    try { sh(`git show-ref --verify refs/heads/${branch} 2>/dev/null`); return true } catch { return false }
  })()
  const currentBranch = (() => { try { return sh('git rev-parse --abbrev-ref HEAD') } catch { return 'unknown' } })()
  if (exists) {
    console.log(`Branch ${branch} already exists.`)
  } else {
    try {
      // For initial implementation, branch from current HEAD (contains sync tooling).
      // In production, prefer: git checkout -b ${branch} origin/master  (our/master) then cherry-pick sync tooling,
      // to keep Host sync separate from Flutter integration branches.
      sh(`git checkout -b ${branch}`)
      console.log(`Created branch ${branch} from ${currentBranch} (${state.currentUpstreamSha.slice(0, 8)} upstream)`)
      console.log(`Next: git merge upstream/master  (resolve conflicts manually; do NOT auto-resolve apps/flutter/** or migration/** or contracts)`)
      console.log(`Then: pnpm upstream:report && pnpm upstream:verify`)
      // Return to original branch so we don't leave user on sync branch unexpectedly
      sh(`git checkout ${currentBranch}`)
      console.log(`Returned to ${currentBranch}`)
    } catch (e) {
      console.error(`Failed to create branch: ${e}`)
      try { sh(`git checkout ${currentBranch}`) } catch {}
    }
  }
  console.log(`Flutter parity branch (after upstream merge succeeds): ${flutterBranch}`)
  console.log(`Create after sync merge succeeds with: git checkout -b ${flutterBranch} ${branch}  (then only Flutter compatibility changes; do not mix unrelated UI work)`)
  // Generate PR description template
  const prBody = generatePrDescription(state)
  const prPath = join(OUT_DIR, 'reports', `pr-description-${date}-${short}.md`)
  writeFileSync(prPath, prBody, 'utf-8')
  console.log(`PR description template: ${prPath}`)
}

function generatePrDescription(state: ReturnType<typeof getUpstreamState>): string {
  // Load latest diffs if available
  let apiDiff: any = null, streamDiff: any = null, impact: any = null, parity: any = null, classification: any = null
  try { apiDiff = JSON.parse(readFileSync(join(OUT_DIR, 'api-diff.json'), 'utf-8')) } catch {}
  try { streamDiff = JSON.parse(readFileSync(join(OUT_DIR, 'stream-diff.json'), 'utf-8')) } catch {}
  try { impact = JSON.parse(readFileSync(join(OUT_DIR, 'flutter-impact.json'), 'utf-8')) } catch {}
  try { parity = JSON.parse(readFileSync(join(OUT_DIR, 'parity.json'), 'utf-8')) } catch {}
  try { classification = JSON.parse(readFileSync(join(OUT_DIR, 'file-classification.json'), 'utf-8')) } catch {}
  const shortOld = state.lastSynchronizedSha.slice(0, 8)
  const shortNew = state.currentUpstreamSha.slice(0, 8)
  const p0 = impact?.bySeverity?.['P0'] ?? 0
  const p1 = impact?.bySeverity?.['P1'] ?? 0
  const p2 = impact?.bySeverity?.['P2'] ?? 0
  const breaking = apiDiff?.breaking ?? 0
  const files = classification?.total ?? 0
  const apiChanges = apiDiff?.total ?? 0
  const streamChanges = streamDiff?.total ?? 0
  const parityStatus = parity ? (parity.incompatible > 0 || p0 > 0 ? 'FAIL' : parity.missing > 0 ? 'MISSING' : 'PASS') : 'UNKNOWN'
  return `# UPSTREAM SYNC REPORT

Upstream:
${shortOld} → ${shortNew}

Commits:
${state.behindBy}

Files:
${files}

API changes:
${apiChanges}

Breaking APIs:
${breaking}

Stream changes:
${streamChanges}

Flutter affected files:
${impact?.entries?.length ?? 0}

P0:
${p0}

P1:
${p1}

P2:
${p2}

React/Flutter parity:
${parityStatus}

Tests:
PENDING (run pnpm upstream:verify)

Manual verification required:
${p0 > 0 || breaking > 0 ? 'YES — P0/breaking changes present' : 'NO — but audit P1/P2'}

---

## sync branch

\`sync/upstream/YYYY-MM-DD-${shortNew}\`

Do not auto-resolve conflicts in:
- apps/flutter/**
- migration/**
- API/stream contracts

## flutter parity branch

\`flutter-sync/YYYY-MM-DD-${shortNew}\`

Contains only Flutter compatibility changes.

## Commands

\`\`\`
pnpm upstream:diff
pnpm upstream:impact
pnpm upstream:report
pnpm upstream:verify
\`\`\`

## Safety

AUTO-APPLY: docs, generated metadata, non-breaking additive fields, formatting
REVIEW REQUIRED: endpoint rename, wrapper change, stream/auth changes
NEVER AUTO-APPLY: blanket dot-to-slash, fake wrappers, synthetic cursors, duplicate stores
`
}

async function cmdVerify() {
  console.log('Running verification gates (build + typecheck + lint + flutter analyze if available)...\n')
  const results: { name: string, ok: boolean, ms: number }[] = []
  async function run(name: string, cmd: string) {
    const start = Date.now()
    try {
      execSync(cmd, { stdio: 'inherit' })
      results.push({ name, ok: true, ms: Date.now() - start })
    } catch {
      results.push({ name, ok: false, ms: Date.now() - start })
    }
  }
  // Host gates: use tsdown build? We run pnpm build:lib for speed
  await run('pnpm build', 'pnpm run build:lib 2>&1 | tail -n 50')
  await run('pnpm typecheck', 'pnpm run typecheck:contracts-ready 2>&1 | tail -n 100')
  // flutter analyze if flutter available
  try {
    const hasFlutter = sh('which flutter 2>/dev/null || echo none')
    if (hasFlutter !== 'none') {
      await run('flutter analyze', 'flutter analyze --no-pub 2>&1 | tail -n 100')
      await run('verify-flutter-tracker', 'pnpm run verify-flutter-tracker 2>&1 | tail -n 50')
    } else {
      console.log('flutter not found — skipping flutter analyze')
    }
  } catch {}
  console.log('\n--- Verify summary ---')
  for (const r of results) console.log(` ${r.ok ? '✓' : '✗'} ${r.name} (${r.ms}ms)`)
  const allOk = results.every(r => r.ok)
  console.log(allOk ? '\n✓ all gates passed' : '\n✗ some gates failed — see above')
  // Also print a machine-readable JSON summary
  console.log(JSON.stringify({ results, ok: allOk }, null, 2))
  if (!allOk) process.exitCode = 1
}

async function main() {
  const cmd = process.argv[2] ?? 'check'
  switch (cmd) {
    case 'check': await cmdCheck(); break
    case 'diff': await cmdDiff(); break
    case 'impact': await cmdImpact(); break
    case 'report': await cmdReport(); break
    case 'sync': await cmdSync(); break
    case 'verify': await cmdVerify(); break
    case 'help':
    case '--help':
    case '-h':
      console.log(`upstream-sync commands:
  check  — tells whether upstream has changed
  diff   — API/schema/stream diff
  impact — affected Flutter files/features
  report — markdown + JSON report
  sync   — create synchronization branch/PR draft
  verify — run compatibility gates
`)
      break
    default:
      console.error(`Unknown command: ${cmd}`)
      console.error(`Use: pnpm upstream:check|diff|report|impact|sync|verify`)
      process.exit(1)
  }
}

main().catch(e => { console.error(e); process.exit(1) })
