// @ts-nocheck
import { execSync } from 'node:child_process'
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'
import type { FlutterContract, FlutterCallSite } from './types.ts'

function sh(cmd: string): string {
  return execSync(cmd, { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 }).trim()
}

export function extractFlutterContract(): FlutterContract {
  const generatedAt = new Date().toISOString()
  const root = 'apps/flutter/lib'
  const files: string[] = []
  walk(root, files)
  const callSites: FlutterCallSite[] = []
  let scanned = 0
  for (const file of files) {
    if (!file.endsWith('.dart')) continue
    scanned++
    const content = readFileSync(file, 'utf-8')
    const sites = parseDartFile(file, content)
    callSites.push(...sites)
  }
  // Also scan test files for additional coverage but not as primary
  const endpointsUsed = [...new Set(callSites.map(c => c.endpoint))].sort()
  const modelsUsed = [...new Set(callSites.map(c => c.model).filter(Boolean) as string[])].sort()
  callSites.sort((a, b) => a.endpoint.localeCompare(b.endpoint) || a.file.localeCompare(b.file))
  return {
    generatedAt,
    filesScanned: scanned,
    callSites,
    endpointsUsed,
    modelsUsed,
  }
}

function walk(dir: string, out: string[]) {
  if (!existsSync(dir)) return
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry)
    const s = statSync(p)
    if (s.isDirectory()) walk(p, out)
    else out.push(p)
  }
}

