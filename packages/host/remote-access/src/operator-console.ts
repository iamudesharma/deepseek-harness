/**
 * Remote operator console: TTY-only stdin commands for the pairing ceremony
 * plus the boot-time QR display. The pairing approval store is in-process
 * memory, so approval lives in the running process — a second CLI process
 * could never reach it. Non-TTY hosts (daemons, supervisors, tests) stay
 * dormant; pairing then proceeds through the log line plus `pending`.
 *
 * @module @deepseek-ai/dsh-host-remote-access/operator-console
 */

import type { Context } from '@deepseek-ai/cordis'
import { createInterface, type Interface as Readline } from 'node:readline'
import z from '@deepseek-ai/schemastery'
import { toString as renderQr } from 'qrcode'
import { issuePairingQr, type IssuedPairingQr } from './pairing-qr.ts'
import type { RemoteAccessFoundation } from './index.ts'

/** Stable Cordis plugin name. */
export const name = 'remote-operator-console'

/** Services required before the console can start (ordering only). */
export const inject = ['remoteAccessFoundation']

/** Plugin config: console master switch plus ceremony PIN policy. */
export interface Config {
  /** Whether the console is active (the bundle wires `--remote` here). */
  enabled?: boolean
  /**
   * Mint a 6-digit PIN on `qr` ceremonies; the QR carries it, so scanning
   * stays frictionless. Off by default: approval plus the unguessable nonce
   * already bind the ceremony.
   */
  withPin?: boolean
}

export const Config: z<Config> = z.object({
  enabled: z.boolean().default(false),
  withPin: z.boolean().default(false),
})

/** Live dependencies of one console; streams are injectable for tests. */
export interface OperatorConsoleDeps {
  /** Remote-access foundation (pairing, approval, devices, identity). */
  foundation: RemoteAccessFoundation
  /** Bind-dependent LAN addresses when the web runtime already provided them. */
  webRuntime?: { lanAddresses?: readonly string[] }
  /** Command source (production: process.stdin). */
  input: NodeJS.ReadableStream
  /** Display sink (production: process.stdout). */
  output: NodeJS.WritableStream
  /** Whether ceremonies mint a PIN. */
  withPin: boolean
  /** Clock, defaults to `Date.now`. */
  now?: () => number
}

/** Interactive console: boot display plus the command loop. */
export interface OperatorConsole {
  /** Issue a fresh ceremony and print the QR plus manual values. */
  printBootBlock(): Promise<void>
  /** Close the readline interface and release the streams. */
  close(): void
}

/** Short nonce rendering for operator typing (first 8 chars). */
function shortNonce(nonce: string): string {
  return nonce.slice(0, 8)
}

/**
 * Render an unknown failure without leaking tokens or stack traces.
 * @param error - rejection value from a device or store call.
 * @returns the short message for operator display.
 */
export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

/**
 * Create an interactive console over explicit streams. Production wires
 * process.stdin/stdout through `startOperatorConsole`; tests pass memory
 * streams here directly.
 * @param deps - foundation, optional web runtime, streams, and policy.
 * @returns the console handle.
 */
