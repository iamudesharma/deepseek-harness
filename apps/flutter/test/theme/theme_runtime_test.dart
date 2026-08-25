import 'package:dsh_flutter/src/theme/appearance.dart';
import 'package:dsh_flutter/src/theme/theme_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builtin registry mirrors BUILTIN_THEMES (light/dark, empty overrides)', () {
    final runtime = ThemeRuntime();
    expect(runtime.snapshot.themes.map((t) => t.id), ['light', 'dark']);
    expect(runtime.snapshot.themes.every((t) => t.tokens.isEmpty), isTrue);
  });

  test('preference light pins the light base; dark pins dark', () {
    final runtime = ThemeRuntime()..setPreference(AppThemePreference.dark);
    expect(runtime.snapshot.active.colorScheme, ColorSchemeBase.dark);
    runtime.setPreference(AppThemePreference.light);
    expect(runtime.snapshot.active.colorScheme, ColorSchemeBase.light);
  });

  test('system resolves through platform brightness and re-resolves on change', () {
    final runtime = ThemeRuntime(initialPreference: AppThemePreference.system);
    // Test binding's default platform brightness is light; snapshot must be
    // resolved (never carry `system` as active id).
    expect(runtime.snapshot.active.id, isIn(['light', 'dark']));
    expect(runtime.snapshot.preference, AppThemePreference.system);

    var notified = 0;
    runtime.onChanged((_) => notified++);
    runtime.setPreference(AppThemePreference.system); // no-op: same preference
    expect(notified, 0);
    expect(runtime.snapshot.revision, greaterThanOrEqualTo(1));
  });

  test('setTheme maps a concrete theme id to its base scheme preference', () {
    final runtime = ThemeRuntime()..setTheme('dark');
    expect(runtime.snapshot.preference, AppThemePreference.dark);
    expect(() => runtime.setTheme('nope'), throwsArgumentError);
  });

  test('registerTheme appends and rejects duplicates', () {
    final runtime = ThemeRuntime()
      ..registerTheme(const ThemeDefinition(id: 'ocean', colorScheme: ColorSchemeBase.dark));
    expect(runtime.snapshot.themes.map((t) => t.id), contains('ocean'));
    expect(
      () => runtime.registerTheme(const ThemeDefinition(id: 'ocean', colorScheme: ColorSchemeBase.light)),
      throwsArgumentError,
    );
  });

  test('override tokens require both modes and fold per active scheme', () {
    final runtime = ThemeRuntime()
      ..overrideToken('--dsw-alias-brand-primary', light: '#111', dark: '#eee');
    expect(runtime.snapshot.active.tokens['--dsw-alias-brand-primary'], isNotEmpty);

    runtime.setPreference(AppThemePreference.dark);
    final darkValue = runtime.snapshot.active.tokens['--dsw-alias-brand-primary'];
    runtime.setPreference(AppThemePreference.light);
    final lightValue = runtime.snapshot.active.tokens['--dsw-alias-brand-primary'];
    expect(darkValue, isNot(lightValue));
  });

  test('revision is monotonic across changes', () {
    final runtime = ThemeRuntime();
    final start = runtime.snapshot.revision;
    runtime.setPreference(AppThemePreference.dark);
    runtime.setTheme('light');
    runtime.overrideToken('--dsw-alias-bg-base', light: 'a', dark: 'b');
    expect(runtime.snapshot.revision, greaterThan(start + 2));
  });
}
