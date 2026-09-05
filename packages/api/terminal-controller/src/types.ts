/**
 * Wire-safe request, result, and failure vocabulary for the terminal Remote
 * namespace this package owns. Session views re-export the terminal service's
 * JSON-safe projections, so a Remote consumer reads the very declaration the
 * backend answers.
 */

import type {
  TerminalSessionSnapshot,
  TerminalSignal,
} from '@deepseek-ai/dsh-terminal/types'

export type {
  TerminalReadResult,
  TerminalSendResult,
  TerminalSessionSnapshot,
  TerminalSessionStatus,
  TerminalSignal,
  TerminalSignalResult,
  TerminalWaitReason,
} from '@deepseek-ai/dsh-terminal/types'

declare module '@deepseek-ai/dsh-typert-protocol' {
  interface RemoteErrorDetailsMap {
    /** The session id names no console session, or it closed in between. */
    'terminal/no-session': { readonly sessionId: string }
    /** Another send is already active on the session. */
    'terminal/send-active': { readonly sessionId: string }
    /** The open cannot proceed: no backend for the type, a taken name, or the service is disposing. */
    'terminal/unavailable': { readonly reason: string }
  }
}

/** Console sessions visible to this surface, in publication order. */
export interface TerminalListValue {
  readonly sessions: readonly TerminalSessionSnapshot[]
}

/** Request to open one console session. */
export interface TerminalOpenRequest {
  /** Optional display name, unique within the console surface. */
  name?: string
  /** Optional initial working directory, interpreted by the backend. */
  cwd?: string
  /** Backend type; the first registered backend when absent. */
  type?: string
}

/** Foreground line send into one console session. */
export interface TerminalSendRequest {
  readonly sessionId: string
  /** UTF-8 text to write. */
  readonly text: string
  /** Whether the backend appends its Enter sequence after the text. */
  readonly submit: boolean
}

/** One backward scrollback page from a console session. */
export interface TerminalReadRequest {
  readonly sessionId: string
  /** Offset from the newest retained line; defaults are backend-owned. */
  readonly offset?: number
  /** Requested line count; backend limits still apply. */
  readonly count?: number
}

/** One signal delivered to the session's verified foreground process group. */
export interface TerminalSignalRequest {
  readonly sessionId: string
  readonly signal: TerminalSignal
}

/** Request to close one console session. */
export interface TerminalCloseRequest {
  readonly sessionId: string
}

/** Receipt for one console session close. */
export interface TerminalCloseValue {
  /** True when this call closed the session; false when a close was already in flight. */
  readonly closed: boolean
}
