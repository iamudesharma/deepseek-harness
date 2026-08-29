/**
 * Filesystem locations for remote-access foundation data.
 * @module @deepseek-ai/dsh-host-remote-access/paths
 */

import { join } from 'node:path'
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths'

/** Subdirectory under the harness home holding remote-access files. */
export const REMOTE_DIR_NAME = 'remote'

/** Basename of the persisted host identity document. */
export const HOST_IDENTITY_FILE_NAME = 'host-identity.json'

/** Basename of the persisted device registry. */
export const DEVICE_REGISTRY_FILE_NAME = 'devices.json'

/**
 * Resolve the absolute path of the host identity file.
 * @param dshHome - explicit harness home; `undefined` resolves via `$DSH_HOME`.
 * @param env - environment mapping for `$DSH_HOME`.
 * @returns absolute path.
 */
export function resolveHostIdentityPath(
  dshHome?: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  return join(resolveDshHome(dshHome, env), REMOTE_DIR_NAME, HOST_IDENTITY_FILE_NAME)
}

/**
 * Resolve the absolute path of the device registry file.
 * @param dshHome - explicit harness home.
 * @param env - environment mapping.
 * @returns absolute path.
 */
export function resolveDeviceRegistryPath(
  dshHome?: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  return join(resolveDshHome(dshHome, env), REMOTE_DIR_NAME, DEVICE_REGISTRY_FILE_NAME)
}
