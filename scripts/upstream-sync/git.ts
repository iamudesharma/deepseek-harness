// @ts-nocheck
import { execSync } from 'node:child_process'
import { readFileSync, existsSync } from 'node:fs'
import type { UpstreamState } from './types.ts'

function sh(cmd: string): string {
  return execSync(cmd, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }).trim()
}

export function getUpstreamState(): UpstreamState {
  const upstreamRepository = sh('git config --get remote.upstream.url || echo "https://github.com/deepseek-ai/deepseek-harness.git"').trim()
  const upstreamBranch = 'master'
  const lastSynchronizedSha = sh('git rev-parse origin/master 2>/dev/null || git merge-base HEAD upstream/master 2>/dev/null || git rev-parse HEAD')
  const currentUpstreamSha = sh('git rev-parse upstream/master')
  const localForkSha = sh('git rev-parse HEAD')
  const mergeBase = (() => {
    try { return sh('git merge-base HEAD upstream/master') } catch { return lastSynchronizedSha }
  })()
  const originMasterSha = (() => {
    try { return sh('git rev-parse origin/master') } catch { return lastSynchronizedSha }
  })()
  const behindBy = (() => {
    try { return Number(sh(`git rev-list --count origin/master..upstream/master`)) } catch { return 0 }
  })()
  const aheadBy = (() => {
    try { return Number(sh(`git rev-list --count origin/master..HEAD`)) } catch { return 0 }
  })()
  return {
    upstreamRepository: upstreamRepository || 'https://github.com/deepseek-ai/deepseek-harness.git',
    upstreamBranch,
    lastSynchronizedSha,
    currentUpstreamSha,
    localForkSha,
    mergeBase,
    originMasterSha,
    synchronizationTimestamp: new Date().toISOString(),
    behindBy,
    aheadBy,
    generatedBy: 'upstream-sync phase 0 baseline',
  }
}

export function readExistingState(path: string): Partial<UpstreamState> | null {
  if (!existsSync(path)) return null
  try {
    return JSON.parse(readFileSync(path, 'utf-8')) as Partial<UpstreamState>
  } catch { return null }
}

export function getCommits(oldSha: string, newSha: string): { sha: string, subject: string, author: string, date: string }[] {
  if (oldSha === newSha) return []
  const raw = sh(`git log --pretty=format:'%H%x1f%s%x1f%an%x1f%aI' ${oldSha}..${newSha}`)
  if (!raw) return []
  return raw.split('\n').filter(Boolean).map(line => {
    const [sha, subject, author, date] = line.split('\x1f') as [string, string, string, string]
    return { sha: sha!, subject: subject!, author: author!, date: date! }
  })
}

export function getChangedFiles(oldSha: string, newSha: string): { status: string, path: string, oldPath?: string }[] {
  const out: { status: string, path: string, oldPath?: string }[] = []
  if (oldSha === newSha) return out
  const raw = sh(`git diff --name-status --find-renames --diff-filter=ADMRC ${oldSha}..${newSha} || true`)
  for (const line of raw.split('\n').filter(Boolean)) {
    const parts = line.split('\t')
    const status = parts[0] ?? 'M'
    if (status.startsWith('R') || status.startsWith('C')) {
      const oldPath = parts[1]!
      const newPath = parts[2]!
      out.push({ status: status[0]!, path: newPath, oldPath })
    } else {
      out.push({ status, path: parts[1]! })
    }
  }
  return out
}

export function fileAtRev(rev: string, filePath: string): string | null {
  try {
    return execSync(`git show ${rev}:${filePath}`, { encoding: 'utf-8', maxBuffer: 20 * 1024 * 1024 })
  } catch { return null }
}

export function listFilesAtRev(rev: string, prefix = 'packages'): string[] {
  try {
    const raw = sh(`git ls-tree -r --name-only ${rev} -- ${prefix} 2>/dev/null || true`)
    return raw.split('\n').filter(Boolean)
  } catch { return [] }
}

export function grepFilesAtRev(rev: string, pattern: string, prefix = 'packages'): string[] {
  try {
    // Use git grep to find files containing pattern at this rev; faster than scanning all files
    const raw = sh(`git grep -l --no-color -e ${JSON.stringify(pattern)} ${rev} -- '${prefix}' 2>/dev/null || true`)
    return raw.split('\n').filter(Boolean).map(line => {
      // git grep with rev outputs "rev:path"; strip rev prefix
      const colon = line.indexOf(':')
      if (colon !== -1 && line.startsWith(rev)) return line.slice(colon + 1)
      // fallback: handle "rev:path" with short rev or full
      if (colon !== -1 && line.includes(':')) {
        const maybeRev = line.slice(0, colon)
        if (/^[0-9a-f]{4,40}$/.test(maybeRev)) return line.slice(colon + 1)
      }
      return line
    })
  } catch { return [] }
}

export function ensureUpstreamFetched(): void {
  try {
    // Fast check: if upstream/master resolves, skip network fetch (already fetched)
    sh('git rev-parse --verify upstream/master >/dev/null 2>&1')
    return
  } catch {}
  try { sh('git fetch upstream --prune 2>&1 | head -n 20') } catch {}
}
