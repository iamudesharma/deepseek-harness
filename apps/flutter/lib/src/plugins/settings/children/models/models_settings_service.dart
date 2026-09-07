/// Models settings service — the `ui-settings-models` faces sliced to the
/// Dart settings seam. The full provider-editor store (llm.providers +
/// credentials + namespace rows) stays with the existing screen store until
/// re-homed at integration; this service owns what React binds to a
/// per-namespace scope here: the product onboarding acknowledgement
/// (`ui-onboarding.welcomeNoticeVersion`).
library;

import 'package:flutter/foundation.dart';

import '../../../../core/connection/connection_client.dart';
import '../../../../core/settings/settings_scope.dart';

/// Service name the models face is published under.
const String kModelsSettingsServiceName = 'settings.models';

/// Durable settings namespace for product-wide GUI onboarding facts
/// (mirrors ui-settings-models/src/onboarding-copy.ts).
const String kWelcomeNoticeNamespace = 'ui-onboarding';

/// Field storing the last welcome notice version the user acknowledged.
const String kWelcomeNoticeAckField = 'welcomeNoticeVersion';

/// Bump only when the notice changes materially (mirrors WELCOME_NOTICE_VERSION).
const String kWelcomeNoticeVersion = '2026-08-13.1';

/// Welcome-notice acknowledgement scope face: whether the shipped notice was
/// acknowledged, and the acknowledge write.
class WelcomeNoticeScope extends ChangeNotifier {
  /// Creates the scope over a connection-backed describe face.
  WelcomeNoticeScope(ConnectionClient client)
    : _scope = SettingsScope<Object?>(
        face: SettingsRpcFace(client),
        namespace: kWelcomeNoticeNamespace,
      ) {
    _scope.subscribe((_) => notifyListeners());
  }

  final SettingsScope<Object?> _scope;

  /// Whether the current notice version needs showing.
  bool get needsShow {
    final value = _scope.snapshot.value;
    if (value is Map) {
      return value[kWelcomeNoticeAckField] != kWelcomeNoticeVersion;
    }
    return true;
  }

  /// Persists the acknowledgement for the shipped version.
  Future<void> acknowledge() =>
      _scope.set(kWelcomeNoticeAckField, kWelcomeNoticeVersion);

  /// Refreshes from the host settings document.
  Future<void> load() => _scope.refreshFromDescribe();
}

/// The models settings page service: onboarding scope today; provider rows
/// keep their existing wire-backed store.
class ModelsSettingsService extends ChangeNotifier {
  /// Creates the service around one client.
  ModelsSettingsService(ConnectionClient client)
    : welcome = WelcomeNoticeScope(client);

  /// Product onboarding acknowledgement scope (`ui-onboarding`).
  final WelcomeNoticeScope welcome;
}
