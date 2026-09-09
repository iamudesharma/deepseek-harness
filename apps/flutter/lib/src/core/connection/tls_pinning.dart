import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TLS certificate pinning against the host fingerprint.
///
/// The host serves remote HTTPS with a self-signed certificate whose
/// fingerprint (`base64url(sha256(DER))`, 43 chars) travels in the pairing QR
/// (`certFp`) or `remote.describe` (`tlsFingerprint`). Native clients accept
/// the certificate only on an exact fingerprint match; Web clients cannot
/// bypass certificate errors programmatically and must trust the host once in
/// the browser instead.

/// Normalize a fingerprint for comparison (unpadded base64url).
String normalizeFingerprint(String value) => value.replaceAll('=', '');

/// Whether DER-encoded certificate bytes match the pinned fingerprint.
///
/// Returns false for malformed fingerprints rather than throwing, so a
/// corrupt pin fails closed into a connection error, not a crash.
/// @param der - DER bytes of the presented certificate.
/// @param fingerprint - pinned `base64url(sha256(DER))` fingerprint.
/// @returns true only on an exact match.
bool certificateMatchesPin(Uint8List der, String fingerprint) {
  final normalized = normalizeFingerprint(fingerprint);
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(normalized)) return false;
  final actual = base64Url
      .encode(sha256.convert(der).bytes)
      .replaceAll('=', '');
  return actual == normalized;
}
