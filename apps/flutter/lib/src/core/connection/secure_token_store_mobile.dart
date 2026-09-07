import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_token_store.dart';

/// Mobile/macOS secure store backed by Keychain (iOS/macOS) / Keystore (Android).
class FlutterSecureTokenStore implements SecureTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String deviceId) => 'dsh_remote_token_$deviceId';

  @override
  Future<String?> read(String deviceId) => _storage.read(key: _key(deviceId));

  @override
  Future<void> write(String deviceId, String token) =>
      _storage.write(key: _key(deviceId), value: token);

  @override
  Future<void> delete(String deviceId) => _storage.delete(key: _key(deviceId));

  @override
  Future<void> clear() async {
    final all = await _storage.readAll();
    for (final k in all.keys.where((k) => k.startsWith('dsh_remote_token_'))) {
      await _storage.delete(key: k);
    }
  }
}
