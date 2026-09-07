import 'connection_client.dart';

/// Remote pairing client — thin wrapper over `ConnectionClient.remotePair`.
///
/// Keeps pairing logic out of UI and makes it testable. The host's
/// `remote.pair` is the only unauthenticated remote endpoint; it requires a
/// valid `hostId`/`nonce`/`pin`/`deviceId` and explicit host approval before
/// the token is minted. This client does not store the token — the caller
/// (pairing UI / `SecureTokenStore`) does.
///
/// Host identity pinning: the caller must verify that the returned `hostId`
/// matches the pinned `RemoteTarget.hostId` before accepting the token;
/// mismatch → `needsReauth` (hostId change forces re-pair).
class RemotePairingClient {
  RemotePairingClient(this._client);

  final ConnectionClient _client;

  /// Pair and return the host's `hostId`, `hostPublicKey`, `deviceToken`,
  /// and `expiresAt`. Throws on `pairing-*` / `host-mismatch` / network errors.
  Future<
    ({String hostId, String hostPublicKey, String deviceToken, int expiresAt})
  >
  pair({
    required String hostId,
    required String deviceId,
    required String displayName,
    required String devicePublicKey,
    required String nonce,
    String? pin,
  }) async {
    final result = await _client.remotePair(
      hostId: hostId,
      deviceId: deviceId,
      displayName: displayName,
      devicePublicKey: devicePublicKey,
      nonce: nonce,
      pin: pin,
    );
    final hostIdResp = result['hostId'] as String?;
    final hostPub = result['hostPublicKey'] as String?;
    final token = result['deviceToken'] as String?;
    final expiresAt = result['expiresAt'] as int?;
    if (hostIdResp == null ||
        hostPub == null ||
        token == null ||
        expiresAt == null) {
      throw const FormatException('remote.pair: missing fields');
    }
    return (
      hostId: hostIdResp,
      hostPublicKey: hostPub,
      deviceToken: token,
      expiresAt: expiresAt,
    );
  }
}
