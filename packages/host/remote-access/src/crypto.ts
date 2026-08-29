/**
 * Base64url helpers for remote-access tokens and fingerprints.
 * @module @deepseek-ai/dsh-host-remote-access/crypto
 */

/**
 * Encode bytes as unpadded base64url.
 * @param data - raw bytes.
 * @returns base64url string without padding.
 */
export function base64urlEncode(data: Uint8Array | Buffer): string {
  return Buffer.from(data).toString('base64url')
}

/**
 * Decode a base64url string to bytes.
 * @param value - base64url string (padding optional).
 * @returns decoded bytes.
 * @throws when the string is not valid base64url.
 */
export function base64urlDecode(value: string): Buffer {
  // Node tolerates missing padding for base64url.
  return Buffer.from(value, 'base64url')
}

/**
 * Encode a JSON value as base64url (UTF-8).
 * @param value - JSON-serializable value.
 * @returns base64url of `JSON.stringify(value)`.
 */
export function base64urlEncodeJson(value: unknown): string {
  return base64urlEncode(Buffer.from(JSON.stringify(value), 'utf8'))
}

/**
 * Decode base64url JSON.
 * @param value - base64url string.
 * @returns parsed JSON.
 * @throws when JSON is malformed.
 */
export function base64urlDecodeJson(value: string): unknown {
  return JSON.parse(base64urlDecode(value).toString('utf8'))
}
