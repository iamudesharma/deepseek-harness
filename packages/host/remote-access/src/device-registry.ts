/**
 * Persistent remote-device store.
 *
 * File: `$DSH_HOME/remote/devices.json` (0600, dirs 0700) via
 * `writeFileAtomic` + `withFileLock` RMW. Each record is a device's
 * public identity; private keys are never stored here.
 *
 * @module @deepseek-ai/dsh-host-remote-access/device-registry
 */

import { randomUUID } from 'node:crypto'
import { mkdir, readFile } from 'node:fs/promises'
import { dirname } from 'node:path'
import { resolveDeviceRegistryPath } from './paths.ts'
import { writeFileAtomic, withFileLock } from '@deepseek-ai/dsh-atomic-write'

/** Push registration for a paired device (Phase 10). */
export interface PushRegistration {
  /** Target platform. */
  platform: 'android' | 'ios'
  /** Opaque push token (FCM or APNs), never exposed via `remote.devices`. */
  pushToken: string
  /** Client app version at registration time. */
  appVersion: string
  /** Epoch milliseconds when the registration was first created. */
  registeredAt: number
  /** Epoch milliseconds when the registration was last updated. */
  updatedAt: number
}

/** Persisted device record (versioned). */
export interface DeviceRecord {
  /** Stable device id (UUID v4). */
  deviceId: string
  /** Human label. */
  displayName: string
  /** Base64 SPKI DER of the device public key. */
  publicKey: string
  /** Creation epoch milliseconds. */
  createdAt: number
  /** Last successful auth epoch milliseconds. */
  lastSeenAt: number
  /** Whether revoked. */
  revoked: boolean
  /** Revocation time when revoked. */
  revokedAt?: number
  /** Last issued token jti. */
  lastJti?: string
  /** Last token expiry epoch milliseconds. */
  tokenExpiresAt?: number
  /** Last token issued-at epoch milliseconds. */
  tokenIssuedAt?: number
  /** Optional push registration (Phase 10); absent when not registered. */
  pushRegistration?: PushRegistration
}

interface PersistedRegistry {
  version: 1
  devices: DeviceRecord[]
}

const DEVICE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function validateDeviceId(deviceId: string, file: string): void {
  if (!DEVICE_ID_PATTERN.test(deviceId)) {
    throw new Error(`device-registry: ${file} has invalid deviceId ${JSON.stringify(deviceId)}`)
  }
}

function parseRegistry(text: string, file: string): PersistedRegistry {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    throw new Error(`device-registry: ${file} is not valid JSON`)
  }
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error(`device-registry: ${file} is not an object`)
  }
  const record = parsed as Record<string, unknown>
  if (record['version'] !== 1) {
    throw new Error(`device-registry: ${file} has unsupported version ${String(record['version'])}`)
  }
  if (!Array.isArray(record['devices'])) {
    throw new Error(`device-registry: ${file} has invalid devices`)
  }
  for (const entry of record['devices'] as unknown[]) {
    if (typeof entry !== 'object' || entry === null) {
      throw new Error(`device-registry: ${file} has invalid device record`)
    }
    const device = entry as Record<string, unknown>
    if (typeof device['deviceId'] !== 'string' || typeof device['displayName'] !== 'string'
      || typeof device['publicKey'] !== 'string' || typeof device['createdAt'] !== 'number'
      || typeof device['lastSeenAt'] !== 'number' || typeof device['revoked'] !== 'boolean') {
      throw new Error(`device-registry: ${file} has malformed device record`)
    }
    validateDeviceId(device['deviceId'], file)
    const push = device['pushRegistration']
    if (push !== undefined) {
      if (typeof push !== 'object' || push === null) {
        throw new Error(`device-registry: ${file} has invalid pushRegistration`)
      }
      const reg = push as Record<string, unknown>
      if ((reg['platform'] !== 'android' && reg['platform'] !== 'ios')
        || typeof reg['pushToken'] !== 'string' || reg['pushToken'].length === 0
        || typeof reg['appVersion'] !== 'string'
        || typeof reg['registeredAt'] !== 'number' || typeof reg['updatedAt'] !== 'number') {
        throw new Error(`device-registry: ${file} has malformed pushRegistration`)
      }
    }
  }
  return record as unknown as PersistedRegistry
}

function serialize(registry: PersistedRegistry): string {
  return JSON.stringify(registry, null, 2) + '\n'
}

/**
 * Persistent device registry with atomic, locked RMW.
 */
export class DeviceRegistry {
  private readonly file: string

  /**
   * Create a registry bound to a harness home.
   * @param dshHome - explicit harness home.
   * @param env - environment mapping.
   */
  constructor(dshHome?: string, env: NodeJS.ProcessEnv = process.env) {
    this.file = resolveDeviceRegistryPath(dshHome, env)
  }

  /** File path (for diagnostics). */
  get path(): string {
    return this.file
  }

  /** Load all devices, returning empty array when the file is absent. */
  async list(): Promise<DeviceRecord[]> {
    let text: string
    try {
      text = await readFile(this.file, 'utf8')
    } catch (error) {
      if ((error as NodeJS.ErrnoException | null)?.code === 'ENOENT') return []
      throw error
    }
    const parsed = parseRegistry(text, this.file)
    return parsed.devices.map(device => ({ ...device }))
  }

