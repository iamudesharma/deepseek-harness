import { PassThrough } from 'node:stream'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { Context } from '@deepseek-ai/cordis'
import {
  apply,
  createOperatorConsole,
  errorMessage,
  startOperatorConsole,
  type OperatorConsoleDeps,
} from '../src/operator-console.ts'
import { AuditLog } from '../src/audit.ts'
import { DeviceRegistry } from '../src/device-registry.ts'
import { loadOrCreateHostIdentity, type HostIdentity } from '../src/host-identity.ts'
import { PairingApprovalStore } from '../src/pairing-approval.ts'
import { PairingStore } from '../src/pairing-store.ts'
import { TokenService } from '../src/token-service.ts'
import { WsTicketStore } from '../src/auth-middleware.ts'
import type { RemoteAccessFoundation } from '../src/index.ts'

const homes: string[] = []
afterEach(() => {
  for (const home of homes.splice(0)) rmSync(home, { recursive: true, force: true })
})

function tempHome(): string {
  const home = mkdtempSync(join(tmpdir(), 'dsh-op-console-'))
  homes.push(home)
  return home
}

/** Live foundation assembled from real parts (no process boot, isolated home). */
async function foundationStub(overrides: { isEnabled?: boolean } = {}): Promise<RemoteAccessFoundation> {
  const home = tempHome()
  const identity: HostIdentity = await loadOrCreateHostIdentity({ dshHome: home })
  return {
    pairing: new PairingStore(),
    approval: new PairingApprovalStore(),
    devices: new DeviceRegistry(home),
    hostIdentity: identity,
    tokenService: new TokenService(identity),
    audit: new AuditLog(),
    wsTickets: new WsTicketStore(),
    tlsFingerprint: 'F'.repeat(43),
    tlsPort: 3443,
    isEnabled: overrides.isEnabled ?? true,
  } as unknown as RemoteAccessFoundation
}

/** Memory streams capturing console output. */
function streams(): { input: PassThrough; output: PassThrough; text: () => string } {
  const input = new PassThrough()
  const output = new PassThrough()
  let text = ''
  output.on('data', (chunk: unknown) => { text += String(chunk) })
  return { input, output, text: () => text }
}

async function waitFor(text: () => string, needle: string): Promise<void> {
  const start = Date.now()
  while (!text().includes(needle)) {
    if (Date.now() - start > 3000) {
      throw new Error(`timed out waiting for ${JSON.stringify(needle)} in ${JSON.stringify(text().slice(-500))}`)
    }
    await new Promise(resolve => setTimeout(resolve, 10))
  }
}

async function deps(overrides: Partial<OperatorConsoleDeps> = {}): Promise<{
  deps: OperatorConsoleDeps
  foundation: RemoteAccessFoundation
  io: ReturnType<typeof streams>
}> {
  const foundation = await foundationStub()
  const io = streams()
  return {
    deps: {
      foundation,
      webRuntime: { lanAddresses: ['192.168.1.10'] },
      input: io.input,
      output: io.output,
      withPin: false,
      ...overrides,
    },
    foundation,
    io,
  }
}

/** One pending approval; returns its nonce. */
function pend(foundation: RemoteAccessFoundation, displayName = 'Pixel 7'): string {
  const approval = (foundation as unknown as { approval: PairingApprovalStore }).approval
  const nonce = '11111111-1111-4111-8111-111111111111'
  approval.request(
    {
      hostId: 'H'.repeat(43),
      deviceId: '22222222-2222-4222-8222-222222222222',
      displayName,
      devicePublicKey: 'cHVibGlj',
      nonce,
    },
    nonce,
  )
  return nonce
}