export function createOperatorConsole(deps: OperatorConsoleDeps): OperatorConsole {
  const { foundation, input, output } = deps
  const now = deps.now ?? Date.now
  const write = (line: string): void => {
    output.write(`${line}\n`)
  }

  const baseUri = (): { uri: string } | { unavailable: string } => {
    if (foundation.tlsPort === undefined) {
      return { unavailable: 'remote TLS listener is not up — pairing cannot complete' }
    }
    const lan = deps.webRuntime?.lanAddresses?.[0]
    return { uri: `https://${lan ?? '127.0.0.1'}:${String(foundation.tlsPort)}` }
  }

  const printIssued = async (issued: IssuedPairingQr): Promise<void> => {
    const ascii = await renderQr(issued.uri, { type: 'terminal', small: true })
    write('dsh remote: scan to pair')
    write(ascii)
    write('or enter manually:')
    write(`  URL: ${issued.payload.baseUri}`)
    write(`  Host ID: ${issued.payload.hostId}`)
    write(`  Public key: ${issued.payload.hostPublicKey}`)
    write(`  Nonce: ${issued.payload.nonce}`)
    if (issued.payload.pin !== undefined) write(`  PIN: ${issued.payload.pin}`)
    write(`  Expires: ${new Date(issued.payload.exp).toISOString()}`)
    write(`approve with: approve ${shortNonce(issued.payload.nonce)}… (prefix ok)`)
  }

  const issue = (): IssuedPairingQr => {
    const base = baseUri()
    if ('unavailable' in base) throw new Error(`remote-access: ${base.unavailable}`)
    return issuePairingQr(foundation.pairing, {
      baseUri: base.uri,
      hostId: foundation.hostIdentity.hostId,
      hostPublicKey: foundation.hostIdentity.publicKeyDer.toString('base64'),
      withPin: deps.withPin,
      ...(foundation.tlsFingerprint === undefined ? {} : { certFp: foundation.tlsFingerprint }),
      now,
    })
  }

  const resolveNonce = (arg: string): { nonce: string } | { message: string } => {
    const pending = foundation.approval.list()
    const exact = pending.find(entry => entry.nonce === arg)
    if (exact !== undefined) return { nonce: exact.nonce }
    let match: { readonly nonce: string } | undefined
    for (const entry of pending) {
      if (!entry.nonce.startsWith(arg)) continue
      if (match !== undefined) {
        return { message: `several pending pairings match ${JSON.stringify(arg)} — type more characters` }
      }
      match = entry
    }
    if (match === undefined) return { message: `no pending pairing matches ${JSON.stringify(arg)}` }
    return { nonce: match.nonce }
  }

  const printPending = (): void => {
    const pending = foundation.approval.list()
    if (pending.length === 0) {
      write('no pending pairings')
      return
    }
    for (const entry of pending) {
      write(`- "${entry.request.displayName}" ${entry.request.deviceId} nonce ${shortNonce(entry.nonce)}…`)
    }
  }

  const printDevices = (): void => {
    foundation.devices.list().then((all) => {
      if (all.length === 0) {
        write('no paired devices')
        return
      }
      for (const device of all) {
        write(`- "${device.displayName}" ${device.deviceId}${device.revoked ? ' revoked' : ''}`)
      }
    }, (error: unknown) => {
      write(`devices failed: ${errorMessage(error)}`)
    })
  }

  const handle = (line: string): void => {
    // split on a trimmed line always yields a non-empty head; only the tail
    // may be absent, and elements are never empty strings.
    const [command, arg] = line.trim().split(/\s+/, 2) as [string, string?]
    if (command === '') return
    if (command === 'help') {
      write('commands: qr | approve <nonce> | deny <nonce> | pending | devices | help')
      return
    }
    if (command === 'qr') {
      void (async (): Promise<void> => {
        try {
          await printIssued(issue())
        } catch (error) {
          write(`qr failed: ${errorMessage(error)}`)
        }
      })()
      return
    }
    if (command === 'pending') {
      printPending()
      return
    }
    if (command === 'devices') {
      printDevices()
      return
    }
    if (command === 'approve' || command === 'deny') {
      if (arg === undefined) {
        write(`usage: ${command} <nonce>`)
        return
      }
      const resolved = resolveNonce(arg)
      if ('message' in resolved) {
        write(resolved.message)
        return
      }
      // Presence was just verified synchronously above, so the decision
      // always lands; a missing entry can only mean it was never pending.
      if (command === 'approve') foundation.approval.approve(resolved.nonce)
      else foundation.approval.deny(resolved.nonce)
      write(`${command === 'approve' ? 'approved' : 'denied'} ${shortNonce(resolved.nonce)}…`)
      return
    }
    write(`unknown command ${JSON.stringify(command)} — type help`)
  }

  const rl: Readline = createInterface({ input, output, prompt: 'dsh-remote> ' })
  rl.on('line', (line: string) => {
    handle(line)
    rl.prompt()
  })
  rl.prompt()

  return {
    async printBootBlock(): Promise<void> {
      try {
        await printIssued(issue())
      } catch (error) {
        write(`dsh remote: ${errorMessage(error)}`)
      }
    },
    close(): void {
      rl.close()
    },
  }
}

/** Explicit-deps entry point: start shared by `apply` and composition tests. */
export interface StartOperatorConsoleDeps {
  /** Logger for dormant-mode diagnostics. */
  logger: { info(message: string): void }
  /** Loader readiness when booted through a Loader; absent in hand-built trees. */
  loader?: { await(): Promise<unknown> }
  /** Whether stdin is a TTY (production reads `process.stdin.isTTY`). */
  interactive: boolean
  /** Console factory inputs minus the policy already resolved by the caller. */
  console: OperatorConsoleDeps
}

/**
 * Start the console unless headless: print the boot block once settled and
 * run the command loop. Split from `apply` so composition tests drive the
 * lifecycle without process globals.
 * @param deps - logger, loader, TTY flag, and console inputs.
 * @returns the disposer closing the console, or a no-op when dormant.
 */
export function startOperatorConsole(deps: StartOperatorConsoleDeps): () => void {
  if (!deps.interactive) {
    deps.logger.info('remote-access: operator console dormant (no TTY)')
    return () => {}
  }
  const console = createOperatorConsole(deps.console)
  // The TLS port and LAN addresses resolve during activation; print once the
  // Loader tree settles like the URL line does. A hand-built tree without a
  // Loader prints at once.
  if (deps.loader === undefined) void console.printBootBlock()
  else void deps.loader.await().then(() => console.printBootBlock(), () => {})
  return () => { console.close() }
}

/**
 * Mount the operator console when enabled and attached to a TTY.
 * @param ctx - plugin context carrying the foundation.
 * @param config - validated console switch and PIN policy; absent in hand-built trees.
 * @returns the disposer closing the console.
 */
export function apply(ctx: Context, config?: Config): () => void {
  // The Loader resolves schema defaults; hand-built test contexts may pass none.
  if (config?.enabled !== true) return () => {}
  const foundation = ctx.remoteAccessFoundation
  if (!foundation.isEnabled) return () => {}
  const webRuntime = (ctx as unknown as { get(name: string): unknown }).get('webRuntime') as
    | { lanAddresses?: readonly string[] }
    | undefined
  const loader = ctx.get('loader') as { await(): Promise<unknown> } | undefined
  return startOperatorConsole({
    logger: ctx.logger,
    ...(loader === undefined ? {} : { loader }),
    // isTTY is undefined when piped, which is falsy: non-TTY stays dormant.
    interactive: process.stdin.isTTY,
    console: {
      foundation,
      webRuntime: webRuntime ?? {},
      input: process.stdin,
      output: process.stdout,
      withPin: config.withPin ?? true,
    },
  })
}
