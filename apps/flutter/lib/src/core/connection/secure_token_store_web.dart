import 'package:shared_preferences/shared_preferences.dart';

import 'secure_token_store.dart';

/// Web-only stub — uses SharedPreferences (browser origin isolation is the
/// transport boundary; httpOnly is not applicable on Web).
class WebSecureTokenStore implements SecureTokenStore {
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
