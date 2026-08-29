// @vitest-environment jsdom
/**
 * Semantic parity replay — React half of `$semantic-parity-replay`.
 *
 * Drives the canonical `parity-stream.jsonl` fixture (identical bytes to the
 * Flutter driver's input) through the REAL assembled web stack: runtime
 * plugin + ui-settings + locale + ui-theme + ui-layout + ui-conversation, fed
 * via the connection sinks (`ConnectionSinks.onMuxEnvelope`/`onHostEnvelope`)
 * exactly as `apps/web` wires them. The resulting conversation snapshot is
 * projected into the canonical v1 line schema and must byte-match the
 * committed `migration/parity-reports/react-parity-projection-v1.txt`; the
 * Flutter suite diffs its own projector against the same file, so the two
 * runtimes cannot drift silently.
 *
 * Schema v1 (state-derived, ordering = node seq order):
 *   session <id> blank=<bool> running=<bool>
 *   node <seq> user text="<text>"
 *   node <seq> assistant turn=<t> step=<s> blocks=<kind:count,...sorted> interrupted=<bool>
 *   node <seq> tool-result callId=<id> name=<name|-> error=<ErrorName|none>
 *   node <seq> <other-kind>
 *   turn-end <turn> seq=<seq>
 *   running-calls <n>
 *   queue <n>
 *   pending none|<kind>:<toolName?>
 */
