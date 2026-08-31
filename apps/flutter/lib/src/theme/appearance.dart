import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme preference persisted by the Appearance row.
///
/// Mirrors `ThemePreference` in `packages/client/ui-theme/src/theme-settings.ts`
/// (`light` | `dark` | `system`).
enum AppThemePreference {
  /// Use light theme.
  light,

  /// Use dark theme.
  dark,

  /// Follow system setting.
  system,
}

/// Convert [AppThemePreference] to Flutter's [ThemeMode].
extension AppThemePreferenceX on AppThemePreference {
  /// Map to [ThemeMode].
  ThemeMode get themeMode {
    switch (this) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
      case AppThemePreference.system:
        return ThemeMode.system;
    }
  }
}

/// Controller for [AppThemePreference].
///
/// No persistence yet — share via `ProviderScope` overrides for tests,
/// mirroring `createAppearanceRowStore` factory pattern. Persistence can be
/// added via `shared_preferences` without changing the public API.
class AppearanceController extends Notifier<AppThemePreference> {
  @override
  AppThemePreference build() => AppThemePreference.system;

  /// Set the theme preference.
  void setTheme(AppThemePreference preference) {
    if (state == preference) return;
    state = preference;
  }
}

/// Global appearance provider. Override in `ProviderScope` for tests.
final appearanceProvider =
    NotifierProvider<AppearanceController, AppThemePreference>(
      AppearanceController.new,
    );

/// Derived [ThemeMode] provider for `MaterialApp.router`.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(appearanceProvider).themeMode;
});
