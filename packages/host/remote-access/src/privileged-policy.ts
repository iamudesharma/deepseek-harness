/**
 * Remote authorization policy: safe vs privileged methods.
 * @module @deepseek-ai/dsh-host-remote-access/privileged-policy
 */

/**
 * Method classification.
 * A: safe remote — session reads/writes, conversation, plan, model selection,
 *    permission flow, workspace metadata, approvals/questions.
 * B: privileged — filesystem, credentials, host OS, sensitive settings,
 *    host process management. Requires explicit remote scope/authorization
 *    (Phase 2: bearer 'full' is required; privileged methods additionally
 *    check that the remote authorization policy allows them).
 */
export type RemoteMethodClass = 'safe' | 'privileged'

const PRIVILEGED_PREFIXES: readonly string[] = [
  'host.',
  'credentials.',
  'settings.',
  'agentPreset.',
]

const PRIVILEGED_EXACT: ReadonlySet<string> = new Set([
  'host.pickDirectory',
  'host.listDirectory',
  'host.createDirectory',
  'host.openPath',
  'credentials.describe',
  'credentials.set',
  'credentials.unset',
  'settings.describe',
  'settings.openDocument',
  'settings.update',
  'settings.replace',
  'settings.mutate',
  'agentPreset.read',
  'agentPreset.copy',
  'agentPreset.openDocument',
  'agentPreset.remove',
])

/**
 * Classify a Remote or RPC endpoint.
 * @param endpoint - wire endpoint like 'session.list' or 'remote.pair'.
 * @returns 'privileged' or 'safe'.
 */
export function classifyRemoteMethod(endpoint: string): RemoteMethodClass {
  if (PRIVILEGED_EXACT.has(endpoint)) return 'privileged'
  if (PRIVILEGED_PREFIXES.some(prefix => endpoint.startsWith(prefix))) return 'privileged'
  return 'safe'
}

/**
 * Whether a bearer-authenticated remote request is authorized for the endpoint.
 * @param endpoint - target endpoint.
 * @param authority - request authority ('loopback' | 'trusted-host' | 'bearer').
 * @param tokenScope - bearer token scope when authority is bearer.
 * @returns true when authorized; when false the caller should answer 403.
 */
export function isRemoteAuthorized(
  endpoint: string,
  authority: 'loopback' | 'trusted-host' | 'bearer',
  tokenScope?: string,
): boolean {
  if (authority === 'loopback' || authority === 'trusted-host') return true
  // Bearer path: safe methods allowed only with 'full' (ws tickets must not be used for HTTP RPC).
  const klass = classifyRemoteMethod(endpoint)
  if (klass === 'safe') return tokenScope === 'full'
  // Privileged remote is DENIED unless explicitly authorized (future scope).
  // Phase 2: "For privileged methods, require explicit remote scope/authorization. Do not silently convert loopback into full."
  // Exception: remote.* management endpoints are bearer-full allowed (except pair which is unauthenticated).
  if (endpoint.startsWith('remote.')) {
    return tokenScope === 'full'
  }
  return false
}
