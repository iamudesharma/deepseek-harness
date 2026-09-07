/// Theme runtime service mirrored from
/// `packages/client/ui-theme/src/client/index.ts` (`ThemeRuntime`).
///
/// Owns the live preference (`light`/`dark`/`system`), resolves `system`
/// through the platform brightness, publishes immutable snapshots with a
/// monotonic revision, and supports override-token layers (later layers win
/// per token; every override must supply both palette modes so a value never
/// goes illegible across a scheme switch). Presentation consumes snapshots;
/// this service never touches widgets.
library;

import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance.dart';

/// Which base palette a theme builds on. The presenter switches the active
/// scheme from this field — never from the theme id.
enum ColorSchemeBase { light, dark }

/// One selectable theme: id, base palette semantics, alias-token overrides.
@immutable
class ThemeDefinition {
  /// Creates an immutable theme.
  const ThemeDefinition({
    required this.id,
    required this.colorScheme,
    this.tokens = const {},
  });

  /// Theme id (the setTheme argument for concrete themes).
  final String id;

  /// Base palette backing this theme.
  final ColorSchemeBase colorScheme;

  /// Alias-layer overrides keyed by `--dsw-alias-*` variable name.
  final Map<String, String> tokens;

  @override
  bool operator ==(Object other) =>
      other is ThemeDefinition &&
      other.id == id &&
      other.colorScheme == colorScheme &&
      const MapEquality<String, String>().equals(other.tokens, tokens);

  @override
  int get hashCode => Object.hash(
    id,
    colorScheme,
    const MapEquality<String, String>().hash(tokens),
  );
}

/// Immutable theme state published on every change.
@immutable
class ThemeSnapshot {
  /// Creates a snapshot.
  const ThemeSnapshot({
    required this.preference,
    required this.active,
    required this.themes,
    required this.revision,
  });

  /// The persisted preference (may be `system`).
  final AppThemePreference preference;

  /// The resolved active theme with override layers folded in.
  final ThemeDefinition active;

  /// Registered themes in registration order.
  final List<ThemeDefinition> themes;

  /// Monotonic change counter (registry, preference, or OS scheme change).
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ThemeSnapshot &&
      other.preference == preference &&
      other.active == active &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(preference, active, revision);
}

/// Both builtin themes, mirroring `BUILTIN_THEMES`: light and dark bases with
/// empty override layers.
final List<ThemeDefinition> kBuiltinThemes = List.unmodifiable([
  const ThemeDefinition(id: 'light', colorScheme: ColorSchemeBase.light),
  const ThemeDefinition(id: 'dark', colorScheme: ColorSchemeBase.dark),
]);

/// Theme runtime over [AppThemePreference]: registry + resolved snapshot +
/// change notifications. The Riverpod appearance controller remains the UI's
/// write seat; this service is what plugin consumers inject as `'theme'`.
class ThemeRuntime {
  /// Creates the runtime seeded with the current UI preference.
  ThemeRuntime({
    AppThemePreference initialPreference = AppThemePreference.system,
  }) : _preference = initialPreference {
    _recompute();
    // OS scheme changes while preference == system re-resolve the snapshot.
    PlatformDispatcher.instance.onPlatformBrightnessChanged =
        _onPlatformBrightnessChanged;
  }

  AppThemePreference _preference;
  final List<ThemeDefinition> _themes = [...kBuiltinThemes];
  final Map<String, ({String light, String dark})> _overrides = {};
  int _revision = 1; // First publication of the initial snapshot.
  late ThemeSnapshot _snapshot;
  Brightness? _lastSystemBrightness =
      PlatformDispatcher.instance.platformBrightness;

  final List<void Function(ThemeSnapshot)> _listeners = [];

  /// The current immutable snapshot.
  ThemeSnapshot get snapshot => _snapshot;

  /// Subscribes to changes (the `theme/change` analog); returns an unsubscriber.
  VoidCallback onChanged(void Function(ThemeSnapshot snapshot) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Sets the persisted preference; no-op when unchanged.
  void setPreference(AppThemePreference preference) {
    if (_preference == preference) return;
    _preference = preference;
    _bump();
  }

  /// Selects a concrete registered theme by id and pins its base scheme as
  /// the effective preference (light→light, dark→dark), mirroring setTheme.
  void setTheme(String id) {
    final theme = _themes.where((t) => t.id == id).firstOrNull;
    if (theme == null) {
      throw ArgumentError.value(id, 'id', 'theme is not registered');
    }
    setPreference(
      theme.colorScheme == ColorSchemeBase.light
          ? AppThemePreference.light
          : AppThemePreference.dark,
    );
  }

  /// Registers an additional theme; duplicate ids throw. Later registration
  /// order is preserved in [ThemeSnapshot.themes].
  void registerTheme(ThemeDefinition definition) {
    if (_themes.any((t) => t.id == definition.id)) {
      throw ArgumentError.value(
        definition.id,
        'definition.id',
        'theme already registered',
      );
    }
    _themes.add(definition);
    _bump();
  }

  /// Applies one override-layer entry. Both palette modes are mandatory.
  void overrideToken(
    String name, {
    required String light,
    required String dark,
  }) {
    _overrides[name] = (light: light, dark: dark);
    _bump();
  }

  void _onPlatformBrightnessChanged() {
    final brightness = PlatformDispatcher.instance.platformBrightness;
    if (_lastSystemBrightness == brightness) return;
    _lastSystemBrightness = brightness;
    if (_preference == AppThemePreference.system) _bump();
  }

  void _bump() {
    _revision++;
    _recompute();
    for (final listener in List.of(_listeners)) {
      listener(_snapshot);
    }
  }

  void _recompute() {
    final systemDark = _lastSystemBrightness == Brightness.dark;
    final dark =
        _preference == AppThemePreference.dark ||
        (_preference == AppThemePreference.system && systemDark);
    final baseId = dark ? 'dark' : 'light';
    final foldedTokens = <String, String>{
      for (final entry in _overrides.entries)
        entry.key: dark ? entry.value.dark : entry.value.light,
    };
    _snapshot = ThemeSnapshot(
      preference: _preference,
      active: ThemeDefinition(
        id: baseId,
        colorScheme: dark ? ColorSchemeBase.dark : ColorSchemeBase.light,
        tokens: foldedTokens,
      ),
      themes: List.unmodifiable(_themes),
      revision: _revision,
    );
  }
}

/// Provides the app-wide [ThemeRuntime], two-way bridged to the existing
/// appearance controller so current UI keeps working while plugin consumers
/// inject the `'theme'` service. Both directions terminate because each side
/// no-ops on an unchanged preference.
final themeRuntimeProvider = Provider<ThemeRuntime>((ref) {
  final runtime = ThemeRuntime(initialPreference: ref.read(appearanceProvider));

  // UI writes → runtime.
  ref.listen(appearanceProvider, (_, next) => runtime.setPreference(next));

  // Service writes → UI seat.
  runtime.onChanged((snapshot) {
    if (ref.read(appearanceProvider) != snapshot.preference) {
      ref.read(appearanceProvider.notifier).setTheme(snapshot.preference);
    }
  });

  return runtime;
});
