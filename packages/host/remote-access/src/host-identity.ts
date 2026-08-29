/**
 * Persistent Ed25519 host identity: stable keypair, hostId, and fingerprint.
 *
 * The host identity is a per-harness-home Ed25519 keypair generated once and
 * reused for the lifetime of the home. `hostId` is the stable identifier
 * derived as `base64url(sha256(spkiPublicKeyDer))`; it is what the pairing
 * and token layer binds to so a token cannot be replayed against a different
 * host. Fingerprints are the same value, rendered as the user-facing identity.
 *
 * Storage: `$DSH_HOME/remote/host-identity.json` (mode 0600, dirs 0700) via
 * atomic write. Generation uses `node:crypto` `generateKeyPairSync('ed25519')`
 * and is performed only when no valid document exists.
 *
 * @module @deepseek-ai/dsh-host-remote-access/host-identity
 */

import {
  createHash,
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  sign as cryptoSign,
  verify as cryptoVerify,
} from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { base64urlEncode } from './crypto.ts'
import { resolveHostIdentityPath } from './paths.ts'
import { writeFileAtomic } from '@deepseek-ai/dsh-atomic-write'

/** JSON shape persisted on disk (versioned for future migration). */
interface PersistedHostIdentity {
  version: 1
  /** Base64-encoded SPKI DER of the Ed25519 public key. */
  publicKey: string
  /** Base64-encoded PKCS8 DER of the Ed25519 private key. */
  privateKey: string
  /** Stable hostId: base64url(sha256(spkiDer)). Duplicated for validation. */
  hostId: string
  /** Epoch milliseconds of first creation. */
  createdAt: number
}

/** Resolved host identity in memory, carrying live KeyObjects. */
export interface HostIdentity {
  /** Stable host identifier. */
  readonly hostId: string
  /** Public key SPKI DER, raw bytes. */
  readonly publicKeyDer: Buffer
  /** Private key PKCS8 DER, raw bytes (never logged). */
  readonly privateKeyDer: Buffer
  /** Same as hostId, user-facing fingerprint. */
  readonly fingerprint: string
  /** Creation time. */
  readonly createdAt: number
  /**
   * Sign bytes with the host private key (Ed25519, detached).
   * @param data - bytes to sign.
   * @returns raw 64-byte signature.
   */
  sign(data: Uint8Array | Buffer): Buffer
  /**
   * Verify a detached Ed25519 signature.
   * @param data - signed bytes.
   * @param signature - 64-byte signature.
   * @returns true when valid.
   */
  verify(data: Uint8Array | Buffer, signature: Uint8Array | Buffer): boolean
}

/** Validation for hostId: base64url of 32 bytes = 43 chars. */
const HOST_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/

function computeHostId(publicKeyDer: Buffer): string {
  const digest = createHash('sha256').update(publicKeyDer).digest()
  return base64urlEncode(digest)
}

function parsePersisted(text: string, file: string): PersistedHostIdentity {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    throw new Error(`host-identity: ${file} is not valid JSON`)
  }
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error(`host-identity: ${file} is not an object`)
  }
  const record = parsed as Record<string, unknown>
  if (record['version'] !== 1) {
    throw new Error(`host-identity: ${file} has unsupported version ${String(record['version'])}`)
  }
  if (typeof record['publicKey'] !== 'string' || typeof record['privateKey'] !== 'string'
    || typeof record['hostId'] !== 'string' || typeof record['createdAt'] !== 'number') {
    throw new Error(`host-identity: ${file} is malformed`)
  }
  if (!HOST_ID_PATTERN.test(record['hostId'])) {
    throw new Error(`host-identity: ${file} has invalid hostId`)
  }
  return record as unknown as PersistedHostIdentity
}

