/// Platform-independent connection endpoint.
///
/// The rest of the Flutter application (ConnectionClient → ConnectionController
/// → LiveSync → SessionManager → Conversation/UI) is transport-agnostic and
/// consumes only [ConnectionClient] + streams. Only bootstrap/security/
/// discovery differ between [LocalTarget] and [RemoteTarget].
sealed class ConnectionTarget {
  const ConnectionTarget();

  /// Base URI of the host (http for local, https for remote).
  Uri get baseUri;

  /// Whether this is a remote (bearer-authenticated) target.
  bool get isRemote;

  /// Whether this is a local (loopback/trusted-host) target.
  bool get isLocal => !isRemote;

  /// Serialize for persistence (SharedPreferences / secure store is outside).
  Map<String, dynamic> toJson();

  /// Deserialize. Throws [FormatException] on unknown type.
  static ConnectionTarget fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'local':
        return LocalTarget.fromJson(json);
      case 'remote':
        return RemoteTarget.fromJson(json);
      default:
        throw FormatException('Unknown ConnectionTarget type $type');
    }
  }
}

/// Local loopback target — existing macOS/Web behavior, no bearer.
///
/// `host`/`port` default to `127.0.0.1:3080` for native macOS; Web uses
/// `Uri.base.origin` when this target is the default. No token, no pinning.
class LocalTarget extends ConnectionTarget {
  const LocalTarget({this.host = '127.0.0.1', this.port = 3080});

  /// Loopback host.
  final String host;

  /// Loopback port (0 = OS-assigned in tests).
  final int port;

  @override
  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  @override
  bool get isRemote => false;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'local',
    'host': host,
    'port': port,
  };

  factory LocalTarget.fromJson(Map<String, dynamic> json) => LocalTarget(
    host: json['host'] as String? ?? '127.0.0.1',
    port: (json['port'] as num?)?.toInt() ?? 3080,
  );

  @override
  bool operator ==(Object other) =>
      other is LocalTarget && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'LocalTarget($host:$port)';
}

/// Remote bearer-authenticated target — Android/iOS/macOS/Web remote.
///
/// `baseUri` is `https://host:port` (TLS required, no plaintext fallback).
/// `hostId` is the pinned stable host identity (`base64url(sha256(spki))`);
/// `hostPublicKey` is the pinned SPKI (base64) for pairing verification;
/// `certFingerprint` is optional TLS cert fingerprint.
/// `deviceId` is this client's stable UUID; `displayName` is human label.
class RemoteTarget extends ConnectionTarget {
  const RemoteTarget({
    required this.baseUri,
    required this.hostId,
    required this.hostPublicKey,
    this.certFingerprint,
    required this.deviceId,
    required this.displayName,
  });

  @override
  final Uri baseUri;

  /// Pinned hostId (stable, from pairing). Host mismatch → needsReauth.
  final String hostId;

  /// Pinned host public key (SPKI base64) from pairing.
  final String hostPublicKey;

  /// Optional pinned TLS cert fingerprint (base64url sha256).
  final String? certFingerprint;

  /// This device's stable UUID.
  final String deviceId;

  /// Human label (e.g. "Pixel 7").
  final String displayName;

  @override
  bool get isRemote => true;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'remote',
    'baseUri': baseUri.toString(),
    'hostId': hostId,
    'hostPublicKey': hostPublicKey,
    if (certFingerprint != null) 'certFingerprint': certFingerprint,
    'deviceId': deviceId,
    'displayName': displayName,
  };

  factory RemoteTarget.fromJson(Map<String, dynamic> json) => RemoteTarget(
    baseUri: Uri.parse(json['baseUri'] as String),
    hostId: json['hostId'] as String,
    hostPublicKey: json['hostPublicKey'] as String,
    certFingerprint: json['certFingerprint'] as String?,
    deviceId: json['deviceId'] as String,
    displayName: json['displayName'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is RemoteTarget &&
      other.baseUri == baseUri &&
      other.hostId == hostId &&
      other.hostPublicKey == hostPublicKey &&
      other.certFingerprint == certFingerprint &&
      other.deviceId == deviceId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(
    baseUri,
    hostId,
    hostPublicKey,
    certFingerprint,
    deviceId,
    displayName,
  );

  @override
  String toString() =>
      'RemoteTarget($baseUri hostId:${hostId.substring(0, 8)}… device:$deviceId)';
}
