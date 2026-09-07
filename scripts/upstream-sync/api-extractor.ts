// oxlint-disable ban-ts-comment -- tsx-run tooling outside the repo TS programs; intentionally unchecked.
// @ts-nocheck
/**
 * Upstream API contract extractor: scans Typert remote services for operations.
 * Runs through tsx outside the repository TypeScript programs.
 */
import { execSync } from 'node:child_process'
import type { ApiContract, ApiOperation } from './types.ts'
import { fileAtRev, listFilesAtRev, grepFilesAtRev } from './git.ts'

function sh(cmd: string): string {
  return execSync(cmd, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }).trim()
}

/**
 * Extract Typert Remote operations from a git revision by scanning
 * all packages src TypeScript files.
 * Uses regex heuristics over git-show content; no need to checkout.
 */
export function extractApiContract(rev: string): ApiContract {
  const generatedAt = new Date().toISOString()
  // Fast path: use git grep to find files containing @Remote or TypertRemoteService
  let candidateFiles: string[] = []
  try {
    candidateFiles = grepFilesAtRev(rev, '@Remote', 'packages')
    const extra = grepFilesAtRev(rev, 'TypertRemoteService', 'packages')
    candidateFiles = [...new Set([...candidateFiles, ...extra])].filter(p => p.endsWith('.ts'))
    if (candidateFiles.length === 0) {
      const allFiles = listFilesAtRev(rev, 'packages')
      candidateFiles = allFiles.filter(p => p.endsWith('.ts') && p.includes('/src/'))
    }
  } catch {
    const allFiles = listFilesAtRev(rev, 'packages')
    candidateFiles = allFiles.filter(p => p.endsWith('.ts') && p.includes('/src/'))
  }
  const operations: ApiOperation[] = []
  let scanned = 0

  for (const file of candidateFiles) {
    const content = fileAtRev(rev, file)
    if (!content) continue
    scanned++
    const ops = parseFileForOperations(file, content, rev)
    operations.push(...ops)
  }

  // Also scan packages/api/gateway types for additional endpoints declared via protocol?
  // Already covered.

  // Deduplicate by endpoint
  const seen = new Set<string>()
  const deduped: ApiOperation[] = []
  for (const op of operations) {
    if (seen.has(op.endpoint)) continue
    seen.add(op.endpoint)
    deduped.push(op)
  }
  deduped.sort((a, b) => a.endpoint.localeCompare(b.endpoint))

  const namespaces = [...new Set(deduped.map(o => o.namespace))].sort()
  const endpoints = deduped.map(o => o.endpoint).sort()

  const byNamespace: Record<string, ApiOperation[]> = {}
  for (const ns of namespaces) byNamespace[ns] = deduped.filter(o => o.namespace === ns)

  return {
    rev,
    generatedAt,
    operations: deduped,
    namespaces,
    endpoints,
    byNamespace,
    sourceFilesScanned: scanned,
  }
}