  /**
   * Add a device; fails when deviceId already exists.
   * @param device - device record to add.
   * @throws when deviceId duplicates.
   */
  async add(device: DeviceRecord): Promise<void> {
    validateDeviceId(device.deviceId, this.file)
    await mkdir(dirname(this.file), { recursive: true, mode: 0o700 })
    await withFileLock(this.file, async () => {
      const current = await this.readLocked()
      if (current.devices.some(entry => entry.deviceId === device.deviceId)) {
        throw new Error(`device-registry: deviceId ${device.deviceId} already exists`)
      }
      current.devices.push({ ...device })
      // Order by lastSeenAt descending for stable listing (most recent first).
      current.devices.sort((left, right) => right.lastSeenAt - left.lastSeenAt)
      await writeFileAtomic(this.file, serialize(current), { mode: 0o600, dirMode: 0o700 })
    })
  }

  /**
   * Update a device by id (e.g. lastSeenAt, token jti, revocation).
   * @param deviceId - target id.
   * @param updater - receives a copy, returns the updated record or `undefined` to no-op.
   * @returns the updated record when changed.
   * @throws when deviceId unknown.
   */
  async update(
    deviceId: string,
    updater: (current: DeviceRecord) => DeviceRecord | undefined,
  ): Promise<DeviceRecord> {
    validateDeviceId(deviceId, this.file)
    let result: DeviceRecord | undefined
    await mkdir(dirname(this.file), { recursive: true, mode: 0o700 })
    await withFileLock(this.file, async () => {
      const current = await this.readLocked()
      const index = current.devices.findIndex(entry => entry.deviceId === deviceId)
      if (index === -1) throw new Error(`device-registry: unknown deviceId ${deviceId}`)
      const existing = current.devices[index] as DeviceRecord
      const next = updater({ ...existing })
      if (next === undefined) {
        result = { ...existing }
        return
      }
      if (next.deviceId !== deviceId) throw new Error('device-registry: deviceId cannot change')
      validateDeviceId(next.deviceId, this.file)
      current.devices[index] = { ...next }
      current.devices.sort((left, right) => right.lastSeenAt - left.lastSeenAt)
      await writeFileAtomic(this.file, serialize(current), { mode: 0o600, dirMode: 0o700 })
      result = { ...next }
    })
    // withFileLock guarantees the write completed before returning.
    return result as DeviceRecord
  }

  /** Mark one device revoked. */
  async revoke(deviceId: string, now: () => number = Date.now): Promise<DeviceRecord> {
    return this.update(deviceId, (current) => {
      if (current.revoked) return undefined
      const next: DeviceRecord = { ...current, revoked: true, revokedAt: now() }
      // Revocation disables push delivery.
      if (next.pushRegistration !== undefined) delete (next as { pushRegistration?: PushRegistration }).pushRegistration
      return next
    })
  }

  /** Revoke all devices. */
  async revokeAll(now: () => number = Date.now): Promise<void> {
    await mkdir(dirname(this.file), { recursive: true, mode: 0o700 })
    await withFileLock(this.file, async () => {
      const current = await this.readLocked()
      let changed = false
      for (const device of current.devices) {
        if (!device.revoked) {
          device.revoked = true
          device.revokedAt = now()
          if (device.pushRegistration !== undefined) delete (device as { pushRegistration?: PushRegistration }).pushRegistration
          changed = true
        } else if (device.pushRegistration !== undefined) {
          // Already revoked but still has stale registration — clean it.
          delete (device as { pushRegistration?: PushRegistration }).pushRegistration
          changed = true
        }
      }
      if (!changed) return
      await writeFileAtomic(this.file, serialize(current), { mode: 0o600, dirMode: 0o700 })
    })
  }

  /** Register or refresh push token for one device (atomic). */
  async registerPush(
    deviceId: string,
    registration: Omit<PushRegistration, 'registeredAt' | 'updatedAt'> & { registeredAt?: number; updatedAt?: number },
    now: () => number = Date.now,
  ): Promise<DeviceRecord> {
    return this.update(deviceId, (current) => {
      if (current.revoked) throw new Error(`device-registry: device ${deviceId} is revoked`)
      const at = now()
      const existing = current.pushRegistration
      const next: PushRegistration = {
        platform: registration.platform,
        pushToken: registration.pushToken,
        appVersion: registration.appVersion,
        registeredAt: existing?.registeredAt ?? registration.registeredAt ?? at,
        updatedAt: registration.updatedAt ?? at,
      }
      return { ...current, pushRegistration: next, lastSeenAt: at }
    })
  }

  /** Remove push registration for one device (atomic). */
  async unregisterPush(deviceId: string): Promise<DeviceRecord> {
    return this.update(deviceId, (current) => {
      if (current.pushRegistration === undefined) return undefined
      const next = { ...current }
      delete (next as { pushRegistration?: PushRegistration }).pushRegistration
      return next
    })
  }

  /** Find one device by id, or undefined when absent. */
  async find(deviceId: string): Promise<DeviceRecord | undefined> {
    const devices = await this.list()
    return devices.find(device => device.deviceId === deviceId)
  }

  private async readLocked(): Promise<PersistedRegistry> {
    let text: string
    try {
      text = await readFile(this.file, 'utf8')
    } catch (error) {
      if ((error as NodeJS.ErrnoException | null)?.code === 'ENOENT') {
        return { version: 1, devices: [] }
      }
      throw error
    }
    return parseRegistry(text, this.file)
  }
}

/**
 * Validate a deviceId string is a UUID v4 (loose, case-insensitive).
 * @param deviceId - candidate id.
 * @returns true when valid.
 */
export function isValidDeviceId(deviceId: string): boolean {
  return DEVICE_ID_PATTERN.test(deviceId)
}

/**
 * Generate a deviceId (UUID v4).
 * @returns new device id.
 */
export function generateDeviceId(): string {
  return randomUUID()
}
