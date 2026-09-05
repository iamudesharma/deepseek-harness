/** Host terminal console Remote owner: console sessions over Typert Remote. */

import type { Context } from '@deepseek-ai/cordis'
import { Remote, RemoteError, TypertRemoteService, remoteErrorOf } from '@deepseek-ai/dsh-typert-protocol'
import { TerminalError, TerminalSessionId } from '@deepseek-ai/dsh-terminal'
import type {
  ConsoleTerminalOwner,
  TerminalReadResult,
  TerminalSendResult,
  TerminalSignalResult,
  TerminalSpawnResult,
} from '@deepseek-ai/dsh-terminal/types'
import type { TerminalSessionService } from '@deepseek-ai/dsh-terminal'
import type {
  TerminalCloseRequest,
  TerminalCloseValue,
  TerminalListValue,
  TerminalOpenRequest,
  TerminalReadRequest,
  TerminalSendRequest,
  TerminalSignalRequest,
} from './types.ts'

export type * from './types.ts'

declare module '@deepseek-ai/cordis' {
  interface Context {
    /** Host terminal console API and Remote namespace owner. */
    terminalController: TerminalController
  }
}

/** The single console principal whose sessions this namespace serves. */
const CONSOLE_OWNER_ID = 'console'

/**
 * Host service backing the generated `ctx.remote.terminal` namespace. Every
 * verb operates the same console principal — one owner per host whose
 * sessions no agent or model can see — so the console pool is exactly the
 * exact-owner fenced pool `ctx.terminals` already guarantees. The PTY service
 * is optional: a composition without it still boots, and every verb answers
 * `terminal/unavailable` (the settingsController absent-provider pattern).
 */
export class TerminalController extends TypertRemoteService {
  static inject = ['typert']

  private readonly consoleOwner: ConsoleTerminalOwner

  /** @param ctx - Host context, with the PTY service when composed. */
  constructor(ctx: Context) {
    super(ctx, 'terminalController', { namespace: 'terminal' })
    // The principal's effect scope is a child plugin of this service's fiber:
    // its disposal ends the principal, and the PTY service tears the console
    // sessions down during that scope's unwind.
    const scope = ctx.plugin(() => {})
    this.consoleOwner = { kind: 'console', id: CONSOLE_OWNER_ID, ctx: scope.ctx }
    ctx.effect(() => () => scope.dispose(), 'terminal-controller: console principal scope')
  }

  /** The PTY service, or a terminal/unavailable refusal when unmounted. */
  private get terminals(): TerminalSessionService {
    const terminals = this.ctx.get('terminals')
    if (terminals === undefined) {
      throw new RemoteError('terminal/unavailable', 'no terminal service is mounted', { reason: 'no terminal service is mounted' })
    }
    return terminals
  }

  /**
   * List the console principal's live sessions.
   * @returns console sessions in publication order.
   */
  @Remote('list')
  async list(): Promise<TerminalListValue> {
    return { sessions: this.terminals.list(this.consoleOwner) }
  }

  /**
   * Open one console session through a registered backend.
   * @param request - optional name, cwd, and backend type.
   * @returns the published session identity, metadata, status, and MOTD.
   */
  @Remote('open')
  async open(request: TerminalOpenRequest): Promise<TerminalSpawnResult> {
    const type = this.resolveBackendType(request.type)
    try {
      return await this.terminals.spawn(this.consoleOwner, {
        type,
        ...request.name !== undefined ? { name: request.name } : {},
        ...request.cwd !== undefined ? { cwd: request.cwd } : {},
      })
    } catch (error) {
      throw this.asRemoteError(error, request.name)
    }
  }

  /**
   * Write one line into the session and wait for readiness.
   * @param request - session id, text, and submit behavior.
   * @returns the bounded viewport, wait reason, and session status.
   */
  @Remote('send')
  async send(request: TerminalSendRequest): Promise<TerminalSendResult> {
    let operation: ReturnType<typeof this.terminals.startSend>
    try {
      operation = this.terminals.startSend(
        this.consoleOwner,
        TerminalSessionId(request.sessionId),
        { text: request.text, submit: request.submit },
      )
    } catch (error) {
      throw this.asRemoteError(error, request.sessionId)
    }
    try {
      return await operation.done
    } catch (error) {
      throw this.asRemoteError(error, request.sessionId)
    }
  }

  /**
   * Read one bounded scrollback page from a console session.
   * @param request - session id with optional offset and count.
   * @returns the retained text page and pagination metadata.
   */
  @Remote('read')
  async read(request: TerminalReadRequest): Promise<TerminalReadResult> {
    try {
      return this.terminals.read(this.consoleOwner, TerminalSessionId(request.sessionId), {
        ...request.offset !== undefined ? { offset: request.offset } : {},
        ...request.count !== undefined ? { count: request.count } : {},
      })
    } catch (error) {
      throw this.asRemoteError(error, request.sessionId)
    }
  }

  /**
   * Deliver one allowed signal to the session's foreground process group.
   * @param request - session id and the signal name.
   * @returns the delivered process-group identity.
   */
  @Remote('signal')
  async signal(request: TerminalSignalRequest): Promise<TerminalSignalResult> {
    try {
      return await this.terminals.signal(this.consoleOwner, TerminalSessionId(request.sessionId), request.signal)
    } catch (error) {
      throw this.asRemoteError(error, request.sessionId)
    }
  }

  /**
   * Close one console session and wait for its process tree to quiesce.
   * @param request - session id to close.
   * @returns whether this call performed the close.
   */
  @Remote('close')
  async close(request: TerminalCloseRequest): Promise<TerminalCloseValue> {
    try {
      return { closed: await this.terminals.kill(this.consoleOwner, TerminalSessionId(request.sessionId), 'console request') }
    } catch (error) {
      throw this.asRemoteError(error, request.sessionId)
    }
  }

  /** The first registered backend type, or an explicit rejection when none is mounted. */
  private resolveBackendType(requested: string | undefined): string {
    if (requested !== undefined) {
      if (requested.length === 0) {
        throw new RemoteError('terminal/unavailable', 'terminal backend type must be non-empty', { reason: 'backend type must be non-empty' })
      }
      return requested
    }
    const [first] = this.terminals.listBackends()
    if (first === undefined) {
      throw new RemoteError('terminal/unavailable', 'no terminal backend is mounted', { reason: 'no backend is mounted' })
    }
    return first
  }

  /** Map PTY service failures onto stable Remote codes; foreign failures pass through. */
  private asRemoteError(error: unknown, sessionId: string | undefined): unknown {
    if (remoteErrorOf(error) !== undefined) throw error
    if (error instanceof TerminalError) {
      if (error.code === 'NO_SESSION' && sessionId !== undefined) {
        throw new RemoteError('terminal/no-session', error.message, { sessionId }, { cause: error })
      }
      if (error.code === 'SEND_ACTIVE' && sessionId !== undefined) {
        throw new RemoteError('terminal/send-active', error.message, { sessionId }, { cause: error })
      }
      throw new RemoteError('terminal/unavailable', error.message, { reason: error.message }, { cause: error })
    }
    return error
  }
}

export default TerminalController