import { existsSync, readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { Context } from '@deepseek-ai/cordis'
import { describe, expect, it } from 'vitest'
import type { ConnectionHandle, SessionId } from '@deepseek-ai/dsh-api-remotes/client'
import TypertRegistry from '@deepseek-ai/dsh-typert-registry'
import * as RuntimeClient from '../src/client/index.ts'
type SessionRuntime = {
  binding: (id: SessionId) => { session: { getSnapshot: () => unknown } } | undefined
  open: (id: SessionId) => void
  searchResultLimit: number
}
const SESSION_SEARCH_RESULT_LIMIT = 50
import { FakeApiClient, fakeRemote, ok } from './fake-api.client.ts'
// Sibling plugins mount through their public faces only (export discipline).
import { apply as applyLocale, inject as localeInject } from '@deepseek-ai/dsh-client-locale/client'
import { apply as applySettings, inject as settingsInject } from '@deepseek-ai/dsh-client-ui-settings/client'
import { apply as applyTheme, inject as themeInject } from '@deepseek-ai/dsh-client-ui-theme/client'
import { apply as applyLayout, inject as layoutInject } from '@deepseek-ai/dsh-client-ui-layout/client'
import { apply as applyConversation, inject as conversationInject } from '@deepseek-ai/dsh-client-ui-conversation/client'

/** Repo root: nearest ancestor containing the workspace marker. */
function repoRoot(): string {
  let dir = process.cwd()
  while (!existsSync(join(dir, 'pnpm-workspace.yaml'))) {
    const parent = resolve(dir, '..')
    if (parent === dir) throw new Error('repo root not found')
    dir = parent
  }
  return dir
}

const ROOT = repoRoot()
const FIXTURE = join(ROOT, 'apps/flutter/test/goldens/replay/parity-stream.jsonl')
const EXPECTED = join(ROOT, 'migration/parity-reports/react-parity-projection-v1.txt')

interface WireLine {
  stream: 'mux' | 'host'
  rpcId: string
  frame: Record<string, unknown>
}

function loadFixture(): WireLine[] {
  return readFileSync(FIXTURE, 'utf8')
    .split('\n')
    .filter(l => l.trim().length > 0)
    .map(l => JSON.parse(l) as WireLine)
}

interface SinkBag {
  onMuxEnvelope?: (envelope: { rpcId: unknown; payload: unknown }) => void
  onHostEnvelope?: (envelope: { rpcId: unknown; payload: unknown }) => void
  onConnected?: (description: unknown) => void
}

interface Bench {
  ctx: Context
  api: FakeApiClient
  sessions: SessionRuntime
  sinks: SinkBag
}

/** Mount the real assembled stack over a programmable fake connection. */
async function mount(): Promise<Bench> {
  const ctx = new Context()
  await ctx.plugin(TypertRegistry)
  const api = new FakeApiClient()
  api.onList = () =>
    Promise.resolve(ok({
      items: [{ sessionId: 's-200' as SessionId, updatedAt: 100, running: false, blank: true }] as never[],
    }))
  let sinks: SinkBag | undefined
  const handle = {
    api,
    isLoopback: true,
    hostDescription: {
      getSnapshot: () => undefined,
      subscribe: () => () => {},
    },
    rpc: { call: () => Promise.reject(new Error('unexpected generic RPC call')) },
    start: (s: unknown) => {
      sinks = s as SinkBag
      return { stop: () => {} }
    },
  } as unknown as ConnectionHandle
  ctx.reflect.provide('connection', handle)
  // Remote event fan-out face: the fixture carries host/remote-event frames.
  ctx.reflect.provide('remote', { $dispatch: () => {}, $on: () => () => {} })
  ctx.reflect.provide('remote.commands', fakeRemote().commands)

  await ctx.plugin(RuntimeClient).await()
  await ctx.plugin({ inject: settingsInject, apply: applySettings }).await()
  await ctx.plugin({ inject: localeInject, apply: applyLocale }).await()
  await ctx.plugin({ inject: themeInject, apply: applyTheme }).await()
  await ctx.plugin({ inject: layoutInject, apply: applyLayout }).await()
  await ctx.plugin({ inject: conversationInject, apply: applyConversation }).await()

  const sessions = ctx.get('sessions') as SessionRuntime
  if (sessions === undefined) throw new Error('sessions service missing after runtime apply')
  expect((sessions as unknown as { searchResultLimit: number }).searchResultLimit).toBe(SESSION_SEARCH_RESULT_LIMIT)
  if (sinks === undefined) throw new Error('connection sinks missing after runtime apply')
  return { ctx, api, sessions, sinks }
}

interface ProjectableNode extends Record<string, unknown> {
  seq: number
  kind: string
}

interface ProjectableSnapshot {
  blank: boolean
  running: boolean
  nodes: ProjectableNode[]
  turnEnds: ReadonlyMap<number, number>
  runningCalls: unknown[]
  queue: unknown[]
  pending: Array<{ kind: string; payload?: { toolName?: string } }>
}

/** Project one replayed session into schema v1. */
function project(snapshot: ProjectableSnapshot, sessionId: string): string[] {
  const lines: string[] = []
  lines.push(`session ${sessionId} blank=${snapshot.blank} running=${snapshot.running}`)
  for (const node of [...snapshot.nodes].sort((a, b) => a.seq - b.seq)) {
    switch (node.kind) {
      case 'user': {
        const content = node.content as readonly Record<string, unknown>[]
        const text = content.find(b => b.type === 'text')?.text
        lines.push(`node ${node.seq} user text="${typeof text === 'string' ? text : ''}"`)
        break
      }
      case 'assistant': {
        const histogram = new Map<string, number>()
        for (const block of node.blocks as readonly { kind: string }[]) {
          histogram.set(block.kind, (histogram.get(block.kind) ?? 0) + 1)
        }
        const blocks = [...histogram.entries()]
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([kind, n]) => `${kind}:${n}`)
          .join(',')
        lines.push(
          `node ${node.seq} assistant turn=${node.turn} step=${node.step} blocks=${blocks} interrupted=${node.interrupted === true}`,
        )
        break
      }
      case 'tool-result': {
        const call = node.call as { name: string } | null
        const error = node.error as { name: string } | null
        const subs = (node.subCalls as readonly { isError: boolean }[]) ?? []
        const subErrors = subs.filter(s => s.isError).length
        lines.push(
          `node ${node.seq} tool-result callId=${node.callId} name=${call?.name ?? '-'} error=${error?.name ?? 'none'} subcalls=${subs.length}/${subErrors}`,
        )
        break
      }
      case 'model-retry':
        lines.push(
          `node ${node.seq} model-retry retry=${node.retry} maxRetries=${node.maxRetries} state=${node.retryState}`,
        )
        break
      default:
        lines.push(`node ${node.seq} ${node.kind}`)
        break
    }
  }
  for (const [turn, seq] of [...snapshot.turnEnds].sort(([a], [b]) => a - b)) {
    lines.push(`turn-end ${turn} seq=${seq}`)
  }
  lines.push(`running-calls ${snapshot.runningCalls.length}`)
  lines.push(`queue ${snapshot.queue.length}`)
  const pending = snapshot.pending[0]
  if (pending === undefined) {
    lines.push('pending none')
  } else if (pending.kind === 'approval') {
    lines.push(`pending approval:${pending.payload?.toolName}`)
  } else {
    lines.push(`pending ${pending.kind}`)
  }
  return lines
}

