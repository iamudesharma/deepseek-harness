/**
 * Package-owned invariant companion for `@deepseek-ai/dsh-host-remote-access`.
 * @module @deepseek-ai/dsh-host-remote-access/invariant
 */

/* jscpd:ignore-start */
import type { Context } from '@deepseek-ai/cordis'
import type { InvariantInstaller } from '@deepseek-ai/dsh-invariants'

const PACKAGE_NAME = '@deepseek-ai/dsh-host-remote-access'

/** Cordis companion plugin name. */
export const name = 'host-remote-access-invariant'
/** Service required before the companion can reserve package ownership. */
export const inject = ['invariants']

/**
 * No runtime invariant: Phase 1 owns durable host-identity and device
 * files plus an in-memory pairing store, but has no independent event stream
 * or mutable relation for a companion to compare without creating identities.
 */
const install: InvariantInstaller = () => {}

/**
 * Register this package's invariant companion.
 * @param ctx - Cordis context carrying the invariant service.
 * @returns the installed registration's disposer after setup succeeds.
 */
export const apply = (ctx: Context): Promise<() => void> =>
  Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install))
/* jscpd:ignore-end */
