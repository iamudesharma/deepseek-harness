import 'dart:convert';

/// QR payload for pairing — enough to establish baseUri + host identity + nonce.
///
/// The host generates a QR containing a JSON object (or `dsh://pair?data=…`
/// URL wrapping that JSON). The mobile validates every field before contacting
/// the host, and re-validates the host's `hostId`/`hostPublicKey` after the
/// pairing response to detect MITM.
class QrPayload {
  const QrPayload({
    required this.baseUri,
    required this.hostId,
    required this.hostPublicKey,
    required this.nonce,
    this.pin,
    required this.exp,
    this.displayName,
  });

  /// Host base URI (https://host:port, no trailing slash, no path).
  final Uri baseUri;

  /// Pinned hostId (base64url sha256 spki, 43 chars).
  final String hostId;

  /// Host public key (base64 SPKI) for pinning.
  final String hostPublicKey;

  /// One-time pairing nonce (UUID).
  final String nonce;

  /// Optional 6-digit PIN (when host issued one).
  final String? pin;

  /// Expiry epoch millis.
  final int exp;

  /// Optional display name from host.
  final String? displayName;

  static final _hostIdPat = RegExp(r'^[A-Za-z0-9_-]{43}$');
  static final _noncePat = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final _pinPat = RegExp(r'^[0-9]{6}$');

  /// Parse from a raw QR string (either `dsh://pair?data=base64url(json)` or
  /// plain JSON). Throws [FormatException] on invalid.
  static QrPayload parse(String raw) {
    String jsonStr;
    if (raw.startsWith('dsh://')) {
      final uri = Uri.tryParse(raw);
      if (uri == null) throw const FormatException('Invalid dsh:// URI');
      final data = uri.queryParameters['data'];
      if (data == null)
        throw const FormatException('Missing data in dsh:// URI');
      // data is base64url(json)
      try {
        jsonStr = utf8.decode(base64Url.decode(_padBase64(data)));
      } catch (_) {
        throw const FormatException('Invalid base64url data');
      }
    } else {
      jsonStr = raw.trim();
      // If it's base64url without dsh:// prefix, try to decode as well
      if (!jsonStr.startsWith('{')) {
        try {
          jsonStr = utf8.decode(base64Url.decode(_padBase64(jsonStr)));
        } catch (_) {
          // fall through to JSON parse which will fail with FormatException
        }
      }
    }
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return fromJson(map);
  }

  static QrPayload fromJson(Map<String, dynamic> json) {
    final baseUriStr = json['baseUri'] as String?;
    final hostId = json['hostId'] as String?;
    final hostPub = json['hostPublicKey'] as String?;
    final nonce = json['nonce'] as String?;
    final exp = json['exp'];
    if (baseUriStr == null ||
        hostId == null ||
        hostPub == null ||
        nonce == null ||
        exp == null) {
      throw const FormatException('Missing required QR fields');
    }
    final baseUri = Uri.tryParse(baseUriStr);
    if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
      throw const FormatException('Invalid baseUri');
    }
    if (!_hostIdPat.hasMatch(hostId))
      throw const FormatException('Invalid hostId');
    if (!_noncePat.hasMatch(nonce))
      throw const FormatException('Invalid nonce');
    final pin = json['pin'] as String?;
    if (pin != null && !_pinPat.hasMatch(pin))
      throw const FormatException('Invalid PIN');
    final expInt = exp is int ? exp : int.tryParse('$exp');
    if (expInt == null) throw const FormatException('Invalid exp');
    if (expInt <= DateTime.now().millisecondsSinceEpoch)
      throw const FormatException('QR expired');
    // Validate hostPublicKey is base64
    try {
      base64Decode(hostPub);
    } catch (_) {
      throw const FormatException('Invalid hostPublicKey');
    }
    return QrPayload(
      baseUri: baseUri,
      hostId: hostId,
      hostPublicKey: hostPub,
      nonce: nonce,
      pin: pin,
      exp: expInt,
      displayName: json['displayName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'baseUri': baseUri.toString(),
    'hostId': hostId,
    'hostPublicKey': hostPublicKey,
    'nonce': nonce,
    if (pin != null) 'pin': pin,
    'exp': exp,
    if (displayName != null) 'displayName': displayName,
  };

  /// Short fingerprint for display (first 8 chars of hostId).
  String get shortFingerprint =>
      hostId.length >= 8 ? hostId.substring(0, 8) : hostId;

  static String _padBase64(String s) {
    final pad = s.length % 4;
    if (pad == 2) return '$s==';
    if (pad == 3) return '$s=';
    if (pad == 1) return '$s===';
    return s;
  }
}