describe('operator console commands', () => {
  it('errorMessage renders errors and plain rejections', () => {
    expect(errorMessage(new Error('disk gone'))).toBe('disk gone')
    expect(errorMessage('disk gone')).toBe('disk gone')
  })

  it('help lists the commands', async () => {
    const { deps: d, io } = await deps()
    const console = createOperatorConsole(d)
    try {
      io.input.write('help\n')
      await waitFor(io.text, 'commands: qr | approve')
    } finally {
      console.close()
    }
  })

  it('ignores empty lines and rejects unknown commands', async () => {
    const { deps: d, io } = await deps()
    const console = createOperatorConsole(d)
    try {
      io.input.write('\n')
      io.input.write('frobnicate\n')
      await waitFor(io.text, 'unknown command "frobnicate"')
    } finally {
      console.close()
    }
  })

  it('pending reports none, then lists entries', async () => {
    const { deps: d, foundation, io } = await deps()
    const console = createOperatorConsole(d)
    try {
      io.input.write('pending\n')
      await waitFor(io.text, 'no pending pairings')
      pend(foundation)
      io.input.write('pending\n')
      await waitFor(io.text, 'Pixel 7')
      await waitFor(io.text, '11111111…')
    } finally {
      console.close()
    }
  })

  it('devices reports none, entries, and revocation', async () => {
    const { deps: d, foundation, io } = await deps()
    const devices = (foundation as unknown as { devices: DeviceRegistry }).devices
    const console = createOperatorConsole(d)
    try {
      io.input.write('devices\n')
      await waitFor(io.text, 'no paired devices')
      await devices.add({
        deviceId: '33333333-3333-4333-8333-333333333333',
        displayName: 'Tablet',
        publicKey: 'cHVibGlj',
        createdAt: 1000,
        lastSeenAt: 1000,
        revoked: false,
      })
      await devices.add({
        deviceId: '44444444-4444-4444-8444-444444444444',
        displayName: 'Old',
        publicKey: 'cHVibGlj',
        createdAt: 1000,
        lastSeenAt: 1000,
        revoked: false,
      })
      await devices.revoke('44444444-4444-4444-8444-444444444444')
      io.input.write('devices\n')
      await waitFor(io.text, '"Tablet" 33333333')
      await waitFor(io.text, '"Old" 44444444-4444-4444-8444-444444444444 revoked')
    } finally {
      console.close()
    }
  })

  it('devices reports store failures instead of hanging', async () => {
    const { deps: d, io } = await deps()
    const broken = {
      list: async (): Promise<never> => { throw new Error('disk gone') },
    }
    ;(d.foundation as unknown as { devices: unknown }).devices = broken
    const console = createOperatorConsole(d)
    try {
      io.input.write('devices\n')
      await waitFor(io.text, 'devices failed: disk gone')
    } finally {
      console.close()
    }
  })

  it('qr prints the block without a PIN by default', async () => {
    const { deps: d, io } = await deps()
    const console = createOperatorConsole(d)
    try {
      io.input.write('qr\n')
      await waitFor(io.text, 'dsh remote: scan to pair')
      await waitFor(io.text, 'URL: https://192.168.1.10:3443')
      await waitFor(io.text, 'Nonce: ')
      await waitFor(io.text, 'Expires: ')
      expect(io.text()).not.toContain('PIN: ')
    } finally {
      console.close()
    }
  })

  it('qr prints the PIN when ceremonies mint one', async () => {
    const { deps: d, io } = await deps({ withPin: true })
    const console = createOperatorConsole(d)
    try {
      io.input.write('qr\n')
      await waitFor(io.text, 'PIN: ')
    } finally {
      console.close()
    }
  })

  it('qr still issues when the listener reported no fingerprint', async () => {
    const { deps: d, foundation, io } = await deps()
    delete (foundation as unknown as { tlsFingerprint?: string }).tlsFingerprint
    const console = createOperatorConsole(d)
    try {
      io.input.write('qr\n')
      await waitFor(io.text, 'dsh remote: scan to pair')
      await waitFor(io.text, 'Nonce: ')
    } finally {
      console.close()
    }
  })

  it('qr fails loudly when TLS is down', async () => {
    const home = tempHome()
    const identity = await loadOrCreateHostIdentity({ dshHome: home })
    const foundation = {
      pairing: new PairingStore(),
      approval: new PairingApprovalStore(),
      devices: new DeviceRegistry(home),
      hostIdentity: identity,
      tokenService: new TokenService(identity),
      audit: new AuditLog(),
      wsTickets: new WsTicketStore(),
      isEnabled: true,
    } as unknown as RemoteAccessFoundation
    const io = streams()
    const console = createOperatorConsole({
      foundation,
      input: io.input,
      output: io.output,
      withPin: false,
    })
    try {
      io.input.write('qr\n')
      await waitFor(io.text, 'qr failed: remote-access: remote TLS listener is not up')
      await console.printBootBlock()
      await waitFor(io.text, 'dsh remote: remote-access: remote TLS listener is not up')
    } finally {
      console.close()
    }
  })

  it('approve and deny settle by exact nonce or unambiguous prefix', async () => {
    const { deps: d, foundation, io } = await deps()
    const approval = (foundation as unknown as { approval: PairingApprovalStore }).approval
    const console = createOperatorConsole(d)
    try {
      io.input.write('approve\n')
      await waitFor(io.text, 'usage: approve <nonce>')
      io.input.write('deny\n')
      await waitFor(io.text, 'usage: deny <nonce>')
      io.input.write('approve deadbeef\n')
      await waitFor(io.text, 'no pending pairing matches "deadbeef"')
      const nonce = pend(foundation)
      io.input.write(`approve ${nonce.slice(0, 8)}\n`)
      await waitFor(io.text, `approved ${nonce.slice(0, 8)}…`)
      io.input.write(`approve ${nonce}\n`)
      await waitFor(io.text, 'no pending pairing matches')
      const nonce2 = 'aaaaaaaa-1111-4111-8111-111111111111'
      approval.request(
        {
          hostId: 'H'.repeat(43),
          deviceId: '55555555-5555-4555-8555-555555555555',
          displayName: 'A',
          devicePublicKey: 'cHVibGlj',
          nonce: nonce2,
        },
        nonce2,
      )
      io.input.write(`deny ${nonce2}\n`)
      await waitFor(io.text, `denied ${nonce2.slice(0, 8)}…`)
    } finally {
      console.close()
    }
  })

  it('approve rejects ambiguous prefixes and reports decided races', async () => {
    const { deps: d, foundation, io } = await deps()
    const approval = (foundation as unknown as { approval: PairingApprovalStore }).approval
    const console = createOperatorConsole(d)
    try {
      const nonceA = 'bbbbbbbb-1111-4111-8111-111111111111'
      const nonceB = 'bbbbbbbb-2222-4222-8222-222222222222'
      for (const [nonce, name] of [[nonceA, 'A'], [nonceB, 'B']] as const) {
        approval.request(
          {
            hostId: 'H'.repeat(43),
            deviceId: '66666666-6666-4666-8666-666666666666',
            displayName: name,
            devicePublicKey: 'cHVibGlj',
            nonce,
          },
          nonce,
        )
      }
      io.input.write('approve bbbbbbbb\n')
      await waitFor(io.text, 'several pending pairings match "bbbbbbbb"')
      approval.deny(nonceA)
      io.input.write(`approve ${nonceA}\n`)
      await waitFor(io.text, `no pending pairing matches ${JSON.stringify(nonceA)}`)
    } finally {
      console.close()
    }
  })
})

