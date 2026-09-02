// @ts-nocheck
import type { ApiDiff, FlutterContract, FlutterImpact, ImpactEntry, ParityReport, ParityStatus, ReactContract } from './types.ts'

const TOOL_MAP: Record<string, string[]> = {
  'session/list': ['message_provider.dart', 'trajectory_provider.dart', 'session_workspace_services.dart', 'sidebar.dart'],
  'session/page': ['message_provider.dart', 'trajectory_provider.dart', 'tool_models.dart', 'subagent_provider.dart', 'session_workspace_services.dart'],
  'session/prompt': ['prompt_provider.dart', 'queue_provider.dart', 'composer.dart'],
  'session/create': ['session_workspace_services.dart', 'sidebar.dart'],
  'session/cancel': ['trajectory_provider.dart', 'queue_provider.dart'],
  'session/updateQueue': ['queue_provider.dart'],
  'session/attachment': ['message_provider.dart', 'attachment_provider.dart'],
  'session/modelCatalog': ['model_directory.dart', 'model_selection.dart'],
  'session/selectModel': ['model_directory.dart'],
  'session/search': ['sidebar.dart', 'session_search_provider.dart'],
  'settings/describe': ['settings_screen.dart', 'settings_scope.dart', 'card-form.ts'],
  'settings/mutate': ['settings_scope.dart', 'card-form.ts'],
  'credentials/describe': ['credential_provider.dart'],
  'credentials/set': ['credential_provider.dart'],
  'credentials/unset': ['credential_provider.dart'],
  'llm/listProviders': ['model_directory.dart', 'llm_client.dart'],
  'llm/listConfigurableProviders': ['model_directory.dart'],
  'llm/discoverModels': ['model_directory.dart'],
  'workspace/list': ['sidebar.dart', 'workspace_provider.dart', 'session_workspace_services.dart'],
  'workspace/create': ['workspace_provider.dart'],
  'workspace/insertBefore': ['sidebar.dart'],
  'workspace/insertSessionBefore': ['sidebar.dart'],
  'workspace/rename': ['sidebar.dart'],
  'workspace/delete': ['sidebar.dart'],
  'skills/list': ['skill_provider.dart'],
  'pluginInventory/list': ['settings_screen.dart', 'inventory_provider.dart'],
  'agentPresets/list': ['agent_preset_provider.dart', 'model_selection.dart'],
  'agentPresets/select': ['agent_preset_provider.dart'],
  'host/describe': ['connection_controller.dart', 'host_provider.dart'],
  'remote/pair': ['remote_pairing_client.dart', 'pairing_screen.dart'],
  'remote/ws-ticket': ['remote_mux_client.dart', 'connection_client.dart'],
  'remote/refresh': ['secure_token_store.dart'],
  'events.mux': ['connection_controller.dart', 'live_sync_provider.dart'],
  'events.host': ['connection_controller.dart', 'workspace_provider.dart'],
}

function _severityFor(endpoint: string, kind: string): 'P0' | 'P1' | 'P2' | 'P3' {
  if (kind === 'removed' || kind === 'dot-to-slash' || kind === 'transport') return 'P0'
  if (kind === 'split' || kind === 'request-wrapper' || kind === 'namespace-rename') return 'P0'
  if (endpoint.includes('session/page') || endpoint.includes('session/prompt') || endpoint.includes('events')) return 'P0'
  if (kind === 'added') return 'P2'
  return 'P1'
}
void _severityFor