function parseFileForOperations(file: string, content: string, _rev: string): ApiOperation[] {
  const ops: ApiOperation[] = []
  // Find service bindings: extends TypertRemoteService or bindTypertRemote(this, 'serviceKey', {namespace: 'ns'})
  // We capture serviceKey and namespace per file
  const serviceBindings: { serviceKey: string; namespace: string; line: number }[] = []

  // Pattern 1: class Foo extends TypertRemoteService  -> then constructor super(ctx, 'serviceKey') or TypertRemoteService param
  // Actually TypertRemoteService constructor takes serviceKey as second param: super(ctx, 'agentTeams') etc.
  // We'll approximate: find all bindTypertRemote occurrences
  const bindRegex = /bindTypertRemote\s*\(\s*this\s*,\s*['"]([^'"]+)['"]\s*(?:,\s*\{\s*namespace:\s*['"]([^'"]+)['"]\s*\})?/g

  let match: RegExpExecArray | null
  while ((match = bindRegex.exec(content)) !== null) {
    const serviceKey = match[1]
    const namespace = match[2] ?? serviceKey
    const line = content.slice(0, match.index).split('\n').length
    serviceBindings.push({ serviceKey, namespace, line })
  }

  // If no explicit bind but extends TypertRemoteService, infer from super calls
  if (serviceBindings.length === 0) {
    const superMatchGlobal = /super\(\s*ctx,\s*['"]([^'"]+)['"]\s*(?:,\s*\{\s*namespace:\s*['"]([^'"]+)['"]\s*\})?/g
    while ((match = superMatchGlobal.exec(content)) !== null) {
      // A class body may separate its `extends TypertRemoteService` clause
      // from `super(ctx, serviceKey)` by fields and documentation. The exact
      // `super(ctx, ...)` form is remote-service-specific, so scope by file
      // rather than an arbitrary proximity window.
      if (!content.includes('extends TypertRemoteService')) continue
      const serviceKey = match[1]
      const namespace = match[2] ?? serviceKey
      const line = content.slice(0, match.index).split('\n').length
      serviceBindings.push({ serviceKey, namespace, line })
    }
  }

  // Fallback: if file declares a service but uses old Service base with typertRemote getter, we still detect via @Remote presence
  // We'll later infer namespace from file path if missing (e.g., packages/api/session-controller/src/index.ts -> namespace session)
  // For now, if no binding found but has @Remote, we try to infer namespace from common mappings

  const hasRemote = content.includes('@Remote')
  if (serviceBindings.length === 0 && hasRemote) {
    const inferred = inferNamespaceFromPath(file)
    if (inferred) {
      serviceBindings.push({ serviceKey: inferred.serviceKey, namespace: inferred.namespace, line: 1 })
    }
  }

  if (serviceBindings.length === 0) return []

  // For each binding, find @Remote methods by iterating lines and tracking decorators.
  const lines = content.split('\n')
  let pendingDecorator: { exportName: string | null; mode: 'unary' | 'stream'; line: number; decoratorLine: string } | null = null

  for (let i = 0; i < lines.length; i++) {
    const lineText = lines[i]
    const trimmed = lineText.trim()
    if (trimmed.startsWith('@Remote')) {
      let exportName: string | null = null
      let mode: 'unary' | 'stream' = 'unary'
      const m1 = trimmed.match(/@Remote\s*\(\s*['"]([^'"]+)['"]\s*\)/)
      if (m1) exportName = m1[1]
      if (trimmed.includes("mode: 'stream'") || trimmed.includes('mode: "stream"')) mode = 'stream'
      pendingDecorator = { exportName, mode, line: i + 1, decoratorLine: trimmed }
      // If next line also @RemoteScope, we ignore for now
      continue
    }
    if (trimmed.startsWith('@RemoteScope')) {
      // treat as direct Remote with context mode? We'll keep unary but note context
      if (pendingDecorator) {
        // keep pending, scope will be handled as exportName maybe
      } else {
        // standalone RemoteScope counts as Remote too
        let exportName: string | null = null
        const m1 = trimmed.match(/@RemoteScope\s*\(\s*['"][^'"]+['"]\s*(?:,\s*['"]([^'"]+)['"])?/)
        if (m1 && m1[1]) exportName = m1[1]
        // look ahead for method name
        let j = i + 1
        while (j < lines.length && lines[j].trim() === '') j++
        const nextLine = lines[j] ?? ''
        const methodMatch = nextLine.match(/(?:async\s+\*?|\*?)\s*(\w+)\s*\(/)
        if (methodMatch) {
          const method = methodMatch[1]
          const binding = serviceBindings[0]
          const operation = exportName ?? method
          const endpoint = `${binding.namespace}/${operation}`
          const wireEndpoint = `/api/${endpoint}`
          // Try to extract args shape from method signature lines
          const sigLines = lines.slice(j, Math.min(j + 4, lines.length)).join(' ')
          const args = extractArgs(sigLines)
          const requestShape = extractRequestShape(sigLines)
          ops.push({
            namespace: binding.namespace,
            operation,
            endpoint,
            wireEndpoint,
            method,
            exportName,
            mode: 'unary',
            serviceKey: binding.serviceKey,
            sourceFile: file,
            line: j + 1,
            requestShape,
            responseShape: null,
            args,
            transport: 'typert/unary',
            authorization: inferAuth(file, binding.namespace),
          })
          pendingDecorator = null
          i = j
        }
      }
      continue
    }
    if (pendingDecorator) {
      // Expect method definition on this line
      const methodMatch = lineText.match(/^\s*(?:public\s+|private\s+|protected\s+|async\s+)*\*?\s*(\w+)\s*\(/)
      // Need to be stricter: line contains '(' and not 'class' etc.
      if (methodMatch && lineText.includes('(') && !trimmed.startsWith('class') && !trimmed.startsWith('import') && !trimmed.startsWith('*')) {
        const method = methodMatch[1]
        // skip common false positives: constructor, get, set
        if (['constructor', 'get', 'set'].includes(method)) {
          pendingDecorator = null
          continue
        }
        const binding = serviceBindings[0]
        const operation = pendingDecorator.exportName ?? method
        const endpoint = `${binding.namespace}/${operation}`
        const wireEndpoint = `/api/${endpoint}`
        const sig = lines.slice(i, Math.min(i + 5, lines.length)).join(' ')
        const args = extractArgs(sig)
        const requestShape = extractRequestShape(sig)
        ops.push({
          namespace: binding.namespace,
          operation,
          endpoint,
          wireEndpoint,
          method,
          exportName: pendingDecorator.exportName,
          mode: pendingDecorator.mode === 'stream' ? 'stream' : 'unary',
          serviceKey: binding.serviceKey,
          sourceFile: file,
          line: i + 1,
          requestShape,
          responseShape: null,
          args,
          transport: pendingDecorator.mode === 'stream' ? 'typert/stream' : 'typert/unary',
          authorization: inferAuth(file, binding.namespace),
        })
        pendingDecorator = null
      } else if (trimmed === '' || trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('@')) {
        // keep waiting
        continue
      } else if (trimmed.includes('class ') || trimmed.includes('interface ') || trimmed.includes('type ')) {
        pendingDecorator = null
      } else {
        // if line is not method, keep waiting one more line? If we exceed 3 lines without method, clear
        const distance = i - pendingDecorator.line
        if (distance > 4) pendingDecorator = null
      }
    }
  }

  // Also fallback: scan for legacy endpoints defined via raw route registration not Typert? Skip for now.

  return ops
}

function extractArgs(sig: string): string[] {
  const m = sig.match(/\(([^)]*)\)/)
  if (!m) return []
  const inside = m[1].trim()
  if (!inside) return []
  // split by comma not inside braces? Simplify
  return inside.split(',').map(s => s.trim().split(':')[0].trim().split(' ')[0].trim()).filter(Boolean).slice(0, 5)
}

function extractRequestShape(sig: string): string | null {
  // Try to find first param type after colon
  const m = sig.match(/\(\s*\w+\s*:\s*([^,\)]+)/)
  if (m) return m[1].trim().slice(0, 120)
  return null
}

function inferAuth(file: string, namespace: string): 'none' | 'browser' | 'bearer-full' | 'bearer-limited' | 'unknown' {
  if (namespace === 'remote' || file.includes('remote-access') || file.includes('remote-notifications')) {
    // remote.pair is none, others are bearer
    return 'bearer-full'
  }
  if (file.includes('session') || file.includes('workspace') || file.includes('settings') || file.includes('plugin') || file.includes('host')) return 'browser'
  return 'browser'
}

function inferNamespaceFromPath(file: string): { serviceKey: string; namespace: string } | null {
  // Map common package paths to namespace
  const mappings: Record<string, string> = {
    'packages/api/session-controller/src/index.ts': 'session',
    'packages/api/workspace-controller/src/index.ts': 'workspace',
    'packages/api/settings-controller/src/index.ts': 'settings',
    'packages/api/settings-controller/src/credentials.ts': 'credentials',
    'packages/api/gateway/src/index.ts': 'typertGateway',
    'packages/host/plugin-inventory/src/index.ts': 'pluginInventory',
    'packages/host/remote-access/src/remote-service.ts': 'remote',
    'packages/host/remote-notifications/src/remote-notifications-service.ts': 'remoteNotifications',
    'packages/preset/agent-presets/src/index.ts': 'agentPresets',
    'packages/session/session/src/index.ts': 'session',
    'packages/workspace/workspace/src/index.ts': 'workspace',
    'packages/settings/settings/src/index.ts': 'settings',
    'packages/llm/llm/src/index.ts': 'llm',
    'packages/subagent/subagent/src/index.ts': 'subagents',
    'packages/goal/goal/src/index.ts': 'goal',
    'packages/interaction/commands/src/index.ts': 'commands',
    'packages/feedback/message-feedback/src/index.ts': 'messageFeedback',
  }
  if (mappings[file]) return { serviceKey: mappings[file], namespace: mappings[file] }
  // heuristic: folder name = last segment before src
  const m = file.match(/packages\/[^/]+\/([^/]+)\/src/)
  if (m) {
    const candidate = m[1]
    // convert kebab to camel? Keep as is
    return { serviceKey: candidate, namespace: candidate }
  }
  const m2 = file.match(/packages\/([^/]+)\/[^/]+\/src/)
  if (m2) return { serviceKey: m2[1], namespace: m2[1] }
  return null
}

export function extractApiContractFromWorkingTree(): ApiContract {
  // Use filesystem directly for working tree (current fork HEAD, not upstream)
  // For our purpose, we want to generate current contract without git show, just reading files
  // But we already have extractApiContract using git ls-tree; keep both.
  const rev = sh('git rev-parse HEAD')
  return extractApiContract(rev)
}
