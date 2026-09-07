import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show
        LocaleService,
        localeServiceProvider,
        LocaleBindOnWidgetRef,
        kSettingsLocaleNamespace,
        kCommonNamespace;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/ds_select.dart';
import '../../locale/locale_preference.dart';

// ---------------------------------------------------------------------------
// Locale store — mirrors `createLanguageRowStore` in
// `packages/client/locale/src/client/settings-store.ts`
// ---------------------------------------------------------------------------

/// One selectable locale row (id + self-described label).
class LanguageOptionRow {
  const LanguageOptionRow({required this.id, required this.label});

  final String id;
  final String label;
}

/// Store state mirrored from the locale snapshot.
class LanguageRowState {
  const LanguageRowState({
    this.active = '',
    this.options = const [],
    this.revision = -1,
    this.loading = false,
    this.error,
  });

  final String active;
  final List<LanguageOptionRow> options;
  final int revision;
  final bool loading;
  final String? error;

  LanguageRowState copyWith({
    String? active,
    List<LanguageOptionRow>? options,
    int? revision,
    bool? loading,
    String? error,
  }) => LanguageRowState(
    active: active ?? this.active,
    options: options ?? this.options,
    revision: revision ?? this.revision,
    loading: loading ?? this.loading,
    error: error,
  );
}

/// Controller for [LanguageRowState] — mirrors `createLanguageRowStore` factory.
///
/// Reads the active locale from `settings.describe` (`locale` namespace) and
/// writes via `settings.mutate`. The `revision` guard prevents stale syncs
/// from overwriting newer snapshots, matching `revision <= d.revision` in
/// the React store.
class LanguageRowController extends Notifier<LanguageRowState> {
  @override
  LanguageRowState build() => const LanguageRowState(
    options: [
      LanguageOptionRow(id: 'en', label: 'English'),
      LanguageOptionRow(id: 'zh', label: '中文'),
    ],
  );

  /// Sync from a remote snapshot — respects revision monotonicity.
  void sync(String active, List<LanguageOptionRow> options, int revision) {
    if (revision <= state.revision) return;
    state = state.copyWith(
      active: active,
      options: options,
      revision: revision,
    );
  }

  /// Load the locale preference from the Host settings document.
  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final section = localeSectionFromDescribe(describe);
      // Empty preference means delegating to the app default; keep active
      // as-is so DsSelect shows placeholder when unset.
      sync(section?.preference ?? '', state.options, section?.revision ?? 0);
      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Switch the UI language to [id] — the React `setLocale` order: publish
  /// the snapshot change through the activated [LocaleService] first (mounted
  /// bind consumers switch immediately), then persist via `settings.mutate`;
  /// persistence is a consequence, not the switch mechanism. On failure both
  /// sides roll back — the service republishes the previous id and the row's
  /// optimistic update is undone.
  Future<String?> setLocale(String id) async {
    final client = ref.read(connectionClientProvider);
    final LocaleService service = ref.read(localeServiceProvider);
    final prevActive = state.active;
    final prevRevision = state.revision;
    final prevServiceLocale = service.locale;
    state = state.copyWith(
      active: id,
      revision: state.revision + 1,
      error: null,
    );
    try {
      service.setLocale(id);
      // Revision guard from the last describe fences the durable write.
      final describe = await client.settingsDescribe();
      final section = localeSectionFromDescribe(describe);
      await client.settingsMutate(
        ns: kLocaleSettingsNamespace,
        ops: [
          {
            'op': 'set',
            'path': [kLocalePreferenceField],
            'value': id,
          },
        ],
        expectedRevision: section?.revision,
      );
      // Re-sync from Host after mutate to confirm revision
      await load();
      return null;
    } catch (e) {
      // Roll back BOTH sides of the optimistic switch.
      if (service.locale != prevServiceLocale) {
        try {
          service.setLocale(prevServiceLocale);
        } on ArgumentError {
          // Previous id left the registry mid-switch (its dictionaries were
          // disposed): keep the failed target rather than masking the write
          // error this rollback is inside of.
        }
      }
      state = state.copyWith(
        active: prevActive,
        revision: prevRevision,
        error: e.toString(),
      );
      return e.toString();
    }
  }
}

/// Global language row provider. Override in `ProviderScope` for tests.
final languageRowProvider =
    NotifierProvider<LanguageRowController, LanguageRowState>(
      LanguageRowController.new,
    );

// ---------------------------------------------------------------------------
// Widget — mirrors `LanguageRow.tsx`
// ---------------------------------------------------------------------------

/// Language preference row registered into the General section item slot
/// (figma 501:30011 'Setting-Cell'): title + selector pill opening the locale
/// menu. Registered by this package — the locale feature owns its own
/// settings surface.
///
/// Figma `Setting-Cell`: gap 8, pad 16/0, hairline separator;
/// Selector pill: h36 r18, fill `bgModulePlatform`, pad 0/14, gap 12,
/// radius [DswTokens.radiusMd] (8) for dropdown menu, hover
/// `interactiveBgHover`, chevron 14.
///
/// Uses [DsSelect] for the dropdown (MenuAnchor with rAF flip), matching the
/// React `Menu` with `portal` and `align="end"` contract. Calls
/// [LanguageRowController.setLocale] on selection, mirroring
/// `LanguageRowInjected.setLocale`.
class LanguageRow extends ConsumerStatefulWidget {
  const LanguageRow({super.key});

  @override
  ConsumerState<LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends ConsumerState<LanguageRow> {
  @override
  void initState() {
    super.initState();
    // Load once like React `describeFace.ensure()` in apply.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(languageRowProvider);
      if (s.revision == -1 && !s.loading) {
        ref.read(languageRowProvider.notifier).load();
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
    final LanguageRowState rowState = ref.watch(languageRowProvider);
    final LanguageRowController controller = ref.read(
      languageRowProvider.notifier,
    );
    // The locale feature owns its settings copy (React registers
    // `settings.locale` in the same package as the service; the Dart service
    // seeds it).
    final String title = ref.bindLocale(kSettingsLocaleNamespace)(
      'language.title',
    );

    // When no preference set, show placeholder; activeLabel mirrors React activeLabel derivation.
    final String? displayValue = rowState.active.isEmpty
        ? null
        : rowState.active;

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
                  if (rowState.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      rowState.error!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        height:
                            DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                        color: aliases.stateErrorPrimary,
                        fontFamily: 'SF Pro',
                        fontFamilyFallback: DswTokens.fontFamilyFallback,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Flexible + maxWidth mirrors the React selector pill (content-
          // hugging, aligned end): DsSelect's root Column stretches, so it
          // needs bounded width — a bare Row child gets unbounded width and
          // crashes at layout.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: DsSelect(
                value: displayValue,
                placeholder: ref.bindLocale(kCommonNamespace)(
                  rowState.loading ? 'loading' : 'select',
                ),
                // Map options to DsSelectOption — id maps to value, label to label
                options: [
                  for (final o in rowState.options)
                    DsSelectOption(value: o.id, label: o.label),
                ],
                errorText: null,
                onChanged: (String next) async {
                  final Color errorBg = aliases.stateErrorPrimary;
                  final err = await controller.setLocale(next);
                  if (!mounted) return;
                  if (err != null) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err), backgroundColor: errorBg),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
