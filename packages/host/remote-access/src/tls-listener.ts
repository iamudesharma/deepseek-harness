/**
 * Remote TLS listener plugin: serves the composed routes over HTTPS when
 * remote access is enabled, so phones on the LAN reach `remote.*` and the
 * multiplex without trusting plaintext. Dormant when remote access is off —
 * the plaintext loopback listener is untouched.
 *
 * @module @deepseek-ai/dsh-host-remote-access/tls-listener
 */

import type { Context } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-host-webserver'
import z from '@deepseek-ai/schemastery'

/** Stable Cordis plugin name. */
export const name = 'remote-tls-listener'

/** Services required before the listener can bind (ordering only). */
export const inject = ['webServer', 'remoteAccessFoundation']

/** Plugin config: bind host and port for the HTTPS listener. */
export interface Config {
  /** Bind host literal; all-interfaces serves LAN clients. */
  host: '127.0.0.1' | '0.0.0.0'
  /** Listen port; zero requests an OS-assigned port. */
  port: number
}

export const Config: z<Config> = z.object({
  host: z.union([z.const('127.0.0.1'), z.const('0.0.0.0')]).default('0.0.0.0'),
  port: z.natural().max(65535).default(3443),
})

/**
 * Bind the HTTPS listener when remote access is enabled.
 * @param ctx - plugin context carrying the web server and foundation.
 * @param config - validated bind host and port.
 * @returns the disposer stopping the listener.
 */
export async function apply(ctx: Context, config: Config): Promise<() => Promise<void>> {
  const foundation = ctx.remoteAccessFoundation
  if (!foundation.isEnabled) return async () => {}
  const { certPem, keyPem } = await foundation.tlsMaterial()
  const listener = await ctx.webServer.listenTls({
    certPem,
    keyPem,
    host: config.host,
    port: config.port,
  })
  foundation.tlsPort = listener.port
  ctx.logger.info(
    `remote-access: TLS listening on https://${config.host}:${String(listener.port)}`,
  )
  return () => listener.stop()
}
