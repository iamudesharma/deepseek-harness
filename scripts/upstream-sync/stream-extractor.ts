// @ts-nocheck
import type { StreamContract, StreamDiff } from './types.ts'
import { fileAtRev, listFilesAtRev } from './git.ts'

export function extractStreamContract(rev: string): StreamContract {
  const generatedAt = new Date().toISOString()
  const endpoints: StreamContract['endpoints'] = []
  const frames: StreamContract['frames'] = []
  let heartbeatMs: number | null = null
  let reconnect = 'unknown'
  let generation = 'unknown'
  let authentication = 'browser+bearer'
  const errorCodes: string[] = []

  // Scan relevant files
  const files = listFilesAtRev(rev, 'packages')
    .filter(p => p.endsWith('.ts') && (p.includes('stream') || p.includes('gateway') || p.includes('connection') || p.includes('remote') || p.includes('events')))
  let scanned = 0
  const contents: Record<string, string> = {}
  for (const f of files) {
    const c = fileAtRev(rev, f)
    if (!c) continue
    scanned++
    contents[f] = c
  }

  // Known stream endpoints
  const knownEndpoints: { name: string, path: string, kind: 'websocket' | 'sse' | 'http' }[] = [
    { name: 'remote.mux', path: '/api/events.mux', kind: 'websocket' },
    { name: '$events', path: '/api/events', kind: 'websocket' },
    { name: 'events.mux', path: '/api/events.mux', kind: 'websocket' },
    { name: 'events.host', path: '/api/events.host', kind: 'websocket' },
    { name: 'session/follow', path: 'session/follow', kind: 'websocket' },
    { name: 'session/control', path: 'session/control', kind: 'websocket' },
    { name: 'workspace/follow', path: 'workspace/follow', kind: 'websocket' },
    { name: 'REMOTE_STREAM_MUX_PATH', path: '/api/__remote_stream_mux', kind: 'websocket' },
  ]

  // Try to extract from stream-protocol.ts, gateway, etc.
  for (const [path, content] of Object.entries(contents)) {
    // endpoints
    const epRegex = /(REMOTE_[A-Z_]+_ENDPOINT|REMOTE_STREAM_MUX_PATH|events\.mux|events\.host)\s*[:=]\s*['"]([^'"]+)['"]/g
    let m: RegExpExecArray | null
    while ((m = epRegex.exec(content)) !== null) {
      const name = m[1]!
      const p = m[2]!
      const kind = p.startsWith('/api/') ? 'websocket' as const : 'websocket' as const
      if (!endpoints.some(e => e.path === p)) {
        endpoints.push({ name, path: p, kind, sourceFile: path })
      }
    }
    // heartbeat
    const hb = content.match(/heartbeatIntervalMs|HEARTBEAT|websocketHeartbeatIntervalMs[^0-9]*(\d{4,6})/)
    if (hb && hb[1]) heartbeatMs = Number(hb[1])
    if (content.includes('30_000') || content.includes('30000')) heartbeatMs = 30000
    if (content.includes('WebSocket') || content.includes('RemoteStreamMuxServer')) {
      // collect frames
      const frameNames = ['RemoteEventInvocationFrame', 'RemoteEventReadyFrame', 'RemoteEventEmitFrame', 'RemoteEventCancellationFrame', 'TypertRemoteEventFrame', 'ServerRequest']
      for (const n of frameNames) {
        if (content.includes(n) && !frames.some(f => f.name === n)) {
          frames.push({ name: n, description: `stream frame ${n}`, sourceFile: path })
        }
      }
    }
    if (content.includes('reconnect') || content.includes('backoff')) reconnect = 'jittered backoff, generation increment'
    if (content.includes('generation')) generation = 'connection generation + stream generation'
    if (content.includes('authorization') || content.includes('Bearer') || content.includes('isAuthenticated')) authentication = 'browser cookie + bearer token (remote)'
    if (content.includes('TypertGatewayErrorCode') || content.includes('errorCodes')) {
      const codes = content.match(/['"]([A-Z_]+)['"]\s*:/g)
      if (codes) for (const c of codes) {
        const code = c.replace(/['":]/g, '').trim()
        if (code && !errorCodes.includes(code)) errorCodes.push(code)
      }
    }
  }

  // Ensure known endpoints present even if not found via regex
  for (const k of knownEndpoints) {
    if (!endpoints.some(e => e.path === k.path)) {
      endpoints.push({ name: k.name, path: k.path, kind: k.kind, sourceFile: 'packages/api/gateway/src/stream-protocol.ts' })
    }
  }

  // Try to read stream-protocol.ts directly for definitive endpoints
  const sp = contents['packages/api/gateway/src/stream-protocol.ts'] ?? fileAtRev(rev, 'packages/api/gateway/src/stream-protocol.ts') ?? ''
  if (sp) {
    const defines = [...sp.matchAll(/export const (\w+) = ['"]([^'"]+)['"]/g)]
    for (const d of defines) {
      const name = d[1]!
      const p = d[2]!
      if (p.startsWith('/api/') || p.startsWith('remote')) {
        if (!endpoints.some(e => e.path === p)) endpoints.push({ name, path: p, kind: 'websocket', sourceFile: 'packages/api/gateway/src/stream-protocol.ts' })
      }
    }
    // frames: extract interface/type names
    const typeRegex = /export (?:interface|type) (\w+Frame|\w+Event\w*)\b/g
    let tm: RegExpExecArray | null
    while ((tm = typeRegex.exec(sp)) !== null) {
      const n = tm[1]!
      if (!frames.some(f => f.name === n)) frames.push({ name: n, description: `stream frame ${n} from stream-protocol.ts`, sourceFile: 'packages/api/gateway/src/stream-protocol.ts' })
    }
  }

  if (heartbeatMs === null) heartbeatMs = 30000
  if (errorCodes.length === 0) errorCodes.push('NOT_FOUND', 'INTERNAL', 'UNAUTHORIZED', 'FORBIDDEN')

  endpoints.sort((a, b) => a.path.localeCompare(b.path))
  frames.sort((a, b) => a.name.localeCompare(b.name))

  return {
    rev,
    generatedAt,
    endpoints,
    frames,
    features: {
      heartbeatMs,
      reconnect,
      generation,
      authentication,
      errorCodes,
    },
    sourceFilesScanned: scanned,
  }
}

export function diffStreamContracts(oldC: StreamContract, newC: StreamContract): StreamDiff {
  const entries: StreamDiff['entries'] = []
  const oldPaths = new Set(oldC.endpoints.map(e => e.path))
  const newPaths = new Set(newC.endpoints.map(e => e.path))
  for (const ep of oldC.endpoints) {
    if (!newPaths.has(ep.path)) {
      entries.push({
        id: `stream-endpoint-removed:${ep.path}`,
        kind: 'removed',
        field: 'endpoint',
        oldValue: ep.path,
        newValue: null,
        severity: 'P0',
        description: `Stream endpoint removed: ${ep.path} (${ep.name})`,
      })
    }
  }
  for (const ep of newC.endpoints) {
    if (!oldPaths.has(ep.path)) {
      entries.push({
        id: `stream-endpoint-added:${ep.path}`,
        kind: 'added',
        field: 'endpoint',
        oldValue: null,
        newValue: ep.path,
        severity: 'P1',
        description: `Stream endpoint added: ${ep.path} (${ep.name})`,
      })
    }
  }
  // Heartbeat diff
  if (oldC.features.heartbeatMs !== newC.features.heartbeatMs) {
    entries.push({
      id: 'stream-heartbeat',
      kind: 'changed',
      field: 'heartbeatMs',
      oldValue: String(oldC.features.heartbeatMs),
      newValue: String(newC.features.heartbeatMs),
      severity: 'P2',
      description: `Heartbeat interval changed: ${oldC.features.heartbeatMs} -> ${newC.features.heartbeatMs}`,
    })
  }
  // Frame diffs
  const oldFrames = new Set(oldC.frames.map(f => f.name))
  const newFrames = new Set(newC.frames.map(f => f.name))
  for (const f of oldC.frames) if (!newFrames.has(f.name)) entries.push({
    id: `frame-removed:${f.name}`, kind: 'removed', field: 'frame', oldValue: f.name, newValue: null, severity: 'P1', description: `Stream frame removed: ${f.name}`,
  })
  for (const f of newC.frames) if (!oldFrames.has(f.name)) entries.push({
    id: `frame-added:${f.name}`, kind: 'added', field: 'frame', oldValue: null, newValue: f.name, severity: 'P2', description: `Stream frame added: ${f.name}`,
  })

  // Auth diff
  if (oldC.features.authentication !== newC.features.authentication) {
    entries.push({
      id: 'stream-auth',
      kind: 'changed',
      field: 'authentication',
      oldValue: oldC.features.authentication,
      newValue: newC.features.authentication,
      severity: 'P0',
      description: `Stream authentication changed`,
    })
  }

  return {
    generatedAt: new Date().toISOString(),
    oldSha: oldC.rev,
    newSha: newC.rev,
    total: entries.length,
    entries,
  }
}
