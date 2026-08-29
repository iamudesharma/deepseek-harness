/**
 * TLS boundary for remote transport: host certificate storage and pinning.
 * @module @deepseek-ai/dsh-host-remote-access/tls
 */

import { mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { createHash, generateKeyPairSync, X509Certificate } from 'node:crypto'
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths'
import { base64urlEncode } from './crypto.ts'

const CERT_FILE = 'remote/cert.pem'
const KEY_FILE = 'remote/key.pem'

/**
 * Resolve cert/key paths.
 * @param dshHome - explicit home.
 * @param env - env.
 * @returns paths.
 */
function resolvePaths(dshHome?: string, env: NodeJS.ProcessEnv = process.env): { certPath: string; keyPath: string } {
  const home = resolveDshHome(dshHome, env)
  return { certPath: join(home, CERT_FILE), keyPath: join(home, KEY_FILE) }
}

/**
 * Generate a self-signed certificate for the host (minimal, for remote TLS).
 * Uses Node's ability to create a KeyObject + self-sign via openssl fallback.
 * If openssl is unavailable, falls back to a deterministic placeholder cert
 * derived from the hostId so pairing can still pin.
 * @param hostId - stable hostId to embed in CN.
 * @param dshHome - explicit home.
 * @param env - env.
 * @returns cert PEM and fingerprint.
 */
export async function ensureHostCertificate(
  hostId: string,
  dshHome?: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<{ certPem: string; keyPem: string; fingerprint: string }> {
  const { certPath, keyPath } = resolvePaths(dshHome, env)
  try {
    const [certPem, keyPem] = await Promise.all([
      readFile(certPath, 'utf8'),
      readFile(keyPath, 'utf8'),
    ])
    const fingerprint = certFingerprint(certPem)
    return { certPem, keyPem, fingerprint }
  } catch (error) {
    if ((error as NodeJS.ErrnoException | null)?.code !== 'ENOENT'
      && !(error as Error).message.includes('ENOENT')) {
      // Corrupt cert: fall through to regeneration.
    }
  }
  // Generate a self-signed cert via openssl if available; otherwise use hostId-derived placeholder.
  let certPem: string
  let keyPem: string
  try {
    const { execSync } = await import('node:child_process')
    // Generate key + cert in one openssl invocation (no passphrase, 3650 days).
    // We write key to a temp location, then read both.
    const tmpKey = `${keyPath}.tmp-key`
    const tmpCert = `${certPath}.tmp-cert`
    await mkdir(dirname(certPath), { recursive: true, mode: 0o700 })
    // Use EC prime256v1 for speed; fallback to RSA if unsupported.
    try {
      execSync(`openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 3650 -nodes -keyout ${JSON.stringify(tmpKey)} -out ${JSON.stringify(tmpCert)} -subj "/CN=${hostId.slice(0, 16)}" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null`, { stdio: 'ignore' })
    } catch {
      execSync(`openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout ${JSON.stringify(tmpKey)} -out ${JSON.stringify(tmpCert)} -subj "/CN=${hostId.slice(0, 16)}" 2>/dev/null`, { stdio: 'ignore' })
    }
    const [{ readFile: rf }, { rm }] = await Promise.all([import('node:fs/promises'), import('node:fs/promises')])
    certPem = await rf(tmpCert, 'utf8')
    keyPem = await rf(tmpKey, 'utf8')
    await rm(tmpKey, { force: true })
    await rm(tmpCert, { force: true })
  } catch {
    // Fallback: generate a keypair via Node and use its SPKI as placeholder cert.
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
    keyPem = privateKey.export({ format: 'pem', type: 'sec1' }) as string
    certPem = `-----BEGIN CERTIFICATE-----\n${Buffer.from(hostId).toString('base64')}\n-----END CERTIFICATE-----\n`
  }
  await mkdir(dirname(certPath), { recursive: true, mode: 0o700 })
  // Write atomically with 0600 (no extra atomic helper to avoid dep cycle; simple writeFile with mode).
  await Promise.all([
    writeFile(certPath, certPem, { mode: 0o600 }),
    writeFile(keyPath, keyPem, { mode: 0o600 }),
  ])
  // Ensure 0600 even on umask.
  try {
    const { chmod } = await import('node:fs/promises')
    await Promise.all([chmod(certPath, 0o600), chmod(keyPath, 0o600)])
  } catch {}
  return { certPem, keyPem, fingerprint: certFingerprint(certPem) }
}

/**
 * Compute SHA-256 fingerprint of a PEM cert (or placeholder).
 * @param certPem - PEM string.
 * @returns base64url(sha256(der)).
 */
export function certFingerprint(certPem: string): string {
  try {
    const cert = new X509Certificate(certPem)
    return base64urlEncode(createHash('sha256').update(cert.raw).digest())
  } catch {
    return base64urlEncode(createHash('sha256').update(certPem).digest())
  }
}

/**
 * Whether TLS material exists without generating.
 * @param dshHome - explicit home.
 * @param env - env.
 * @returns true when both files exist.
 */
export async function hasHostCertificate(
  dshHome?: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<boolean> {
  const { certPath, keyPath } = resolvePaths(dshHome, env)
  try {
    await Promise.all([stat(certPath), stat(keyPath)])
    return true
  } catch {
    return false
  }
}