function loadKeyObjects(persisted: PersistedHostIdentity, file: string): HostIdentity {
  let publicKeyDer: Buffer
  let privateKeyDer: Buffer
  try {
    publicKeyDer = Buffer.from(persisted.publicKey, 'base64')
    privateKeyDer = Buffer.from(persisted.privateKey, 'base64')
    if (publicKeyDer.length === 0 || privateKeyDer.length === 0) throw new Error('empty key')
  } catch {
    throw new Error(`host-identity: ${file} has invalid key encoding`)
  }
  const computed = computeHostId(publicKeyDer)
  if (computed !== persisted.hostId) {
    throw new Error(`host-identity: ${file} hostId does not match its public key`)
  }
  let privateKey: ReturnType<typeof createPrivateKey>
  let publicKey: ReturnType<typeof createPublicKey>
  try {
    privateKey = createPrivateKey({ key: privateKeyDer, format: 'der', type: 'pkcs8' })
    publicKey = createPublicKey({ key: publicKeyDer, format: 'der', type: 'spki' })
  } catch {
    throw new Error(`host-identity: ${file} has invalid key material`)
  }
  return {
    hostId: persisted.hostId,
    publicKeyDer,
    privateKeyDer,
    fingerprint: persisted.hostId,
    createdAt: persisted.createdAt,
    sign(data) {
      return cryptoSign(null, Buffer.from(data), privateKey)
    },
    verify(data, signature) {
      return cryptoVerify(null, Buffer.from(data), publicKey, Buffer.from(signature))
    },
  }
}

/**
 * Load an existing host identity or atomically create one.
 *
 * Corrupted documents are rejected rather than silently regenerated so a
 * broken home never quietly forks its identity and invalidates issued tokens.
 *
 * @param options - location and clock seams.
 * @returns the stable host identity.
 * @throws when the persisted document is corrupt and cannot be parsed/validated.
 */
export async function loadOrCreateHostIdentity(options: {
  /** Explicit harness home. */
  dshHome?: string
  /** Environment mapping for `$DSH_HOME`. */
  env?: NodeJS.ProcessEnv
  /** Clock, defaults to `Date.now()`. */
  now?: () => number
  /** Random key generation hook (test seam). */
  generateKeyPair?: typeof generateKeyPairSync
} = {}): Promise<HostIdentity> {
  const file = resolveHostIdentityPath(options.dshHome, options.env)
  try {
    const text = await readFile(file, 'utf8')
    const persisted = parsePersisted(text, file)
    return loadKeyObjects(persisted, file)
  } catch (error) {
    const code = (error as NodeJS.ErrnoException | null)?.code
    if (code !== 'ENOENT') {
      if (code === undefined) throw error
      if ((error as Error).message.startsWith('host-identity:')) throw error
      throw error
    }
  }
  const generate = options.generateKeyPair ?? generateKeyPairSync
  const { privateKey, publicKey } = generate('ed25519')
  const publicKeyDer = publicKey.export({ format: 'der', type: 'spki' }) as Buffer
  const privateKeyDer = privateKey.export({ format: 'der', type: 'pkcs8' }) as Buffer
  const hostId = computeHostId(publicKeyDer)
  const createdAt = (options.now ?? Date.now)()
  const persisted: PersistedHostIdentity = {
    version: 1,
    publicKey: publicKeyDer.toString('base64'),
    privateKey: privateKeyDer.toString('base64'),
    hostId,
    createdAt,
  }
  const text = JSON.stringify(persisted, null, 2) + '\n'
  try {
    await writeFileAtomic(file, text, { mode: 0o600, dirMode: 0o700 })
  } catch (error) {
    try {
      const existingText = await readFile(file, 'utf8')
      const existing = parsePersisted(existingText, file)
      return loadKeyObjects(existing, file)
    } catch {
      throw error
    }
  }
  return loadKeyObjects(persisted, file)
}

/**
 * Load an existing host identity, failing when absent.
 * @param dshHome - explicit harness home.
 * @param env - environment.
 * @returns identity when present.
 * @throws when absent or corrupt.
 */
export async function loadHostIdentity(
  dshHome?: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<HostIdentity> {
  const file = resolveHostIdentityPath(dshHome, env)
  const text = await readFile(file, 'utf8')
  const persisted = parsePersisted(text, file)
  return loadKeyObjects(persisted, file)
}

/**
 * Compute a hostId from a public key DER without touching the filesystem.
 * @param publicKeyDer - SPKI DER bytes.
 * @returns base64url sha256.
 */
export function hostIdOf(publicKeyDer: Uint8Array | Buffer): string {
  return computeHostId(Buffer.from(publicKeyDer))
}
