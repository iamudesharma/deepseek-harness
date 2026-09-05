import { afterEach, describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import { RemoteError, remoteErrorOf, remoteMethods } from '@deepseek-ai/dsh-typert-protocol'
import TerminalSessionService from '@deepseek-ai/dsh-terminal'
import type {
  TerminalBackendSession,
  TerminalReadRequest,
  TerminalSendOperation,
  TerminalSendRequest,
  TerminalSessionStatus,
  TerminalSignal,
} from '@deepseek-ai/dsh-terminal'
import TerminalController from '../src/index.ts'

const roots: Context[] = []

afterEach(async () => {
  await Promise.all(roots.splice(0).map(ctx => ctx.fiber.dispose()))
})

class StubSession implements TerminalBackendSession {
  readonly motd = 'stub ready'
  readonly pid = 42
  closed: string[] = []
  statusValue: TerminalSessionStatus = { kind: 'running' }
  sent: TerminalSendRequest[] = []

  startSend(request: TerminalSendRequest): TerminalSendOperation {
    this.sent.push(request)
    return {
      done: Promise.resolve({
        viewport: `ran:${request.text}`,
        waitReason: 'stdin_read' as const,
        sessionStatus: this.statusValue,
        truncated: false,
      }),
      readOutput: () => ({ delta: '', truncated: false }),
      cancel: () => false,
    }
  }

  read(request: TerminalReadRequest) {
    return { text: `page:${request.offset ?? 'none'}:${request.count ?? 'none'}`, totalLines: 3, lineBegin: 0, lineEnd: 1, truncated: false }
  }

  async signal(signal: TerminalSignal) {
    return { delivered: true as const, targetPgid: signal === 'SIGINT' ? 7 : 8 }
  }

  status(): TerminalSessionStatus {
    return this.statusValue
  }

  async close(reason: string): Promise<void> {
    this.closed.push(reason)
  }
}

async function harness(): Promise<Context> {
  const ctx = new Context()
  roots.push(ctx)
  // No agent registry is mounted on purpose: the console surface must not
  // depend on one, and every console principal is live without it.
  await ctx.plugin(TerminalSessionService)
  ctx.provide('typert', {
    lookups: { configure: () => () => {} },
    contexts: { configureHost: () => () => {} },
  } as never)
  await ctx.plugin(TerminalController)
  return ctx
}

describe('the terminal Remote namespace a console panel calls', () => {
  it('publishes the terminal namespace from its own service key', async () => {
    const ctx = await harness()
    expect(ctx.terminalController.typertRemote.serviceKey).toBe('terminalController')
    expect(ctx.terminalController.typertRemote.namespace).toBe('terminal')
    expect(remoteMethods(ctx.terminalController)).toEqual([
      { method: 'list', invocation: { kind: 'direct' } },
      { method: 'open', invocation: { kind: 'direct' } },
      { method: 'send', invocation: { kind: 'direct' } },
      { method: 'read', invocation: { kind: 'direct' } },
      { method: 'signal', invocation: { kind: 'direct' } },
      { method: 'close', invocation: { kind: 'direct' } },
    ])
  })

  it('opens, lists, reads, sends, signals, and closes a console session', async () => {
    const ctx = await harness()
    const session = new StubSession()
    ctx.terminals.registerBackend({ type: 'stub', spawn: () => Promise.resolve(session) })

    const opened = await ctx.terminalController.open({})
    // An absent type resolves to the first registered backend, explicitly.
    expect(opened).toMatchObject({ sessionId: 'pty-1', type: 'stub', pid: 42, motd: 'stub ready' })

    expect(await ctx.terminalController.list()).toMatchObject({ sessions: [{ sessionId: 'pty-1' }] })

    expect(await ctx.terminalController.read({ sessionId: opened.sessionId, count: 2 })).toMatchObject({
      text: 'page:none:2',
      totalLines: 3,
    })

    const sent = await ctx.terminalController.send({ sessionId: opened.sessionId, text: 'echo hi', submit: true })
    expect(sent).toMatchObject({ viewport: 'ran:echo hi', waitReason: 'stdin_read' })
    expect(session.sent[0]).toMatchObject({ text: 'echo hi', submit: true })

    expect(await ctx.terminalController.signal({ sessionId: opened.sessionId, signal: 'SIGINT' })).toEqual({
      delivered: true,
      targetPgid: 7,
    })

    expect(await ctx.terminalController.close({ sessionId: opened.sessionId })).toEqual({ closed: true })
    expect(session.closed).toEqual(['console request'])
  })

  it('fails closed with stable codes for unknown sessions', async () => {
    const ctx = await harness()
    ctx.terminals.registerBackend({ type: 'stub', spawn: () => Promise.resolve(new StubSession()) })

    const missingRead = await ctx.terminalController.read({ sessionId: 'pty-9' }).catch((error: unknown) => error)
    expect(remoteErrorOf(missingRead)).toMatchObject({ code: 'terminal/no-session', details: { sessionId: 'pty-9' } })

    const missingSend = await ctx.terminalController.send({ sessionId: 'pty-9', text: 'x', submit: false }).catch((error: unknown) => error)
    expect(remoteErrorOf(missingSend)).toMatchObject({ code: 'terminal/no-session', details: { sessionId: 'pty-9' } })

    const missingClose = await ctx.terminalController.close({ sessionId: 'pty-9' }).catch((error: unknown) => error)
    expect(remoteErrorOf(missingClose)).toMatchObject({ code: 'terminal/no-session', details: { sessionId: 'pty-9' } })

    const unknownType = await ctx.terminalController.open({ type: 'nope' }).catch((error: unknown) => error)
    expect(remoteErrorOf(unknownType)).toMatchObject({ code: 'terminal/unavailable' })
  })

  it('reports an explicit unavailable failure while no backend is mounted', async () => {
    const ctx = await harness()
    const absent = await ctx.terminalController.open({}).catch((error: unknown) => error)
    expect(remoteErrorOf(absent)).toMatchObject({
      code: 'terminal/unavailable',
      message: 'no terminal backend is mounted',
    })
  })

  it('rejects a duplicate console name and a duplicate open as unavailable', async () => {
    const ctx = await harness()
    ctx.terminals.registerBackend({ type: 'stub', spawn: () => Promise.resolve(new StubSession()) })
    await ctx.terminalController.open({ name: 'panel' })
    const duplicate = await ctx.terminalController.open({ name: 'panel' }).catch((error: unknown) => error)
    expect(remoteErrorOf(duplicate)).toMatchObject({ code: 'terminal/unavailable' })
    expect(remoteErrorOf(duplicate)).toBeInstanceOf(RemoteError)
  })

  it('tears console sessions down with the owning scope', async () => {
    const ctx = await harness()
    const session = new StubSession()
    ctx.terminals.registerBackend({ type: 'stub', spawn: () => Promise.resolve(session) })
    await ctx.terminalController.open({})
    await ctx.fiber.dispose()
    roots.length = 0

    // Teardown may arrive through either owner: the console principal's scope
    // unwind or the PTY service's global disposal, whichever runs first.
    expect(session.closed).toHaveLength(1)
    expect(session.closed[0]).toMatch(/^PTY (owner|service) disposed$/)
  })
})
