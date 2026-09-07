// @ts-nocheck
/** Shared types for upstream-sync machinery. */

export interface UpstreamState {
  upstreamRepository: string
  upstreamBranch: string
  lastSynchronizedSha: string
  currentUpstreamSha: string
  localForkSha: string
  mergeBase: string
  originMasterSha: string
  synchronizationTimestamp: string
  behindBy: number
  aheadBy: number
  generatedBy: string
}

export type FileCategory =
  | 'HOST'
  | 'API'
  | 'CLIENT'
  | 'REACT'
  | 'FLUTTER'
  | 'CORE'
  | 'INTERACTION'
  | 'MODEL'
  | 'STREAM'
  | 'SECURITY'
  | 'BUILD'
  | 'DOCS'
  | 'TEST'
  | 'OTHER'

export interface ClassifiedFile {
  path: string
  status: 'added' | 'modified' | 'deleted' | 'renamed' | 'copied' | 'unmerged'
  oldPath?: string
  category: FileCategory
}

export interface FileClassification {
  oldSha: string
  newSha: string
  total: number
  added: ClassifiedFile[]
  modified: ClassifiedFile[]
  deleted: ClassifiedFile[]
  renamed: ClassifiedFile[]
  byCategory: Record<FileCategory, number>
  files: ClassifiedFile[]
}

export interface ApiOperation {
  namespace: string
  operation: string
  endpoint: string
  wireEndpoint: string
  method: string
  exportName: string | null
  mode: 'unary' | 'stream'
  serviceKey: string
  sourceFile: string
  line: number
  requestShape: string | null
  responseShape: string | null
  args: string[]
  transport: 'typert/unary' | 'typert/stream' | 'websocket' | 'http'
  authorization: 'none' | 'browser' | 'bearer-full' | 'bearer-limited' | 'unknown'
}

export interface ApiContract {
  rev: string
  generatedAt: string
  operations: ApiOperation[]
  namespaces: string[]
  endpoints: string[]
  byNamespace: Record<string, ApiOperation[]>
  sourceFilesScanned: number
}

export interface StreamEndpoint {
  name: string
  path: string
  kind: 'websocket' | 'sse' | 'http'
  sourceFile: string
}

export interface StreamFrame {
  name: string
  description: string
  sourceFile: string
}

export interface StreamContract {
  rev: string
  generatedAt: string
  endpoints: StreamEndpoint[]
  frames: StreamFrame[]
  features: {
    heartbeatMs: number | null
    reconnect: string
    generation: string
    authentication: string
    errorCodes: string[]
  }
  sourceFilesScanned: number
}

export interface ReactSurface {
  id: string
  sourceFile: string
  apiUsed: string[]
  requestShape: string | null
  responseShape: string | null
  modelUsed: string[]
  eventUsed: string[]
  streamUsed: string[]
  stateSource: string | null
  currentValueSource: string | null
  fallbackBehavior: string | null
  errorBehavior: string | null
  lifecycle: string | null
}

export interface ReactContract {
  generatedAt: string
  rev: string
  surfaces: ReactSurface[]
  totalSurfaces: number
}

export interface FlutterCallSite {
  file: string
  line: number
  api: string
  endpoint: string
  wireEndpoint: string
  requestShape: string | null
  responseDecoder: string | null
  providerOrState: string | null
  eventConsumer: string | null
  streamConsumer: string | null
  model: string | null
  currentValueSource: string | null
}

export interface FlutterContract {
  generatedAt: string
  filesScanned: number
  callSites: FlutterCallSite[]
  endpointsUsed: string[]
  modelsUsed: string[]
}

export type ParityStatus = 'PASS' | 'MISSING' | 'OUTDATED' | 'INCOMPATIBLE' | 'REMOVED' | 'UNKNOWN'

export interface ParityEntry {
  id: string
  reactApi: string
  flutterApi: string | null
  status: ParityStatus
  severity: 'P0' | 'P1' | 'P2' | 'P3'
  reactSource: string
  flutterSource: string | null
  reason: string
}

export interface ParityReport {
  generatedAt: string
  total: number
  pass: number
  missing: number
  outdated: number
  incompatible: number
  removed: number
  unknown: number
  entries: ParityEntry[]
}

export interface ImpactEntry {
  id: string
  change: string
  category: string
  severity: 'P0' | 'P1' | 'P2' | 'P3'
  affectedFiles: string[]
  reason: string
  requiredAction: string
  status: 'open' | 'audited' | 'planned' | 'migrated' | 'verified' | 'ignored'
  firstSeenUpstreamSha: string
  lastSeenUpstreamSha: string
  sourceFiles: string[]
}

export interface FlutterImpact {
  generatedAt: string
  oldSha: string
  newSha: string
  entries: ImpactEntry[]
  bySeverity: Record<string, number>
}

export interface ChangeRegistryEntry {
  id: string
  oldValue: string | null
  newValue: string | null
  category: FileCategory | 'API' | 'STREAM' | 'MODEL' | 'EVENT' | 'SECURITY' | 'REACT'
  severity: 'P0' | 'P1' | 'P2' | 'P3'
  reactStatus: ParityStatus
  flutterStatus: ParityStatus
  hostStatus: 'PASS' | 'MISSING' | 'CHANGED'
  migrationStatus: 'Detected' | 'Audited' | 'Planned' | 'Migrated' | 'Integrated' | 'Verified' | 'Ignored'
  firstSeenUpstreamSha: string
  lastSeenUpstreamSha: string
  sourceFiles: string[]
  affectedFlutterFiles: string[]
  description: string
}

export interface ChangeRegistry {
  generatedAt: string
  oldSha: string
  newSha: string
  total: number
  entries: ChangeRegistryEntry[]
}

export interface ApiDiffEntry {
  id: string
  kind:
    | 'added'
    | 'removed'
    | 'renamed'
    | 'namespace-rename'
    | 'operation-rename'
    | 'dot-to-slash'
    | 'pluralization'
    | 'request-wrapper'
    | 'response-wrapper'
    | 'required-field'
    | 'optional-field'
    | 'enum'
    | 'type'
    | 'nesting'
    | 'transport'
    | 'authorization'
    | 'split'
    | 'merged'
    | 'unchanged'
  oldEndpoint: string | null
  newEndpoint: string | null
  oldValue: string | null
  newValue: string | null
  severity: 'P0' | 'P1' | 'P2' | 'P3'
  description: string
  sourceFiles: string[]
}

export interface ApiDiff {
  generatedAt: string
  oldSha: string
  newSha: string
  total: number
  breaking: number
  additive: number
  entries: ApiDiffEntry[]
}

export interface StreamDiffEntry {
  id: string
  kind: 'added' | 'removed' | 'changed' | 'renamed'
  field: string
  oldValue: string | null
  newValue: string | null
  severity: 'P0' | 'P1' | 'P2' | 'P3'
  description: string
}

export interface StreamDiff {
  generatedAt: string
  oldSha: string
  newSha: string
  total: number
  entries: StreamDiffEntry[]
}
