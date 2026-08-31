/// General settings service — the `ui-settings-general` faces sliced to the
/// Dart settings seam. React binds the General section's rows to per-namespace
/// scopes (`locale` for language, `ui-theme` for appearance); this service
/// owns both scopes over the shared describe wire so the section and any
/// later shell row read one source.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/connection/connection_client.dart';
import '../../../../core/settings/settings_scope.dart';

/// Service name the general face is published under.
const String kGeneralSettingsServiceName = 'settings.general';

/// Namespace carrying the locale preference (React `locale` row).
const String kLocaleNamespace = 'locale';

/// Field carrying the persisted locale preference.
const String kLocalePreferenceField = 'preference';

/// Namespace carrying theme appearance preferences (React `ui-theme` row).
const String kThemeNamespace = 'ui-theme';

/// Both General-section scopes plus the shared refresh they ride.
class GeneralSettingsService extends ChangeNotifier {
  /// Creates the service around a connection-backed describe face.
  GeneralSettingsService(ConnectionClient client)
    : language = SettingsScope<Object?>(
        face: SettingsRpcFace(client),
        namespace: kLocaleNamespace,
      ),
      appearance = SettingsScope<Object?>(
        face: SettingsRpcFace(client),
        namespace: kThemeNamespace,
      ) {
    language.subscribe((_) => notifyListeners());
    appearance.subscribe((_) => notifyListeners());
  }

  /// Language preference scope (`locale` namespace).
  final SettingsScope<Object?> language;

  /// Appearance preference scope (`ui-theme` namespace).
  final SettingsScope<Object?> appearance;

  /// Current persisted language preference (null while loading/unserved).
  String? get languagePreference {
    final value = language.snapshot.value;
    if (value is Map) {
      final raw = value[kLocalePreferenceField];
      if (raw is String) return raw;
    }
    return null;
  }

  /// Persists the language preference.
  Future<void> setLanguage(String id) =>
      language.set(kLocalePreferenceField, id);

  /// Refreshes both scopes from the shared describe answer.
  Future<void> load() async {
    await Future.wait([
      language.refreshFromDescribe(),
      appearance.refreshFromDescribe(),
    ]);
  }
}
