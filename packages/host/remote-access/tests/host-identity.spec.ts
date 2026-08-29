import { mkdtempSync, rmSync, readFileSync, writeFileSync, statSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { loadOrCreateHostIdentity, loadHostIdentity, hostIdOf } from '../src/host-identity.ts'
import { resolveHostIdentityPath } from '../src/paths.ts'

const dirs: string[] = []

function tempHome(): string {
  const dir = mkdtempSync(join(tmpdir(), 'dsh-remote-host-'))
  dirs.push(dir)
  return dir
}

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
})

describe('host identity', () => {
  it('creates a persistent Ed25519 keypair on first initialization', async () => {
    const home = tempHome()
    const identity = await loadOrCreateHostIdentity({ dshHome: home })
    expect(identity.hostId).toMatch(/^[A-Za-z0-9_-]{43}$/)
    expect(identity.fingerprint).toBe(identity.hostId)
    expect(identity.publicKeyDer.length).toBeGreaterThan(0)
    expect(identity.privateKeyDer.length).toBeGreaterThan(0)
    const file = resolveHostIdentityPath(home)
    const raw = readFileSync(file, 'utf8')
    const parsed = JSON.parse(raw) as { version: number; hostId: string }
    expect(parsed.version).toBe(1)
    expect(parsed.hostId).toBe(identity.hostId)
  })

  it('loads the same hostId on restart (stable fingerprint)', async () => {
    const home = tempHome()
    const first = await loadOrCreateHostIdentity({ dshHome: home })
    const second = await loadOrCreateHostIdentity({ dshHome: home })
    expect(second.hostId).toBe(first.hostId)
    expect(second.publicKeyDer.equals(first.publicKeyDer)).toBe(true)
    expect(second.fingerprint).toBe(first.fingerprint)
    expect(second.createdAt).toBe(first.createdAt)
  })

  it('produces stable fingerprint (hostId = base64url(sha256(spki)))', async () => {
    const home = tempHome()
    const identity = await loadOrCreateHostIdentity({ dshHome: home })
    expect(hostIdOf(identity.publicKeyDer)).toBe(identity.hostId)
  })

  it('sign and verify round-trips', async () => {
    const home = tempHome()
    const identity = await loadOrCreateHostIdentity({ dshHome: home })
    const data = Buffer.from('hello remote')
    const sig = identity.sign(data)
    expect(sig.length).toBe(64)
    expect(identity.verify(data, sig)).toBe(true)
    expect(identity.verify(Buffer.from('tampered'), sig)).toBe(false)
    const other = await loadOrCreateHostIdentity({ dshHome: tempHome() })
    expect(other.verify(data, sig)).toBe(false)
  })

  it('does not regenerate on every launch (file mtime stable)', async () => {
    const home = tempHome()
    const first = await loadOrCreateHostIdentity({ dshHome: home })
    const file = resolveHostIdentityPath(home)
    const before = statSync(file).mtimeMs
    await new Promise(resolve => setTimeout(resolve, 10))
    const second = await loadOrCreateHostIdentity({ dshHome: home })
    const after = statSync(file).mtimeMs
    expect(second.hostId).toBe(first.hostId)
    expect(after).toBe(before)
  })

  it('rejects corrupted identity (invalid JSON)', async () => {
    const home = tempHome()
    const file = resolveHostIdentityPath(home)
    mkdirSync(join(home, 'remote'), { recursive: true })
    writeFileSync(file, 'not-json', 'utf8')
    await expect(loadOrCreateHostIdentity({ dshHome: home })).rejects.toThrow(/not valid JSON/)
  })

  it('rejects corrupted identity (missing fields)', async () => {
    const home = tempHome()
    const file = resolveHostIdentityPath(home)
    mkdirSync(join(home, 'remote'), { recursive: true })
    writeFileSync(file, JSON.stringify({ version: 1 }), 'utf8')
    await expect(loadOrCreateHostIdentity({ dshHome: home })).rejects.toThrow(/malformed/)
  })

  it('rejects corrupted identity (hostId mismatch)', async () => {
    const home = tempHome()
    await loadOrCreateHostIdentity({ dshHome: home })
    const file = resolveHostIdentityPath(home)
    const raw = JSON.parse(readFileSync(file, 'utf8')) as Record<string, unknown>
    raw['hostId'] = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    writeFileSync(file, JSON.stringify(raw), 'utf8')
    await expect(loadHostIdentity(home)).rejects.toThrow(/hostId does not match/)
  })

  it('rejects corrupted identity (invalid key encoding)', async () => {
    const home = tempHome()
    const file = resolveHostIdentityPath(home)
    mkdirSync(join(home, 'remote'), { recursive: true })
    writeFileSync(file, JSON.stringify({
      version: 1,
      publicKey: '!!!',
      privateKey: '!!!',
      hostId: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      createdAt: Date.now(),
    }), 'utf8')
    await expect(loadOrCreateHostIdentity({ dshHome: home })).rejects.toThrow(/invalid key encoding|hostId does not match|has invalid/)
  })

  it('uses secure filesystem permissions (0600 file, 0700 dir)', async () => {
    if (process.platform === 'win32') return
    const home = tempHome()
    await loadOrCreateHostIdentity({ dshHome: home })
    const file = resolveHostIdentityPath(home)
    const fileMode = statSync(file).mode & 0o777
    const dirMode = statSync(join(home, 'remote')).mode & 0o777
    expect(fileMode).toBe(0o600)
    expect(dirMode).toBe(0o700)
  })

  it('loadHostIdentity fails when absent', async () => {
    const home = tempHome()
    await expect(loadHostIdentity(home)).rejects.toThrow()
  })
})
