import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_token_store_mobile.dart';

/// Secure token store abstraction.
///
/// On Android/iOS this will be backed by `flutter_secure_storage` (Keychain/
/// Keystore); on Web/macOS it falls back to `SharedPreferences` with an
/// in-memory cache. The interface is transport-agnostic: callers store the
/// bearer token keyed by `deviceId`, never the private key (which is not
/// stored on the host).
abstract class SecureTokenStore {
  /// Read the bearer token for [deviceId], or `null` if none.
  Future<String?> read(String deviceId);

  /// Persist the bearer token for [deviceId].
  Future<void> write(String deviceId, String token);

  /// Delete the token for [deviceId] (revocation / re-pair).
  Future<void> delete(String deviceId);

  /// Delete all tokens (revoke-all / logout).
  Future<void> clear();
}

/// In-memory implementation for tests and for Web where secure storage is
/// not critical. Also used as the fallback when `flutter_secure_storage`
/// is unavailable.
class InMemoryTokenStore implements SecureTokenStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String deviceId) async => _store[deviceId];

  @override
  Future<void> write(String deviceId, String token) async {
    _store[deviceId] = token;
  }

  @override
  Future<void> delete(String deviceId) async {
    _store.remove(deviceId);
  }

  @override
  Future<void> clear() async => _store.clear();
}

/// SharedPreferences-backed store for production Web/macOS.
///
/// On Android/iOS the app should provide a `FlutterSecureTokenStore`
/// (see `secure_token_store_mobile.dart` conditional import). This fallback
/// keeps Web builds clean without adding `flutter_secure_storage` to the
/// Web bundle.
class SharedPrefsTokenStore implements SecureTokenStore {
  static const _prefix = 'dsh_remote_token_';

  @override
  Future<String?> read(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$deviceId');
  }

  @override
  Future<void> write(String deviceId, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$deviceId', token);
  }

  @override
  Future<void> delete(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$deviceId');
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}

/// Riverpod provider for the token store. Tests override with [InMemoryTokenStore].
///
/// Web/macOS fallback is [SharedPrefsTokenStore]; Android/iOS/macOS (when
/// available) use [FlutterSecureTokenStore] (Keychain/Keystore). The
/// conditional keeps the Web bundle free of `dart:io` and ensures Android/iOS
/// never persist the bearer token in plain SharedPreferences.
final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  if (kIsWeb) return SharedPrefsTokenStore();
  return FlutterSecureTokenStore();
});
