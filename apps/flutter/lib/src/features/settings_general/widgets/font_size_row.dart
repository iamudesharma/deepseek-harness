import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../theme/app_theme.dart';
import '../../../plugins/settings/children/general/general_settings_plugin.dart'
    show kSettingsNamespace;

// ---------------------------------------------------------------------------
// Font-size store — mirrors `createFontSizeRowStore` in
// `packages/client/ui-theme/src/client/settings-store.ts`
// ---------------------------------------------------------------------------

/// Settings namespace owned by the theme plugin (React `THEME_SETTINGS_NAMESPACE`).
const String kThemeSettingsNamespace = 'ui-theme';

/// Field carrying the conversation content font size (React `FONT_SIZE_FIELD`).
const String kFontSizeField = 'fontSize';

/// Minimum content font size in px (React `FONT_SIZE_MIN`).
const int kFontSizeMin = 12;

/// Maximum content font size in px (React `FONT_SIZE_MAX`).
const int kFontSizeMax = 17;

/// Default content font size in px (React `DEFAULT_FONT_SIZE`).
const int kDefaultFontSize = 14;

/// Store state mirrored from the theme snapshot's font size.
class FontSizeRowState {
  const FontSizeRowState({
    this.fontSize = kDefaultFontSize,
    this.revision = -1,
    this.loading = false,
    this.error,
  });

  final int fontSize;
  final int revision;
  final bool loading;
  final String? error;

  FontSizeRowState copyWith({
    int? fontSize,
    int? revision,
    bool? loading,
    String? error,
  }) => FontSizeRowState(
    fontSize: fontSize ?? this.fontSize,
    revision: revision ?? this.revision,
    loading: loading ?? this.loading,
    error: error,
  );
}

/// Controller for [FontSizeRowState] — mirrors `createFontSizeRowStore`.
class FontSizeRowController extends Notifier<FontSizeRowState> {
  @override
  FontSizeRowState build() => const FontSizeRowState();

  /// Sync from a remote snapshot — respects revision monotonicity.
  void sync(int fontSize, int revision) {
    if (revision <= state.revision) return;
    state = state.copyWith(fontSize: fontSize, revision: revision);
  }

  Map<String, dynamic>? _themeSection(Map<String, dynamic> describe) {
    final namespaces = describe['namespaces'];
    if (namespaces is List) {
      for (final entry in namespaces) {
        if (entry is Map && entry['ns'] == kThemeSettingsNamespace) {
          return entry.cast<String, dynamic>();
        }
      }
      return null;
    }
    if (namespaces is Map) {
      final entry = namespaces[kThemeSettingsNamespace];
      if (entry is Map) return entry.cast<String, dynamic>();
    }
    return null;
  }

  /// Load the persisted font size from the Host settings document.
  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final section = _themeSection(describe);
      final value = section?['value'] as Map<String, dynamic>?;
      final raw = value?[kFontSizeField];
      final size = raw is int && raw >= kFontSizeMin && raw <= kFontSizeMax
          ? raw
          : kDefaultFontSize;
      sync(size, section?['revision'] as int? ?? 0);
      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Change the content font size — mirrors the theme service write: the
  /// displayed value follows the persisted setting, never the click echo,
  /// so a failed write rolls back to the last confirmed value.
  Future<String?> setFontSize(int px) async {
    if (px < kFontSizeMin || px > kFontSizeMax) {
      final error = 'RangeError: $px outside $kFontSizeMin..$kFontSizeMax';
      state = state.copyWith(error: error);
      return error;
    }
    final client = ref.read(connectionClientProvider);
    final prevSize = state.fontSize;
    final prevRevision = state.revision;
    state = state.copyWith(fontSize: px, error: null);
    try {
      final describe = await client.settingsDescribe();
      final section = _themeSection(describe);
      await client.settingsMutate(
        ns: kThemeSettingsNamespace,
        ops: [
          {'op': 'set', 'path': [kFontSizeField], 'value': px},
        ],
        expectedRevision: section?['revision'] as int?,
      );
      await load();
      return null;
    } catch (e) {
      state = state.copyWith(
        fontSize: prevSize,
        revision: prevRevision,
        error: e.toString(),
      );
      return e.toString();
    }
  }
}

/// Global font-size row provider. Override in `ProviderScope` for tests.
final fontSizeRowProvider =
    NotifierProvider<FontSizeRowController, FontSizeRowState>(
      FontSizeRowController.new,
    );

// ---------------------------------------------------------------------------
// Widget — mirrors `FontSizeRow.tsx`
// ---------------------------------------------------------------------------

/// Font-size preference row: title + description + stepper pill (value with
/// up/down arrows, clamped to 12..17) + px unit label. The arrows disable at
/// the bounds, mirroring the React `disabled` gates.
class FontSizeRow extends ConsumerStatefulWidget {
  const FontSizeRow({super.key});

  @override
  ConsumerState<FontSizeRow> createState() => _FontSizeRowState();
}

class _FontSizeRowState extends ConsumerState<FontSizeRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(fontSizeRowProvider);
      if (s.revision == -1 && !s.loading) {
        ref.read(fontSizeRowProvider.notifier).load();
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
    final FontSizeRowState rowState = ref.watch(fontSizeRowProvider);
    final FontSizeRowController controller = ref.read(
      fontSizeRowProvider.notifier,
    );
    final t = ref.bindLocale(kSettingsNamespace);

    Future<void> step(int delta) async {
      final err = await controller.setFontSize(rowState.fontSize + delta);
      if (!mounted || err == null) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: aliases.stateErrorPrimary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: aliases.borderL2, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('fontSize.title'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                      fontWeight: FontWeight.w400,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('fontSize.description'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelTertiary,
                    ),
                  ),
                  if (rowState.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      rowState.error!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.stateErrorPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${rowState.fontSize}',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w500,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: rowState.fontSize >= kFontSizeMax
                        ? null
                        : () => step(1),
                    child: Semantics(
                      button: true,
                      enabled: rowState.fontSize < kFontSizeMax,
                      label: t('fontSize.increase'),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 16,
                        color: rowState.fontSize >= kFontSizeMax
                            ? aliases.labelTertiary.withValues(alpha: 0.4)
                            : aliases.labelSecondary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: rowState.fontSize <= kFontSizeMin
                        ? null
                        : () => step(-1),
                    child: Semantics(
                      button: true,
                      enabled: rowState.fontSize > kFontSizeMin,
                      label: t('fontSize.decrease'),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: rowState.fontSize <= kFontSizeMin
                            ? aliases.labelTertiary.withValues(alpha: 0.4)
                            : aliases.labelSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Text(
                t('fontSize.unit'),
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