export function analyzeFlutterImpact(
  apiDiff: ApiDiff,
  flutter: FlutterContract,
  oldSha: string,
  newSha: string,
): FlutterImpact {
  const generatedAt = new Date().toISOString()
  const entries: ImpactEntry[] = []

  for (const diff of apiDiff.entries) {
    const endpoint = diff.newEndpoint ?? diff.oldEndpoint ?? diff.id
    const normalized = endpoint.replace('/api/', '')
    const affectedByMap = TOOL_MAP[normalized] ?? []
    const affectedByFlutter = flutter.callSites
      .filter(cs => cs.endpoint === normalized || cs.endpoint.replace('/', '.') === normalized || cs.api === normalized)
      .map(cs => cs.file)
    const affected = [...new Set([...affectedByMap, ...affectedByFlutter])].map(f => f.includes('/') ? f : `apps/flutter/lib/src/${f}`)
    // Add more specific file matches via flutter contract
    const severity = diff.severity as 'P0' | 'P1' | 'P2' | 'P3'
    let requiredAction = 'audit'
    if (diff.kind === 'dot-to-slash') requiredAction = 'update Flutter _wireEndpoint usage; ensure gateway slash route matches'
    else if (diff.kind === 'removed') requiredAction = 'remove or replace Flutter call; feature will 404'
    else if (diff.kind === 'split') requiredAction = 'adapt Flutter to new split endpoints (e.g., llm/providers split)'
    else if (diff.kind === 'request-wrapper') requiredAction = 'update Flutter payload to {args: ...} or {request: ...} wrapper'
    else if (diff.kind === 'added') requiredAction = 'evaluate if Flutter should consume new endpoint'
    else if (diff.kind === 'transport') requiredAction = 'update Flutter transport from unary to stream or vice versa'
    else requiredAction = `audit Flutter consumers of ${normalized}`

    entries.push({
      id: diff.id,
      change: `${diff.kind}: ${diff.oldEndpoint ?? '∅'} → ${diff.newEndpoint ?? '∅'}`,
      category: 'API',
      severity,
      affectedFiles: affected.length ? affected : flutter.callSites.filter(cs => cs.endpoint.includes(normalized.split('/')[0]!)).map(cs => cs.file).slice(0, 5),
      reason: diff.description,
      requiredAction,
      status: 'open',
      firstSeenUpstreamSha: oldSha,
      lastSeenUpstreamSha: newSha,
      sourceFiles: diff.sourceFiles,
    })
  }

  // Additional architectural mismatches not captured by endpoint diff but known from Flutter codebase
  const knownMismatches: ImpactEntry[] = [
    {
      id: 'flutter:session/page-cursor',
      change: 'session/page throughSeq sentinel vs cursor',
      category: 'API',
      severity: 'P0',
      affectedFiles: ['apps/flutter/lib/src/core/connection/connection_client.dart', 'apps/flutter/lib/src/features/session/live_history.dart'],
      reason: 'React session/page requires authoritative throughSeq from session/follow snapshot.cursor; Flutter previously used sentinel/discovery (-1). Architecture mismatch if Flutter still synthesizes cursor.',
      requiredAction: 'verify Flutter getSessionHistory requires throughSeq and waits for LiveHistory.acceptedSeq; no fabricated cursor',
      status: 'open',
      firstSeenUpstreamSha: oldSha,
      lastSeenUpstreamSha: newSha,
      sourceFiles: ['packages/api/session-controller/src/index.ts'],
    },
    {
      id: 'flutter:settings-describe-list',
      change: 'settings/describe List namespaces',
      category: 'API',
      severity: 'P0',
      affectedFiles: ['apps/flutter/lib/src/features/settings/settings_scope.dart', 'apps/flutter/lib/src/features/settings/settings_screen.dart'],
      reason: 'Host SettingsController returns {namespaces: List<{ns,schema,value,revision}>} not Map. Flutter must handle List form (see recent fix).',
      requiredAction: 'ensure SettingsScope._refreshNow handles List<Map> and fallback forms; verified in be6498fd',
      status: 'open',
      firstSeenUpstreamSha: oldSha,
      lastSeenUpstreamSha: newSha,
      sourceFiles: ['packages/api/settings-controller/src/index.ts'],
    },
    {
      id: 'flutter:remote-mux-ticket',
      change: 'remote.mux bearer ticket flow',
      category: 'STREAM',
      severity: 'P1',
      affectedFiles: ['apps/flutter/lib/src/core/connection/remote_mux_client.dart', 'apps/flutter/lib/src/core/connection/connection_client.dart', 'apps/flutter/lib/src/core/connection/connection_controller.dart'],
      reason: 'Remote WebSocket requires single-use ws-ticket (bearer full). Flutter must fetch ticket before opening wss://…?ticket= and handle 401→needsReauth.',
      requiredAction: 'verify ticket fetch and re-pair flow; no silent fallback to unauthenticated',
      status: 'open',
      firstSeenUpstreamSha: oldSha,
      lastSeenUpstreamSha: newSha,
      sourceFiles: ['packages/host/remote-access/src/remote-service.ts', 'packages/api/gateway/src/stream-protocol.ts'],
    },
  ]
  // Only add known mismatches if not already covered by diff entries
  for (const km of knownMismatches) {
    if (!entries.some(e => e.id === km.id)) entries.push(km)
  }

  const bySeverity: Record<string, number> = { P0: 0, P1: 0, P2: 0, P3: 0 }
  for (const e of entries) bySeverity[e.severity!]++

  return {
    generatedAt,
    oldSha,
    newSha,
    entries: entries.sort((a, b) => {
      const order = { P0: 0, P1: 1, P2: 2, P3: 3 } as const
      if (order[a.severity] !== order[b.severity]) return order[a.severity] - order[b.severity]
      return a.id.localeCompare(b.id)
    }),
    bySeverity,
  }
}

