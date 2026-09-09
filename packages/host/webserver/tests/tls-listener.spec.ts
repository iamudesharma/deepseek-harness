/**
 * REAL-composition coverage for the remote TLS listener: a test-only
 * cordis.yml booted through the vendored Loader mounts the webserver row,
 * then `listenTls` serves the same registered routes over HTTPS with the
 * production host certificate material (`ensureHostCertificate`).
 */

import { mkdtempSync, rmSync } from 'node:fs'
import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { get as httpsGet } from 'node:https'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { afterEach, describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import Loader from '@deepseek-ai/cordis-plugin-loader'
import Include from '@deepseek-ai/cordis-plugin-include'
import HttpServer from '../src/index.ts'
import {
  ensureHostCertificate,
  loadOrCreateHostIdentity,
} from '@deepseek-ai/dsh-host-remote-access'

let root: string | undefined
let context: Context | undefined
const homes: string[] = []

afterEach(async () => {
  await context?.fiber.dispose()
  context = undefined
  if (root !== undefined) await rm(root, { recursive: true, force: true })
  root = undefined
  for (const home of homes.splice(0)) rmSync(home, { recursive: true, force: true })
})

/** Boot one webserver row through the real Loader. */
async function loadComposition(): Promise<{ ctx: Context; port: number }> {
  root = await mkdtemp(join(tmpdir(), 'dsh-webserver-tls-'))
  const configPath = join(root, 'cordis.yml')
  await writeFile(configPath, [
    "- name: '@deepseek-ai/dsh-host-webserver'",
    '  config:',
    "    host: '127.0.0.1'",
    '    port: 0',
    '',
  ].join('\n'))

  context = new Context()
  context.baseUrl = pathToFileURL(root).href + '/'
  await context.plugin(Loader)
  context.loader.builtins.include = Include
  const modules = new Map<string, unknown>([
    ['@deepseek-ai/dsh-host-webserver', HttpServer],
  ])
  context.loader.internal = {
    version: 'v2',
    async import(specifier: string) {
      if (!modules.has(specifier)) throw new Error(`unexpected Loader import: ${specifier}`)
      return modules.get(specifier)
    },
  } as unknown as NonNullable<typeof context.loader.internal>
  await context.loader.create({
    name: 'cordis:include',
    config: { path: pathToFileURL(configPath).href },
  })
  await context.loader.await()
  const port = context.webServer.port
  expect(port).toBeGreaterThan(0)
  return { ctx: context, port }
}

/** Production certificate material in an isolated home. */
async function certMaterial(): Promise<{ certPem: string; keyPem: string }> {
  const home = mkdtempSync(join(tmpdir(), 'dsh-webserver-tls-home-'))
  homes.push(home)
  const identity = await loadOrCreateHostIdentity({ dshHome: home })
  const { certPem, keyPem } = await ensureHostCertificate(identity.hostId, home)
  return { certPem, keyPem }
}

/** GET one path over TLS without trusting the self-signed chain. */
function getTls(port: number, path: string): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const req = httpsGet(
      { host: '127.0.0.1', port, path, rejectUnauthorized: false },
      (res) => {
        let body = ''
        res.on('data', (chunk: unknown) => { body += String(chunk) })
        res.on('end', () => { resolve({ status: res.statusCode ?? 0, body }) })
      },
    )
    req.on('error', reject)
    req.end()
  })
}

describe('webserver TLS listener', () => {
  it('serves registered routes over HTTPS and stops cleanly', async () => {
    const { ctx } = await loadComposition()
    ctx.webServer.register({
      kind: 'exact',
      path: '/tls-probe',
      handler: (_req, res) => {
        res.writeHead(200, { 'content-type': 'text/plain' })
        res.end('tls-ok')
      },
    })
    const { certPem, keyPem } = await certMaterial()
    const listener = await ctx.webServer.listenTls({
      certPem,
      keyPem,
      host: '127.0.0.1',
      port: 0,
    })
    try {
      expect(listener.port).toBeGreaterThan(0)
      const response = await getTls(listener.port, '/tls-probe')
      expect(response.status).toBe(200)
      expect(response.body).toBe('tls-ok')
      const missing = await getTls(listener.port, '/nope')
      expect(missing.status).toBe(404)
    } finally {
      await listener.stop()
    }
  })

  it('rejects invalid certificate material without binding', async () => {
    const { ctx } = await loadComposition()
    await expect(ctx.webServer.listenTls({
      certPem: 'not-a-cert',
      keyPem: 'not-a-key',
      host: '127.0.0.1',
      port: 0,
    })).rejects.toThrow('webserver: invalid TLS certificate material')
  })

  it('a second listener on the same port fails to bind', async () => {
    const { ctx } = await loadComposition()
    const { certPem, keyPem } = await certMaterial()
    const first = await ctx.webServer.listenTls({
      certPem,
      keyPem,
      host: '127.0.0.1',
      port: 0,
    })
    try {
      await expect(ctx.webServer.listenTls({
        certPem,
        keyPem,
        host: '127.0.0.1',
        port: first.port,
      })).rejects.toThrow()
    } finally {
      await first.stop()
    }
  })
})
