import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/appearance.dart';
import '../../../theme/app_theme.dart';
import '../../../plugins/settings/children/general/general_settings_plugin.dart'
    show kSettingsNamespace;

// The Appearance row's copy rides the `settings` namespace registered by
// GeneralSettingsPlugin (the Dart owner of this section's chrome). React
// files it under a separate `settings.theme` namespace owned by ui-theme;
// the Dart ThemePlugin sits in core/bootstrap outside this workstream's
// write authority, so the keys live with the section's own dictionaries.
// ---------------------------------------------------------------------------
// Appearance store — mirrors `createAppearanceRowStore` in
// `packages/client/ui-theme/src/client/settings-store.ts`
// ---------------------------------------------------------------------------

/// Store state mirrored from the theme snapshot.
class AppearanceRowState {
  const AppearanceRowState({
    this.preference = AppThemePreference.system,
    this.revision = -1,
    this.loading = false,
    this.error,
  });

  final AppThemePreference preference;
  final int revision;
  final bool loading;
  final String? error;

  AppearanceRowState copyWith({
    AppThemePreference? preference,
    int? revision,
    bool? loading,
    String? error,
  }) => AppearanceRowState(
    preference: preference ?? this.preference,
    revision: revision ?? this.revision,
    loading: loading ?? this.loading,
    error: error,
  );
}

/// Controller for [AppearanceRowState] — mirrors `createAppearanceRowStore`.
///
/// Reads the persisted preference from `settings.describe` (`ui-theme`
/// namespace) and writes via `settings.mutate`. Selection follows the
/// persisted preference, never the resolved active theme, matching
/// `AppearanceRow.tsx` comment.
class AppearanceRowController extends Notifier<AppearanceRowState> {
  @override
  AppearanceRowState build() => const AppearanceRowState();

  void sync(AppThemePreference preference, int revision) {
    if (revision <= state.revision) return;
    state = state.copyWith(preference: preference, revision: revision);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? themeNs;
      for (final ns in namespaces) {
        if (ns['ns'] == 'ui-theme') {
          themeNs = ns;
          break;
        }
      }
      final value = themeNs?['value'] as Map<String, dynamic>?;
      final raw = value?['preference'] as String?;
      final pref = _parsePreference(raw);
      final revision = themeNs?['revision'] as int? ?? 0;
      sync(pref, revision);
      state = state.copyWith(loading: false);
      // Also sync the global appearanceProvider for live theme
      ref.read(appearanceProvider.notifier).setTheme(pref);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<String?> setTheme(AppThemePreference preference) async {
    final client = ref.read(connectionClientProvider);
    final prev = state.preference;
    final prevRevision = state.revision;
    final nextRevision = state.revision + 1;
    // Optimistic local + global
    state = state.copyWith(
      preference: preference,
      revision: nextRevision,
      error: null,
    );
    ref.read(appearanceProvider.notifier).setTheme(preference);
    try {
      final describe = await client.settingsDescribe();
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? themeNs;
      for (final ns in namespaces) {
        if (ns['ns'] == 'ui-theme') {
          themeNs = ns;
          break;
        }
      }
      final expectedRevision = themeNs?['revision'] as int?;
      await client.settingsMutate(
        ns: 'ui-theme',
        ops: [
          {
            'op': 'set',
            'path': ['preference'],
            'value': preference.name,
          },
        ],
        expectedRevision: expectedRevision,
      );
      await load();
      return null;
    } catch (e) {
      state = state.copyWith(
        preference: prev,
        revision: prevRevision,
        error: e.toString(),
      );
      ref.read(appearanceProvider.notifier).setTheme(prev);
      return e.toString();
    }
  }

  AppThemePreference _parsePreference(String? raw) {
    switch (raw) {
      case 'light':
        return AppThemePreference.light;
      case 'dark':
        return AppThemePreference.dark;
      case 'system':
      default:
        return AppThemePreference.system;
    }
  }
}

final appearanceRowProvider =
    NotifierProvider<AppearanceRowController, AppearanceRowState>(
      AppearanceRowController.new,
    );

// ---------------------------------------------------------------------------
// Widget — mirrors `AppearanceRow.tsx`
// ---------------------------------------------------------------------------

/// Appearance preference row registered into the General section item slot
/// (figma 501:30012 'Frame 2117131228'): title + three preference cubes.
/// Registered by this package — the theme feature owns its own settings
/// surface. Selection follows the persisted preference, never the resolved
/// active theme.
///
/// Cube order and icons (figma 501:30015-30017: Light, Dark, System).
///
/// Styling ports `AppearanceRow.module.css`:
/// - `.group` gap 8 pad 16/0 hairline `borderL2`
/// - `.title` 14/22 w400 labelPrimary
/// - `.cubeRow` flex gap 8 wrap stretch
/// - `.themeCube` 1px borderL2 radius 16 pad 20/32 flex 1 1 180 centered
///   icon-over-label column gap 4 14/22 primary, hover interactiveBgHover
///   when not selected, selected bg `bgModulePlatform` + border
///   `neutralBluish400` (#ADB2B8 static, no alias-layer name) radius
///   [DswTokens.radiusMd] for menu parts and [DswTokens.radiusXl] for cubes.
///
/// Uses [AppThemePreference] via [appearanceRowProvider] + global
/// [appearanceProvider] for live theme, mirroring `useStore(s=>s.preference)`
/// and `setTheme` injected face.
class AppearanceRow extends ConsumerStatefulWidget {
  const AppearanceRow({super.key});

