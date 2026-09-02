// @ts-nocheck
import type { FileCategory, ClassifiedFile, FileClassification } from './types.ts'

export function classifyFile(path: string): FileCategory {
  if (path.startsWith('apps/flutter/')) return 'FLUTTER'
  if (path.startsWith('apps/web/') || path.startsWith('packages/client/')) return 'CLIENT'
  // React specifics inside client ui
  if (path.includes('ui-') || path.includes('packages/client/ui')) return 'REACT'
  if (path.startsWith('packages/api/')) return 'API'
  if (path.startsWith('packages/host/')) return 'HOST'
  if (path.startsWith('packages/core/')) return 'CORE'
  if (path.startsWith('packages/interaction/')) return 'INTERACTION'
  if (path.startsWith('packages/llm/') || path.includes('/llm/')) return 'MODEL'
  if (path.includes('stream') || path.includes('mux') || path.includes('gateway') || path.includes('remote-stream') || path.includes('events')) return 'STREAM'
  if (path.includes('credentials') || path.includes('auth') || path.includes('security') || path.includes('remote-access') || path.includes('browser-credentials')) return 'SECURITY'
  if (path.startsWith('packages/typert/') || path.includes('typert')) return 'API'
  if (path.startsWith('packages/session/') || path.includes('session')) return 'CORE'
  if (path.startsWith('packages/preset/') || path.includes('preset')) return 'CORE'
  if (path.startsWith('packages/settings/') || path.includes('settings')) return 'CORE'
  if (path.startsWith('packages/')) {
    // fallback for other packages
    if (path.includes('/api/') || path.includes('gateway')) return 'API'
    return 'CORE'
  }
  if (path.startsWith('.github/') || path === 'package.json' || path === 'pnpm-lock.yaml' || path.startsWith('scripts/') || path === 'tsconfig.json' || path.includes('tsdown') || path.includes('vite')) return 'BUILD'
  if (path.endsWith('.md') || path.startsWith('docs/') || path.startsWith('.agents/') || path.startsWith('website/')) return 'DOCS'
  if (path.includes('.spec.') || path.includes('__tests__') || path.includes('/tests/') || path.startsWith('snapshots/') || path.startsWith('vitest')) return 'TEST'
  return 'OTHER'
}

export function classifyFiles(
  oldSha: string,
  newSha: string,
  changed: { status: string, path: string, oldPath?: string }[],
): FileClassification {
  const files: ClassifiedFile[] = changed.map(c => {
    let status: ClassifiedFile['status'] = 'modified'
    if (c.status === 'A') status = 'added'
    else if (c.status === 'D') status = 'deleted'
    else if (c.status === 'M') status = 'modified'
    else if (c.status === 'R') status = 'renamed'
    else if (c.status === 'C') status = 'copied'
    else status = 'modified'
    return {
      path: c.path,
      status,
      oldPath: c.oldPath,
      category: classifyFile(c.path),
    }
  })

  const byCategory: Record<FileCategory, number> = {
    HOST: 0, API: 0, CLIENT: 0, REACT: 0, FLUTTER: 0, CORE: 0, INTERACTION: 0, MODEL: 0, STREAM: 0, SECURITY: 0, BUILD: 0, DOCS: 0, TEST: 0, OTHER: 0,
  }
  for (const f of files) byCategory[f.category]++

  return {
    oldSha,
    newSha,
    total: files.length,
    added: files.filter(f => f.status === 'added'),
    modified: files.filter(f => f.status === 'modified'),
    deleted: files.filter(f => f.status === 'deleted'),
    renamed: files.filter(f => f.status === 'renamed'),
    byCategory,
    files,
  }
}