export function buildParity(
  react: ReactContract,
  flutter: FlutterContract,
): ParityReport {
  const entries: ParityReport['entries'] = []
  // Build set of endpoints used by React (from react surfaces) and by Flutter
  // Only consider real Typert endpoints (namespace/operation), not arbitrary event/error strings.
  const ALLOWED_NAMESPACES = new Set([
    'agent-team','agentPresets','commands','cordis-host-runner','credentials','directoryPicker','feed','fileReferences','goals','llm','messageFeedback','pluginInventory','session','sessionReferenceResolver','settings','skills','subagents','subagent','workspace','host','remote','remoteNotifications',
    'pluginInventory','sessionReferenceResolver',
  ])
  function isValidEndpoint(ep: string): boolean {
    if (!ep.includes('/')) return false
    if (ep.includes(' ')) return false
    if (ep.length > 80) return false
    const [ns, op] = ep.split('/')
    if (!ALLOWED_NAMESPACES.has(ns)) return false
    if (!op || op.length < 2) return false
    // Exclude known error/event suffixes that are not RPCs
    const badOps = ['agent-busy','attachment-invalid','conflict','created','end-seed','forbidden','not-found','title-invalid','workspace-attach-failed','document-updated','rejected','reference-updated','adapters-updated','model-discovery-rejected','retry','retry-started','not-found']
    if (badOps.includes(op)) return false
    // operation should be alphanumeric with maybe -/_/. ; error codes like "agent-busy" look like RPC but are actually error codes; filter via badOps already
    // Also exclude strings containing sentences
    if (ep.includes(' carrier ') || ep.includes(' did not ') || ep.includes(' before ')) return false
    return true
  }

  const reactEndpoints = new Set<string>()
  for (const s of react.surfaces) for (const api of s.apiUsed) if (isValidEndpoint(api)) reactEndpoints.add(api)
  // Add known explicit ones
  const known = ['session/list','session/page','session/prompt','session/create','session/cancel','settings/describe','settings/mutate','workspace/list','agentPresets/list','agentPresets/select','pluginInventory/list','host/describe','session/modelCatalog','session/selectModel','session/attachment','session/search','session/updateQueue','session/cancel','workspace/create','workspace/delete','workspace/rename','workspace/insertBefore','workspace/insertSessionBefore','credentials/describe','credentials/set','credentials/unset','llm/listProviders','llm/listConfigurableProviders','llm/discoverModels','skills/list','fileReferences/list','commands/list','commands/execute']
  for (const k of known) if (isValidEndpoint(k) || k.includes('/')) reactEndpoints.add(k)

  // Normalize Flutter endpoints: both slash and dot variants map to slash for comparison
  const flutterEndpointsSlash = new Set(flutter.endpointsUsed.map(ep => ep.replaceAll('.', '/')).filter(isValidEndpoint))
  const flutterDotVariants = new Map<string, string>() // slash -> original dot
  for (const ep of flutter.endpointsUsed) {
    if (ep.includes('.') && isValidEndpoint(ep.replaceAll('.', '/'))) {
      const slash = ep.replaceAll('.', '/')
      if (!flutterDotVariants.has(slash)) flutterDotVariants.set(slash, ep)
    }
  }

  for (const ep of [...reactEndpoints].sort()) {
    const flutterHas = flutterEndpointsSlash.has(ep)
    const dotVariant = flutterDotVariants.get(ep)
    const status: ParityStatus = flutterHas ? (dotVariant ? 'OUTDATED' : 'PASS') : 'MISSING'
    const severity = status === 'PASS' ? 'P3' as const : status === 'OUTDATED' ? 'P1' as const : (ep.includes('session/') || ep.includes('settings/') ? 'P0' as const : 'P1' as const)
    const reactSource = react.surfaces.find(s => s.apiUsed.includes(ep))?.sourceFile ?? 'packages/client/connection/src'
    const flutterSource = flutterHas ? flutter.callSites.find(cs => cs.endpoint.replaceAll('.', '/') === ep)?.file ?? null : null
    const reason = status === 'PASS' ? `React and Flutter both use ${ep}` : status === 'OUTDATED' ? `React uses ${ep} (slash) but Flutter still has dot variant ${dotVariant} — needs slash migration (Flutter _wireEndpoint handles but Host may 404)` : `React uses ${ep} but Flutter does not call it`
    entries.push({
      id: `parity:${ep}`,
      reactApi: ep,
      flutterApi: flutterHas ? ep : null,
      status,
      severity,
      reactSource,
      flutterSource,
      reason,
    })
  }

  // Incompatible dot variants that are not in reactEndpoints but should be flagged (Flutter uses dot where React uses slash)
  for (const [slash, dot] of flutterDotVariants) {
    if (reactEndpoints.has(slash)) continue // already handled as OUTDATED above
    // If React has slash for this dot, but we already marked as OUTDATED? Actually above we marked react eps that flutter has dot as OUTDATED, so this covers it.
    // Here handle dot variants where React does NOT have the slash endpoint (maybe deprecated or new)
    const normalized = slash
    if (reactEndpoints.has(normalized)) continue
    // Check if React has this endpoint at all (maybe not) — then it's unknown but dot is still outdated
    if (!reactEndpoints.has(normalized)) {
      // Still flag dot as incompatible if there's a slash version in api contract that React should have but doesn't in our surfaces
      // For now, create an entry
      entries.push({
        id: `parity:dot-vs-slash:${dot}`,
        reactApi: slash,
        flutterApi: dot,
        status: 'INCOMPATIBLE',
        severity: 'P0',
        reactSource: 'React slash (inferred)',
        flutterSource: flutter.callSites.find(cs => cs.endpoint === dot)?.file ?? null,
        reason: `BREAKING: Flutter uses ${dot} (dot) but expected ${slash} (slash). _wireEndpoint normalizes but ensure Host gateway slash route.`,
      })
    }
  }

  // Add Flutter-only endpoints that are truly unknown to React (slash, not dot)
  for (const ep of [...flutterEndpointsSlash].sort()) {
    if (reactEndpoints.has(ep)) continue
    // Skip if this slash came from a dot variant already flagged
    if ([...flutterDotVariants.values()].some(dot => dot.replaceAll('.', '/') === ep)) {
      // Already flagged as dot-vs-slash or handled
      const dot = [...flutterDotVariants.entries()].find(([s]) => s === ep)?.[1]
      if (dot) continue
    }
    // Unknown Flutter endpoint (maybe removed in upstream or new)
    entries.push({
      id: `parity:flutter-only:${ep}`,
      reactApi: ep,
      flutterApi: ep,
      status: 'UNKNOWN',
      severity: 'P2',
      reactSource: 'unknown in React contract',
      flutterSource: flutter.callSites.find(cs => cs.endpoint.replaceAll('.', '/') === ep)?.file ?? null,
      reason: `Flutter uses ${ep} not found in React surfaces; verify if deprecated or new`,
    })
  }

  // Specific architectural mismatches mentioned in spec
  const archChecks: { ep: string, reason: string, severity: 'P0'|'P1' }[] = [
    { ep: 'session/follow snapshot.cursor', reason: 'React session/follow snapshot.cursor vs Flutter session/page sentinel cursor discovery — ARCHITECTURAL MISMATCH', severity: 'P0' },
    { ep: 'agentPreset selected event', reason: 'React agentPreset selected event updates session state via events; Flutter must consume same event (event ignored → STATE/PARITY MISMATCH)', severity: 'P1' },
  ]
  for (const ac of archChecks) {
    // Add as separate entry if not already
    entries.push({
      id: `parity:arch:${ac.ep.replace(/\s+/g, '-')}`,
      reactApi: ac.ep,
      flutterApi: null,
      status: 'UNKNOWN',
      severity: ac.severity,
      reactSource: 'react-contract',
      flutterSource: null,
      reason: ac.reason,
    })
  }

  const pass = entries.filter(e => e.status === 'PASS').length
  const missing = entries.filter(e => e.status === 'MISSING').length
  const outdated = entries.filter(e => e.status === 'OUTDATED').length
  const incompatible = entries.filter(e => e.status === 'INCOMPATIBLE').length
  const removed = entries.filter(e => e.status === 'REMOVED').length
  const unknown = entries.filter(e => e.status === 'UNKNOWN').length

  return {
    generatedAt: new Date().toISOString(),
    total: entries.length,
    pass, missing, outdated, incompatible, removed, unknown,
    entries: entries.sort((a, b) => {
      const order = { INCOMPATIBLE: 0, MISSING: 1, UNKNOWN: 2, OUTDATED: 3, PASS: 4, REMOVED: 5 } as const
      const ao = (order as any)[a.status] ?? 9
      const bo = (order as any)[b.status] ?? 9
      if (ao !== bo) return ao - bo
      if (a.severity !== b.severity) return a.severity.localeCompare(b.severity)
      return a.id.localeCompare(b.id)
    }),
  }
}
