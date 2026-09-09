/** Mux upgrade authorization: ticket fallback behind the browser fence. */
import { createServer, connect } from 'node:net'
import type { AddressInfo } from 'node:net'
import type { IncomingMessage } from 'node:http'
import { PassThrough } from 'node:stream'
import { once } from 'node:events'
import { Context } from '@deepseek-ai/cordis'
import { describe, expect, it } from 'vitest'
import { apply as applyConnection, inject as connectionInject } from '@deepseek-ai/dsh-client-connection'
import type { WebServer, WebRoute, WebUpgradeRoute } from '@deepseek-ai/dsh-host-webserver'
import type { RemoteAccessFoundation } from '@deepseek-ai/dsh-host-remote-access'
import TypertRegistry from '@deepseek-ai/dsh-typert-registry'
import TypertGatewayService from '@deepseek-ai/dsh-api-gateway'
import { provideBrowserCredentials } from './browser-credentials.ts'

/** webServer fake capturing upgrade routes for direct handler drives. */
function fakeHttpServer(upgrades: WebUpgradeRoute[]): Pick<WebServer, 'register' | 'registerUpgrade' | 'tapIndex' | 'port'> {
  const routes: WebRoute[] = []
  return {
    register(route) {
      routes.push(route)
      return () => { routes.splice(routes.indexOf(route), 1) }
    },
    registerUpgrade(route) {
      upgrades.push(route)
      return () => { upgrades.splice(upgrades.indexOf(route), 1) }
    },
    tapIndex: () => () => {},
    port: 0,
  }
}

/** Stub foundation answering a canned mux decision. */
function stubFoundation(
  decide: (url: string | undefined) => Promise<'proceed' | 'forbidden' | 'unauthenticated'>,
): { stub: RemoteAccessFoundation; seen: (string | undefined)[] } {
  const seen: (string | undefined)[] = []
  const stub = {
    authorizeMuxUpgrade: async (url: string | undefined) => {
      seen.push(url)
      return decide(url)
    },
  } as unknown as RemoteAccessFoundation
  return { stub, seen }
}

/** Boot connection + registry + gateway with an optional stub foundation. */
async function mounted(stub?: RemoteAccessFoundation): Promise<{
  upgrades: WebUpgradeRoute[]
  dispose: () => Promise<void>
}> {
  const ctx = new Context()
  const upgrades: WebUpgradeRoute[] = []
  provideBrowserCredentials(ctx)
  ctx.provide('webServer', fakeHttpServer(upgrades) as WebServer)
  if (stub !== undefined) ctx.provide('remoteAccessFoundation', stub)
  await ctx.plugin(TypertRegistry)
  const connectionFiber = ctx.plugin({ inject: [...connectionInject], apply: applyConnection })
  await connectionFiber
  const gatewayFiber = ctx.plugin(TypertGatewayService)
  await gatewayFiber
  expect(upgrades).toHaveLength(1)
  return {
    upgrades,
    dispose: async () => {
      await gatewayFiber.dispose()
      await connectionFiber.dispose()
    },
  }
}

/** Fake upgrade request without a browser cookie (loopback host passes the fence). */
function fakeUpgradeRequest(url: string): IncomingMessage {
  return { headers: { host: '127.0.0.1' }, url } as unknown as IncomingMessage
}

/** Collect one socket.end payload from a memory socket. */
async function rejectedStatus(
  upgrades: WebUpgradeRoute[],
  url: string,
): Promise<string> {
  const socket = new PassThrough()
  let text = ''
  socket.on('data', (chunk: unknown) => { text += String(chunk) })
  const closed = once(socket, 'end')
  void upgrades[0]!.handler(fakeUpgradeRequest(url), socket, Buffer.alloc(0))
  await closed
  return text.split('\r\n', 1)[0]!
}

/** Drive one upgrade over real loopback TCP and read the status line. */
async function tcpUpgradeStatus(url: string, route: WebUpgradeRoute): Promise<string> {
  const server = createServer((socket) => {
    void route.handler(
      {
        headers: {
          host: '127.0.0.1',
          upgrade: 'websocket',
          connection: 'Upgrade',
          'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
          'sec-websocket-version': '13',
        },
        method: 'GET',
        url,
      } as unknown as IncomingMessage,
      socket,
      Buffer.alloc(0),
    )
  })
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const port = (server.address() as AddressInfo).port
  try {
    const client = connect(port, '127.0.0.1')
    await once(client, 'connect')
    const statusLine = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error('timed out waiting for upgrade response')) }, 3000)
      client.once('data', (chunk: Buffer) => {
        clearTimeout(timer)
        resolve(chunk.toString('utf8').split('\r\n', 1)[0]!)
      })
      client.once('error', reject)
    })
    client.write(
      [
        `GET ${url} HTTP/1.1`,
        'Host: 127.0.0.1',
        'Upgrade: websocket',
        'Connection: Upgrade',
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
        'Sec-WebSocket-Version: 13',
        '',
        '',
      ].join('\r\n'),
    )
    const line = await statusLine
    client.destroy()
    return line
  } finally {
    await new Promise<void>(resolve => server.close(() => { resolve() }))
  }
}

describe('remote mux upgrade authorization', () => {
  it('keeps the fence rejection without a foundation', async () => {
    const { upgrades, dispose } = await mounted()
    try {
      expect(await rejectedStatus(upgrades, '/api/remote.mux?ticket=abc')).toBe('HTTP/1.1 401 Unauthorized')
    } finally {
      await dispose()
    }
  })

  it('keeps the fence rejection when the foundation declines', async () => {
    const { stub, seen } = stubFoundation(async () => 'unauthenticated')
    const { upgrades, dispose } = await mounted(stub)
    try {
      expect(await rejectedStatus(upgrades, '/api/remote.mux?ticket=abc')).toBe('HTTP/1.1 401 Unauthorized')
      expect(seen).toEqual(['/api/remote.mux?ticket=abc'])
    } finally {
      await dispose()
    }
  })

  it('maps foundation forbidden to 403', async () => {
    const { stub } = stubFoundation(async () => 'forbidden')
    const { upgrades, dispose } = await mounted(stub)
    try {
      expect(await rejectedStatus(upgrades, '/api/remote.mux?ticket=abc')).toBe('HTTP/1.1 403 Forbidden')
    } finally {
      await dispose()
    }
  })

  it('upgrades the socket on ticket proceed', async () => {
    const { stub, seen } = stubFoundation(async () => 'proceed')
    const { upgrades, dispose } = await mounted(stub)
    try {
      expect(await tcpUpgradeStatus('/api/remote.mux?ticket=abc', upgrades[0]!)).toBe('HTTP/1.1 101 Switching Protocols')
      expect(seen).toEqual(['/api/remote.mux?ticket=abc'])
    } finally {
      await dispose()
    }
  })

  it('answers 401 when the ticket check itself fails', async () => {
    const { stub } = stubFoundation(async () => { throw new Error('store down') })
    const { upgrades, dispose } = await mounted(stub)
    try {
      expect(await rejectedStatus(upgrades, '/api/remote.mux?ticket=abc')).toBe('HTTP/1.1 401 Unauthorized')
    } finally {
      await dispose()
    }
  })
})