  @override
  ConsumerState<AppearanceRow> createState() => _AppearanceRowState();
}

class _AppearanceRowState extends ConsumerState<AppearanceRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(appearanceRowProvider);
      if (s.revision == -1 && !s.loading) {
        ref.read(appearanceRowProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final AppearanceRowState rowState = ref.watch(appearanceRowProvider);
    // Prefer rowState preference (persisted) but also watch global for system fallback
    final AppThemePreference preference = rowState.preference;

    final Translate t = ref.bindLocale(kSettingsNamespace);
    final String title = t('appearance.title');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: aliases.borderL2, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
              fontWeight: FontWeight.w400,
              color: aliases.labelPrimary,
              fontFamily: 'SF Pro',
              fontFamilyFallback: DswTokens.fontFamilyFallback,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool narrow = constraints.maxWidth < 560;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Cube(
                    id: AppThemePreference.light,
                    label: t('appearance.light'),
                    icon: Icons.light_mode_outlined,
                    selected: preference == AppThemePreference.light,
                    aliases: aliases,
                    onTap: () => _setTheme(AppThemePreference.light),
                    narrow: narrow,
                  ),
                  _Cube(
                    id: AppThemePreference.dark,
                    label: t('appearance.dark'),
                    icon: Icons.dark_mode_outlined,
                    selected: preference == AppThemePreference.dark,
                    aliases: aliases,
                    onTap: () => _setTheme(AppThemePreference.dark),
                    narrow: narrow,
                  ),
                  _Cube(
                    id: AppThemePreference.system,
                    label: t('appearance.system'),
                    icon: Icons.brightness_auto_outlined,
                    selected: preference == AppThemePreference.system,
                    aliases: aliases,
                    onTap: () => _setTheme(AppThemePreference.system),
                    narrow: narrow,
                  ),
                ],
              );
            },
          ),
          if (rowState.error != null) ...[
            const SizedBox(height: 8),
            Text(
              rowState.error!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                color: aliases.stateErrorPrimary,
                fontFamily: 'SF Pro',
                fontFamilyFallback: DswTokens.fontFamilyFallback,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setTheme(AppThemePreference pref) async {
    final err = await ref.read(appearanceRowProvider.notifier).setTheme(pref);
    if (err != null && mounted) {
      final ThemeData theme = Theme.of(context);
      final DswAliases aliases =
          theme.extension<DswThemeExtension>()?.aliases ??
          (theme.brightness == Brightness.dark
              ? DswTokens.darkAliases
              : DswTokens.lightAliases);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: aliases.stateErrorPrimary,
        ),
      );
    }
  }
}

class _Cube extends StatefulWidget {
  const _Cube({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.aliases,
    required this.onTap,
    required this.narrow,
  });

  final AppThemePreference id;
  final String label;
  final IconData icon;
  final bool selected;
  final DswAliases aliases;
  final VoidCallback onTap;
  final bool narrow;

  @override
  State<_Cube> createState() => _CubeState();
}

class _CubeState extends State<_Cube> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = widget.selected
        ? DswTokens.neutralBluish400
        : widget.aliases.borderL2;
    final Color bg = widget.selected
        ? widget.aliases.bgModulePlatform
        : DswTokens.transparent;
    final Color hoverBg = widget.aliases.interactiveBgHover;

    // Flex 1 1 180px — in Wrap we approximate with constrained width
    final double cubeWidth = widget.narrow ? double.infinity : 180;

    Widget cube = Container(
      width: widget.narrow ? double.infinity : null,
      constraints: BoxConstraints(
        minWidth: 180,
        maxWidth: widget.narrow ? double.infinity : 220,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: _hovering && !widget.selected ? hoverBg : bg,
        borderRadius: BorderRadius.circular(DswTokens.radiusXl), // 16
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 16, color: widget.aliases.labelPrimary),
          const SizedBox(height: 4),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
              color: widget.aliases.labelPrimary,
              fontFamily: 'SF Pro',
              fontFamilyFallback: DswTokens.fontFamilyFallback,
            ),
          ),
        ],
      ),
    );

    // Use Material + InkWell for hover/press + radius 16 clipping, matching
    // .themeCube:hover:not(.selected) interactiveBgHover contract.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: DswTokens.transparent,
        borderRadius: BorderRadius.circular(DswTokens.radiusXl),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(DswTokens.radiusXl),
          hoverColor: DswTokens.transparent,
          child: SizedBox(
            width: cubeWidth.isInfinite ? null : cubeWidth,
            child: cube,
          ),
        ),
      ),
    );
  }
}
