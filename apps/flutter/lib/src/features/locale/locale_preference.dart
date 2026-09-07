/// Durable `locale` preference over the Host settings document — mirrors
/// `LOCALE_SETTINGS_NAMESPACE` / `LOCALE_PREFERENCE_FIELD` in
/// `packages/client/locale/src/locale-settings.ts` and the boot-time scope
/// adoption in `LocaleRuntime`
/// (`packages/client/locale/src/client/index.ts`).
library;

import '../../core/connection/connection_client.dart';
import '../../core/services/runtime_services.dart';

/// Settings namespace owned by the locale feature.
const String kLocaleSettingsNamespace = 'locale';

/// Field carrying the explicit locale selection.
const String kLocalePreferenceField = 'preference';

/// One read of the durable `locale` section off settings.describe.
class LocaleSection {
  /// Creates a section view.
  const LocaleSection({required this.preference, this.revision});

  /// Persisted selection; '' delegates to the app default.
  final String preference;

  /// Namespace revision (the next write's fence); null when absent.
  final int? revision;
}

/// Extracts the `locale` namespace from a settings.describe answer; null when
/// the namespace is absent.
LocaleSection? localeSectionFromDescribe(Map<String, dynamic> describe) {
  final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
  for (final ns in namespaces) {
    if (ns['ns'] != kLocaleSettingsNamespace) continue;
    final value = ns['value'] as Map<String, dynamic>? ?? const {};
    return LocaleSection(
      preference: value[kLocalePreferenceField] as String? ?? '',
      revision: ns['revision'] as int?,
    );
  }
  return null;
}

/// Applies the persisted preference onto [service] after activation — the
/// boot analog of React adopting the Host scope when the locale service is
/// constructed. A stale persisted id outside the current registry keeps the
/// running default; describe unreachability leaves it standing too.
Future<void> adoptPersistedLocale(
  ConnectionClient client,
  LocaleService service,
) async {
  try {
    final describe = await client.settingsDescribe();
    final section = localeSectionFromDescribe(describe);
    final preference = section?.preference ?? '';
    if (preference.isEmpty) return;
    service.setLocale(preference);
  } on ArgumentError {
    // Stale persisted id no longer registered: React's adopt publishes the
    // target without validation too, and per-key fallback covers missing
    // copy — a renamed locale id must not block boot.
  } catch (_) {
    // settings.describe unreachable at boot (no host / wire-down): matches
    // the other boot-time loads that leave defaults in place.
  }
}
