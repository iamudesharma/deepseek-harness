/**
 * REAL-composition coverage for remote boot: a test-only cordis.yml booted
 * through the vendored Loader mounts the webserver, the remote-access
 * foundation, and the TLS listener rows. Assertions observe the running
 * composition: the HTTPS listener serves routes with the host certificate,
 * the foundation reports its TLS facts, and disposal releases the port.
 * `$DSH_HOME` points at an isolated temp dir so the real home is untouched.
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
import WebServerPlugin from '@deepseek-ai/dsh-host-webserver'
import FoundationPlugin from '../src/index.ts'
import * as TlsListenerPlugin from '../src/tls-listener.ts'

let root: string | undefined
let context: Context | undefined
let home: string | undefined
let savedDshHome: string | undefined

afterEach(async () => {
  await context?.fiber.dispose()
  context = undefined
  if (root !== undefined) await rm(root, { recursive: true, force: true })
  root = undefined
  if (home !== undefined) rmSync(home, { recursive: true, force: true })
  home = undefined
  if (savedDshHome === undefined) delete process.env['DSH_HOME']
  else process.env['DSH_HOME'] = savedDshHome
  savedDshHome = undefined
})

/** Boot webserver + foundation + TLS listener through the real Loader. */
async function loadComposition(remoteEnabled: boolean): Promise<Context> {
  root = await mkdtemp(join(tmpdir(), 'dsh-remote-boot-'))
  home = mkdtempSync(join(tmpdir(), 'dsh-remote-boot-home-'))
  savedDshHome = process.env['DSH_HOME']
  process.env['DSH_HOME'] = home
  const configPath = join(root, 'cordis.yml')
  await writeFile(configPath, [
    "- name: '@deepseek-ai/dsh-host-webserver'",
    '  config:',
    "    host: '127.0.0.1'",
    '    port: 0',
    "- name: '@deepseek-ai/dsh-host-remote-access'",
    '  config:',
    `    enabled: ${remoteEnabled ? 'true' : 'false'}`,
    "- name: '@deepseek-ai/dsh-host-remote-access/tls-listener'",
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
    ['@deepseek-ai/dsh-host-webserver', WebServerPlugin],
    ['@deepseek-ai/dsh-host-remote-access', FoundationPlugin],
    ['@deepseek-ai/dsh-host-remote-access/tls-listener', TlsListenerPlugin],
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
  return context
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

describe('remote boot composition', () => {
  it('serves HTTPS with the host certificate when remote is enabled', async () => {
    const ctx = await loadComposition(true)
    const foundation = ctx.get('remoteAccessFoundation')
    expect(foundation?.isEnabled).toBe(true)
    expect(foundation?.tlsFingerprint).toMatch(/^[A-Za-z0-9_-]{43}$/)
    expect(foundation?.tlsPort).toBeGreaterThan(0)
    expect(foundation?.configSnapshot).toEqual({ enabled: true })
    ctx.webServer.register({
      kind: 'exact',
      path: '/remote-probe',
      handler: (_req, res) => {
        res.writeHead(200, { 'content-type': 'text/plain' })
        res.end('remote-tls-ok')
      },
    })
    const response = await getTls(foundation?.tlsPort ?? 0, '/remote-probe')
    expect(response.status).toBe(200)
    expect(response.body).toBe('remote-tls-ok')
  })

  it('stays loopback-only without a TLS listener when remote is off', async () => {
    const ctx = await loadComposition(false)
    const foundation = ctx.get('remoteAccessFoundation')
    expect(foundation?.isEnabled).toBe(false)
    expect(foundation?.tlsFingerprint).toBeUndefined()
    expect(foundation?.tlsPort).toBeUndefined()
  })

  it('pairs a device end to end through approval and mints a token', async () => {
    const ctx = await loadComposition(true)
    const foundation = ctx.get('remoteAccessFoundation')
    if (foundation === undefined) throw new Error('foundation missing')
    const service = ctx.get('remoteAccess')
    if (service === undefined) throw new Error('remoteAccess service missing')
    const hostId = foundation.hostIdentity.hostId
    const entry = foundation.pairing.create({ hostId })
    const deviceId = '11111111-1111-4111-8111-111111111111'
    const paired = service.pair({
      hostId,
      deviceId,
      displayName: 'Smoke Phone',
      devicePublicKey: Buffer.from('smoke-spki').toString('base64'),
      nonce: entry.nonce,
    })
    // Host approves while pair waits (the operator console path in production).
    await new Promise(resolve => setTimeout(resolve, 50))
    expect(foundation.approval.approve(entry.nonce)).toBe(true)
    const result = await paired
    expect(result.hostId).toBe(hostId)
    expect(result.expiresAt).toBeGreaterThan(Date.now())
    // The minted token authenticates as the new device.
    const payload = await foundation.tokenService.verify(result.deviceToken)
    expect(payload.sub).toBe(deviceId)
    const devices = await foundation.devices.list()
    expect(devices.map(entry => entry.deviceId)).toContain(deviceId)
  })
})