function parseDartFile(file: string, content: string): FlutterCallSite[] {
  const lines = content.split('\n')
  const sites: FlutterCallSite[] = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    // Match _postTypert('endpoint'), callMethod('endpoint'), client.xxx etc.
    const postTypertRegex = /_postTypert\s*\(\s*['"]([^'"]+)['"]\s*,/g
    const callMethodRegex = /callMethod\s*\(\s*['"]([^'"]+)['"]\s*,/g
    const directMethodRegex = /\b(await\s+)?client\.(getSessions|getSessionHistory|getSessionEvents|sendMessage|createSession|cancelTurn|settingsDescribe|settingsMutate|credentialsDescribe|credentialsSet|llmProviders|llmModels|sessionModels|sessionSelectModel|workspaceList|workspaceCreate|skillList|agentPresetList|agentPresetSelect|hostDescribe|remotePair|fetchWsTicket|pluginInventoryList)\s*\(/g
    const endpointLiteralRegex = /['"](session\/[a-zA-Z0-9\/_-]+|settings\/[a-zA-Z0-9\/_-]+|workspace\/[a-zA-Z0-9\/_-]+|llm\/[a-zA-Z0-9\/_-]+|pluginInventory\/[a-zA-Z0-9\/_-]+|agentPresets\/[a-zA-Z0-9\/_-]+|host\/[a-zA-Z0-9\/_-]+|remote\/[a-zA-Z0-9\/_-]+|credentials\/[a-zA-Z0-9\/_-]+|skills\/[a-zA-Z0-9\/_-]+)['"]/g

    let m: RegExpExecArray | null

    while ((m = postTypertRegex.exec(line)) !== null) {
      const endpoint = m[1]
      sites.push({
        file,
        line: i + 1,
        api: endpoint,
        endpoint,
        wireEndpoint: `/api/${endpoint.replace('.', '/')}`,
        requestShape: extractRequestShape(lines, i),
        responseDecoder: extractDecoder(lines, i),
        providerOrState: extractProvider(lines, i),
        eventConsumer: extractEvent(lines, i),
        streamConsumer: extractStream(lines, i),
        model: extractModel(lines, i),
        currentValueSource: extractCursor(lines, i),
      })
    }
    // Reset regex lastIndex for next line? Already handled per line
    // For callMethod
    {
      const re = /callMethod\s*\(\s*['"]([^'"]+)['"]/g
      let mm: RegExpExecArray | null
      while ((mm = re.exec(line)) !== null) {
        const endpoint = mm[1]
        // Avoid double counting if already counted as _postTypert
        if (sites.some(s => s.line === i + 1 && s.endpoint === endpoint)) continue
        sites.push({
          file,
          line: i + 1,
          api: endpoint,
          endpoint,
          wireEndpoint: `/api/${endpoint.replace('.', '/')}`,
          requestShape: extractRequestShape(lines, i),
          responseDecoder: extractDecoder(lines, i),
          providerOrState: extractProvider(lines, i),
          eventConsumer: extractEvent(lines, i),
          streamConsumer: extractStream(lines, i),
          model: extractModel(lines, i),
          currentValueSource: extractCursor(lines, i),
        })
      }
    }
    // Direct client methods map to endpoints
    {
      const re = /client\.(getSessions|getSessionHistory|getSessionEvents|sendMessage|createSession|cancelTurn|settingsDescribe|settingsMutate|credentialsDescribe|credentialsSet|llmProviders|llmModels|sessionModels|sessionSelectModel|workspaceList|workspaceCreate|skillList|agentPresetList|agentPresetSelect|hostDescribe|remotePair|fetchWsTicket|pluginInventoryList)/g
      let mm: RegExpExecArray | null
      while ((mm = re.exec(line)) !== null) {
        const method = mm[1]
        const endpoint = mapMethodToEndpoint(method)
        sites.push({
          file,
          line: i + 1,
          api: `ConnectionClient.${method}`,
          endpoint,
          wireEndpoint: `/api/${endpoint}`,
          requestShape: extractRequestShape(lines, i),
          responseDecoder: extractDecoder(lines, i),
          providerOrState: extractProvider(lines, i),
          eventConsumer: extractEvent(lines, i),
          streamConsumer: extractStream(lines, i),
          model: extractModel(lines, i),
          currentValueSource: extractCursor(lines, i),
        })
      }
    }
    // Stream subscriptions via open('session/follow'| 'session/control' | 'workspace/follow' | etc.)
    // These are Typert stream endpoints opened over the mux, not unary _postTypert. Capture them as call sites
    {
      const re = /\bopen\s*\(\s*['"]([^'"]+)['"]/g
      let mm: RegExpExecArray | null
      while ((mm = re.exec(line)) !== null) {
        const endpoint = mm[1]
        // Only treat Typert-like endpoints (contains slash) as stream RPCs; skip local opens
        if (!endpoint.includes('/')) continue
        // Reuse the same allowlist as impact-analyzer (session, settings, workspace, etc.) or any /-form
        // Accept any slash endpoint that looks like namespace/operation
        if (!/^[a-zA-Z0-9_-]+\/[a-zA-Z0-9._-]+$/.test(endpoint)) continue
        if (line.trim().startsWith('//') || line.trim().startsWith('*')) continue
        if (sites.some(s => s.line === i + 1 && s.endpoint === endpoint)) continue
        sites.push({
          file,
          line: i + 1,
          api: endpoint,
          endpoint,
          wireEndpoint: `/api/${endpoint}`,
          requestShape: extractRequestShape(lines, i),
          responseDecoder: extractDecoder(lines, i),
          providerOrState: extractProvider(lines, i),
          eventConsumer: extractEvent(lines, i),
          streamConsumer: endpoint,
          model: extractModel(lines, i),
          currentValueSource: extractCursor(lines, i),
        })
      }
    }
    // Also catch string literals that look like endpoints but not via call (for coverage)
    // Don't double count; this is now handled by the open() capture above, keep fallback for plain literals in non-stream contexts
    {
      const re = /['"](session\/[a-zA-Z0-9\/_-]+|settings\/[a-zA-Z0-9\/_-]+|workspace\/[a-zA-Z0-9\/_-]+|llm\/[a-zA-Z0-9\/_-]+|pluginInventory\/[a-zA-Z0-9\/_-]+|agentPresets\/[a-zA-Z0-9\/_-]+|host\/[a-zA-Z0-9\/_-]+|remote\/[a-zA-Z0-9\/_-]+|credentials\/[a-zA-Z0-9\/_-]+|skills\/[a-zA-Z0-9\/_-]+|feed\/[a-zA-Z0-9\/_-]+|goals\/[a-zA-Z0-9\/_-]+|subagents\/[a-zA-Z0-9\/_-]+|fileReferences\/[a-zA-Z0-9\/_-]+)['"]/g
      let mm: RegExpExecArray | null
      while ((mm = re.exec(line)) !== null) {
        const endpoint = mm[1]
        if (sites.some(s => s.line === i + 1 && s.endpoint === endpoint)) continue
        if (line.trim().startsWith('//') || line.trim().startsWith('*')) continue
        // Only add if this line looks like an endpoint literal used as data (not already captured via open/_postTypert/callMethod)
        // For coverage, we intentionally do not push here to avoid false positives from comments or error-code strings.
        // The stream case is already handled above; other string literals are informational (e.g., error codes like session/fork-unavailable).
        void endpoint
      }
    }
  }
  return sites
}

function mapMethodToEndpoint(method: string): string {
  const map: Record<string, string> = {
    getSessions: 'session/list',
    getSessionHistory: 'session/page',
    getSessionEvents: 'session/page',
    sendMessage: 'session/prompt',
    createSession: 'session/create',
    cancelTurn: 'session/cancel',
    settingsDescribe: 'settings/describe',
    settingsMutate: 'settings/mutate',
    credentialsDescribe: 'credentials/describe',
    credentialsSet: 'credentials/set',
    llmProviders: 'llm/listProviders',
    llmModels: 'session/modelCatalog',
    sessionModels: 'session/modelCatalog',
    sessionSelectModel: 'session/selectModel',
    workspaceList: 'workspace/list',
    workspaceCreate: 'workspace/create',
    skillList: 'skills/list',
    agentPresetList: 'agentPresets/list',
    agentPresetSelect: 'agentPresets/select',
    hostDescribe: 'host/describe',
    remotePair: 'remote/pair',
    fetchWsTicket: 'remote/ws-ticket',
    pluginInventoryList: 'pluginInventory/list',
  }
  return map[method] ?? method
}

function extractRequestShape(lines: string[], idx: number): string | null {
  const window = lines.slice(Math.max(0, idx - 2), Math.min(lines.length, idx + 6)).join(' ')
  const m = window.match(/\{[^}]{0,200}\}/)
  return m ? m[0].slice(0, 160) : null
}

function extractDecoder(lines: string[], idx: number): string | null {
  const window = lines.slice(idx, Math.min(lines.length, idx + 4)).join(' ')
  if (window.includes('fromJson')) return 'fromJson'
  if (window.includes('_unwrapValue')) return '_unwrapValue'
  if (window.includes('_extract')) return 'extractor'
  return null
}

function extractProvider(lines: string[], idx: number): string | null {
  const window = lines.slice(Math.max(0, idx - 3), Math.min(lines.length, idx + 3)).join(' ')
  if (window.includes('Riverpod') || window.includes('ref.watch') || window.includes('Provider')) {
    const m = window.match(/(\w+Provider|\w+Controller)/)
    return m ? m[1] : 'Riverpod'
  }
  return null
}

function extractEvent(lines: string[], idx: number): string | null {
  const window = lines.slice(Math.max(0, idx - 2), Math.min(lines.length, idx + 4)).join(' ')
  if (window.includes('event') || window.includes('SessionEvent')) return 'session/event'
  return null
}

function extractStream(lines: string[], idx: number): string | null {
  const window = lines.slice(Math.max(0, idx - 2), Math.min(lines.length, idx + 4)).join(' ')
  if (window.includes('eventsMux') || window.includes('events.mux')) return 'events.mux'
  if (window.includes('eventsHost') || window.includes('events.host')) return 'events.host'
  if (window.includes('follow')) return 'session/follow'
  return null
}

function extractModel(lines: string[], idx: number): string | null {
  const window = lines.slice(Math.max(0, idx - 2), Math.min(lines.length, idx + 4)).join(' ')
  if (window.includes('model')) return 'model'
  return null
}

function extractCursor(lines: string[], idx: number): string | null {
  const window = lines.slice(Math.max(0, idx - 2), Math.min(lines.length, idx + 6)).join(' ')
  if (window.includes('throughSeq') || window.includes('cursor') || window.includes('acceptedSeq')) return 'throughSeq cursor'
  return null
}
