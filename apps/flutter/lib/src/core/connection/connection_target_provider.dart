import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_target.dart';

/// Key for persisting the active target.
const _kTargetKey = 'dsh_connection_target';

/// Provider for the current [ConnectionTarget].
///
/// Defaults to [LocalTarget] — existing macOS/Web behavior.
/// Tests override this with a RemoteTarget via `ProviderScope(overrides:…)`.
final connectionTargetProvider = StateProvider<ConnectionTarget>((ref) {
  return const LocalTarget();
});

/// Bootstrap that restores a persisted [RemoteTarget] from SharedPreferences.
///
/// Watched in the root before `connectionBootstrapProvider`, so the first
/// handshake uses the restored target. Missing-plugin and corrupt-JSON cases
/// keep [LocalTarget] — the default local desktop/web path is unchanged.
final connectionTargetBootstrapProvider = FutureProvider<void>((ref) async {
  final String raw;
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kTargetKey);
    if (value == null) return;
    raw = value;
  } catch (_) {
    // SharedPreferences plugin channel unavailable (e.g. widget tests without
    // a mock): nothing persisted is readable, so LocalTarget is correct.
    return;
  }
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    ref.read(connectionTargetProvider.notifier).state =
        ConnectionTarget.fromJson(map);
  } catch (_) {
    // Corrupt JSON → keep LocalTarget.
  }
});

/// Persist the target (called after pairing or when switching back to local).
Future<void> persistConnectionTarget(ConnectionTarget target) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kTargetKey, jsonEncode(target.toJson()));
}

/// Clear the persisted target (logout / re-pair).
Future<void> clearPersistedTarget() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kTargetKey);
}