describe('operator console lifecycle', () => {
  it('printBootBlock falls back to loopback without LAN addresses', async () => {
    const home = tempHome()
    const identity = await loadOrCreateHostIdentity({ dshHome: home })
    const foundation = {
      pairing: new PairingStore(),
      approval: new PairingApprovalStore(),
      devices: new DeviceRegistry(home),
      hostIdentity: identity,
      tokenService: new TokenService(identity),
      audit: new AuditLog(),
      wsTickets: new WsTicketStore(),
      tlsPort: 3443,
      tlsFingerprint: 'F'.repeat(43),
      isEnabled: true,
    } as unknown as RemoteAccessFoundation
    const io = streams()
    const console = createOperatorConsole({
      foundation,
      input: io.input,
      output: io.output,
      withPin: false,
    })
    try {
      await console.printBootBlock()
      await waitFor(io.text, 'URL: https://127.0.0.1:3443')
    } finally {
      console.close()
    }
  })

  it('startOperatorConsole stays dormant without a TTY', async () => {
    const { foundation } = await deps()
    const messages: string[] = []
    const io = streams()
    const dispose = startOperatorConsole({
      logger: { info: (message: string) => { messages.push(message) } },
      interactive: false,
      console: {
        foundation,
        input: io.input,
        output: io.output,
        withPin: false,
      },
    })
    try {
      expect(messages).toEqual(['remote-access: operator console dormant (no TTY)'])
      expect(io.text()).toBe('')
    } finally {
      dispose()
    }
  })

  it('startOperatorConsole prints at once without a Loader', async () => {
    const { foundation, io } = await deps()
    const dispose = startOperatorConsole({
      logger: { info: () => {} },
      interactive: true,
      console: {
        foundation,
        webRuntime: { lanAddresses: ['10.0.0.9'] },
        input: io.input,
        output: io.output,
        withPin: false,
      },
    })
    try {
      await waitFor(io.text, 'URL: https://10.0.0.9:3443')
    } finally {
      dispose()
    }
  })

  it('startOperatorConsole waits for Loader settle and survives boot failure', async () => {
    const { foundation, io } = await deps()
    let release!: () => void
    const gate = new Promise<void>((resolve) => { release = resolve })
    const dispose = startOperatorConsole({
      logger: { info: () => {} },
      loader: { await: () => gate },
      interactive: true,
      console: {
        foundation,
        input: io.input,
        output: io.output,
        withPin: false,
      },
    })
    try {
      await new Promise(resolve => setTimeout(resolve, 50))
      expect(io.text()).not.toContain('scan to pair')
      release()
      await waitFor(io.text, 'scan to pair')
    } finally {
      dispose()
    }
    const io2 = streams()
    const dispose2 = startOperatorConsole({
      logger: { info: () => {} },
      loader: { await: () => Promise.reject(new Error('boot failed')) },
      interactive: true,
      console: {
        foundation,
        input: io2.input,
        output: io2.output,
        withPin: false,
      },
    })
    try {
      await new Promise(resolve => setTimeout(resolve, 50))
      expect(io2.text()).not.toContain('scan to pair')
    } finally {
      dispose2()
    }
  })

  it('apply stays dormant without config, when disabled, or when remote is off', async () => {
    const ctx = new Context()
    const dormant = apply(ctx, undefined)
    try {
      expect(dormant).toBeTypeOf('function')
    } finally {
      dormant()
    }
    const dormant2 = apply(ctx, { enabled: false })
    try {
      expect(dormant2).toBeTypeOf('function')
    } finally {
      dormant2()
    }
    const off = await foundationStub({ isEnabled: false })
    const ctx2 = new Context()
    ;(ctx2 as unknown as Record<string, unknown>)['remoteAccessFoundation'] = off
    const dormant3 = apply(ctx2, { enabled: true })
    try {
      expect(dormant3).toBeTypeOf('function')
    } finally {
      dormant3()
    }
  })

  it('apply delegates to the lifecycle with process streams', async () => {
    const { foundation } = await deps()
    const ctx = new Context()
    ;(ctx as unknown as Record<string, unknown>)['remoteAccessFoundation'] = foundation
    const dispose = apply(ctx, { enabled: true })
    try {
      expect(dispose).toBeTypeOf('function')
    } finally {
      dispose()
    }
    const loaderStub = { await: () => Promise.resolve() }
    const ctx2 = new Context()
    ;(ctx2 as unknown as Record<string, unknown>)['remoteAccessFoundation'] = foundation
    const originalGet = ctx2.get.bind(ctx2)
    ;(ctx2 as unknown as { get: (name: string) => unknown }).get = (name: string) => {
      return name === 'loader' ? loaderStub : originalGet(name)
    }
    const dispose2 = apply(ctx2, { enabled: true, withPin: true })
    try {
      expect(dispose2).toBeTypeOf('function')
    } finally {
      dispose2()
    }
  })
})