describe('semantic parity vs Flutter ($semantic-parity-replay)', () => {
  it('projects the canonical fixture identically to the committed reference', async () => {
    const frames = loadFixture()
    const bench = await mount()

    // Production order: the surface opens the resident session window first;
    // live frames then own the stream. The fixture's own session-added and
    // subscribed frames ride the replay like any other frame.
    const added = frames.find(f => f.frame.type === 'host/session-added')!
    bench.sinks.onHostEnvelope?.({ rpcId: added.rpcId, payload: added.frame })
    for (let i = 0; i < 12; i++) await Promise.resolve()

    const binding = bench.sessions.binding('s-200' as SessionId)
    if (binding === undefined) throw new Error('s-200 binding missing after session-added')
    // Surface entry point: the runtime owns open() (staging + history
    // backfill); SessionFace intentionally excludes it.
    bench.sessions.open('s-200' as SessionId)
    for (let i = 0; i < 12; i++) await Promise.resolve()

    for (const line of frames) {
      if (line === added) continue
      try {
        if (line.stream === 'mux') {
          bench.sinks.onMuxEnvelope?.({ rpcId: line.rpcId, payload: line.frame })
        } else {
          bench.sinks.onHostEnvelope?.({ rpcId: line.rpcId, payload: line.frame })
        }
      } catch (e) {
        const ev = (line.frame as { event?: { seq?: number; type?: string } }).event
        throw new Error(
          `replay failed at rpcId=${line.rpcId} type=${(line.frame as { type?: string }).type} seq=${ev?.seq} evType=${ev?.type}: ${(e as Error).message}`,
        )
      }
    }
    for (let i = 0; i < 12; i++) await Promise.resolve()

    const projection = project(binding.session.getSnapshot() as unknown as ProjectableSnapshot, 's-200')
    const expected = readFileSync(EXPECTED, 'utf8').trim()
    expect(projection.join('\n')).toBe(expected)
  })

  it('repairs a live seq-gap into the identical converged window', async () => {
    const bench = await mount()
    // History pages return the authoritative window; the live stream will
    // skip seq 3 to force the gap path.
    bench.api.onHistory = () =>
      Promise.resolve(
        ok({
          records: [
            { type: 'turn/start', seq: 1, time: 0, data: { turn: 1 } },
            {
              type: 'user/message', seq: 2, time: 0, surfaceOp: 'append',
              data: { role: 'user', content: [{ type: 'text', text: 'gap' }], source: { kind: 'user' } },
            },
            { type: 'step/start', seq: 3, time: 0, data: { turn: 1, step: 1 } },
            { type: 'assistant/chunk', seq: 4, time: 0, data: { turn: 1, step: 1, chunk: { type: 'text-delta', index: 0, text: 'x' } } },
            {
              type: 'assistant/message', seq: 5, time: 0, surfaceOp: 'append', sourceEventSeqs: [4],
              data: { turn: 1, step: 1, message: { role: 'assistant', content: [{ type: 'text', text: 'x' }] } },
            },
          ].map(event => ({ event })) as never,
          hasMore: false,
        }) as never,
      )

    const added = { rpcId: 'g0', frame: { type: 'host/session-added', sessionId: 's-300', blank: true } }
    bench.sinks.onHostEnvelope?.({ rpcId: 'g0', payload: added.frame })
    for (let i = 0; i < 12; i++) await Promise.resolve()
    const binding = bench.sessions.binding('s-300' as SessionId)!
    bench.sessions.open('s-300' as SessionId)
    for (let i = 0; i < 12; i++) await Promise.resolve()

    const push = (rpcId: string, frame: Record<string, unknown>) =>
      bench.sinks.onMuxEnvelope?.({ rpcId, payload: { sessionId: 's-300', event: frame } })
    push('g1', { type: 'turn/start', seq: 1, time: 0, data: { turn: 1 } })
    push('g2', {
      type: 'user/message', seq: 2, time: 0, surfaceOp: 'append',
      data: { role: 'user', content: [{ type: 'text', text: 'gap' }], source: { kind: 'user' } },
    })
    for (let i = 0; i < 12; i++) await Promise.resolve()
    // Gap: seq 3 missing.
    push('g4', { type: 'assistant/chunk', seq: 4, time: 0, data: { turn: 1, step: 1, chunk: { type: 'text-delta', index: 0, text: 'x' } } })
    push('g5', {
      type: 'assistant/message', seq: 5, time: 0, surfaceOp: 'append', sourceEventSeqs: [4],
      data: { turn: 1, step: 1, message: { role: 'assistant', content: [{ type: 'text', text: 'x' }] } },
    })
    for (let i = 0; i < 30; i++) await Promise.resolve()

    const snap = binding.session.getSnapshot() as unknown as {
      nodes: Array<{ kind: string }>
      turnEnds: ReadonlyMap<number, number>
    }
    const seqs = snap.nodes.map(n => n.kind).join(',')
    expect(seqs).toBe('user,assistant')
    expect(snap.nodes.filter(n => n.kind === 'user')).toHaveLength(1)
  })
})
