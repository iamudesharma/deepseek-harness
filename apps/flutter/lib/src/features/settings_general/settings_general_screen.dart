import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../theme/app_theme.dart';
import 'widgets/appearance_row.dart';
import 'widgets/language_row.dart';

/// SettingsGeneralScreen — Flutter port of the General section column
/// (`GeneralSection.tsx` + `LanguageRow.tsx` + `AppearanceRow.tsx`).
///
/// Renders the two feature-owned `settings.general.item` contributions:
/// Language (locale) and Appearance (theme), each with its own
/// `create*Store` mirror (`languageRowProvider` / `appearanceRowProvider`)
/// and `settings.mutate` write path. The chrome mirrors
/// `GeneralSection.module.css` section column: no extra page shell here — the
/// caller (e.g. [SettingsScreen] General tab) provides padding.
///
/// Typert: no dropped typert — both rows read `settings.describe` and write
/// via `settings.mutate` through [ConnectionClient].
class SettingsGeneralScreen extends ConsumerWidget {
  const SettingsGeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        Text(
          'General',
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
            letterSpacing: 0.2,
            fontFamily: 'SF Pro',
            fontFamilyFallback: DswTokens.fontFamilyFallback,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Language and appearance for this device.',
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
            color: aliases.labelTertiary,
            fontFamily: 'SF Pro',
            fontFamilyFallback: DswTokens.fontFamilyFallback,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
        // Section column — like GeneralSection, renders item slot contributions
        // Includes the `settings.general.item` permission preset row (React PermissionRow)
        // — inline row, not a page, with Menu dropdown and RiskConfirmation for Full access.
        Container(
          decoration: BoxDecoration(
            color: aliases.bgLayer2,
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            border: Border.all(color: aliases.borderL2),
            boxShadow: DswTokens.shadowLv1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [LanguageRow(), AppearanceRow(), PermissionPresetRow()],
          ),
        ),
        const SizedBox(height: DswTokens.spaceLg),
        Text(
          'Permission preset default is persisted via settings.describe / mutate (permission namespace, defaultPreset field) with revision guard, mirroring PermissionPresetSettingsController — inline row, not a page.',
          style: TextStyle(
            fontSize: 11,
            height: 14 / 11,
            color: aliases.labelCaption,
            fontFamily: 'SF Pro',
            fontFamilyFallback: DswTokens.fontFamilyFallback,
          ),
        ),
        const SizedBox(height: 8),
        // Inline row parity — React's `PermissionRow` is a `settings.general.item` contribution, not a separate page.
        // The *page* shell for permission presets would be `SettingsScreen` tab, but the host row itself lives
        // inside the General section column as a Menu + RiskConfirmation — this preserves row-vs-page behavior.
        const SizedBox(height: DswTokens.spaceSm),
        Text(
          'Language and Appearance are wired to the Host settings document '
          '(locale / ui-theme namespaces) via settings.describe + settings.mutate, '
          'with revision-guarded stores mirroring createLanguageRowStore / createAppearanceRowStore.',
          style: TextStyle(
            fontSize: 11,
            height: 14 / 11,
            color: aliases.labelCaption,
            fontFamily: 'SF Pro',
            fontFamilyFallback: DswTokens.fontFamilyFallback,
          ),
        ),
      ],
    );
  }
}

/// Permission preset default row — inline `settings.general.item`, not a page.
///
/// React `PermissionRow` persists `defaultPreset` for sessions created later
/// through the host Settings API (namespace `permission`, field `defaultPreset`,
/// revision-fenced). The selector is a `Menu` anchored on a small pill button;
/// `danger-full-access` is gated by `RiskConfirmation` (acknowledge checkbox
/// before Enable). Host-absent (`unavailable`) renders null in React; here we
/// hide the row while loading/unavailable and keep the placeholder description.
class PermissionPresetRow extends ConsumerStatefulWidget {
  const PermissionPresetRow({super.key});
  @override
  ConsumerState<PermissionPresetRow> createState() =>
      _PermissionPresetRowState();
}

class _PermissionState {
  const _PermissionState({
    this.currentValue,
    this.options = const [],
    this.status = 'loading',
    this.error,
    this.writable = true,
  });
  final String? currentValue;
  final List<_PermOption> options;
  final String status; // loading|ready|unavailable|error|saving
  final String? error;
  final bool writable;
}

class _PermOption {
  const _PermOption({
    required this.id,
    required this.label,
    this.danger = false,
  });
  final String id;
  final String label;
  final bool danger;
}

class _PermissionPresetRowState extends ConsumerState<PermissionPresetRow> {
  _PermissionState _state = const _PermissionState();
  bool _open = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(connectionClientProvider);
    setState(() => _state = const _PermissionState(status: 'loading'));
    try {
      final describe = await client.settingsDescribe();
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? permNs;
      for (final ns in namespaces) {
        if (ns['ns'] == 'permission') {
          permNs = ns;
          break;
        }
      }
      if (permNs == null) {
        // Host has no permission namespace — row stays null like React unavailable.
        setState(
          () => _state = const _PermissionState(
            status: 'unavailable',
            writable: false,
          ),
        );
        return;
      }
      final value = permNs['value'] as Map<String, dynamic>?;
      final current = value?['defaultPreset'] as String?;
      // Options mirror React's schema union — without settingsSchema face we carry the known presets locally.
      final options = const [
        _PermOption(id: 'ask', label: 'Ask (approval)'),
        _PermOption(id: 'plan', label: 'Plan mode'),
        _PermOption(id: 'edit', label: 'Edit'),
        _PermOption(
          id: 'danger-full-access',
          label: 'Full access',
          danger: true,
        ),
      ];
      final resolved = current != null && options.any((o) => o.id == current)
          ? current
          : options.first.id;
      setState(
        () => _state = _PermissionState(
          currentValue: resolved,
          options: options,
          status: 'ready',
          writable: permNs!['writable'] as bool? ?? true,
        ),
      );
    } catch (e) {
      setState(
        () => _state = _PermissionState(
          status: 'error',
          error: e.toString(),
          options: const [
            _PermOption(id: 'ask', label: 'Ask (approval)'),
            _PermOption(id: 'edit', label: 'Edit'),
          ],
        ),
      );
    }
  }

  Future<void> _select(String id) async {
    if (id == 'danger-full-access') {
      final confirmed = await _confirmFullAccess();
      if (confirmed != true) return;
    }
    final prev = _state;
    setState(
      () => _state = _PermissionState(
        currentValue: prev.currentValue,
        options: prev.options,
        status: 'saving',
        writable: prev.writable,
      ),
    );
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final namespaces = (describe['namespaces'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? permNs;
      for (final ns in namespaces) {
        if (ns['ns'] == 'permission') {
          permNs = ns;
          break;
        }
      }
      final rev = permNs?['revision'] as int?;
      await client.settingsMutate(
        ns: 'permission',
        ops: [
          {
            'op': 'set',
            'path': ['defaultPreset'],
            'value': id,
          },
        ],
        expectedRevision: rev,
      );
      await _load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Default preset "$id" saved')));
    } catch (e) {
      setState(
        () => _state = _PermissionState(
          currentValue: prev.currentValue,
          options: prev.options,
          status: 'error',
          error: e.toString(),
          writable: prev.writable,
        ),
      );
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save preset: $e')));
    }
  }

  Future<bool?> _confirmFullAccess() {
    bool acknowledged = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Enable Full access?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Full access reduces confirmation steps and grants full file access. Use only in trusted workspaces.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: acknowledged,
                      onChanged: (v) =>
                          setState(() => acknowledged = v ?? false),
                    ),
                    const Expanded(child: Text('I understand the risk')),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: acknowledged ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Enable'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_state.status == 'unavailable') return const SizedBox.shrink();
    final theme = Theme.of(context);
    final aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final selected =
        _state.options.where((o) => o.id == _state.currentValue).firstOrNull ??
        _state.options.firstOrNull;
    final label =
        selected?.label ??
        (_state.status == 'loading' ? 'Loading…' : 'Unavailable');
    final busy = _state.status == 'loading' || _state.status == 'saving';
    final description =
        _state.error ??
        'Default permission mode for new sessions. Current-session switches stay on /permission.';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: aliases.borderL1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permission preset',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: _state.error == null
                        ? aliases.labelTertiary
                        : aliases.stateErrorPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            enabled: !busy && _state.writable && _state.options.isNotEmpty,
            offset: const Offset(0, 32),
            color: aliases.specificMenu,
            onSelected: (id) => _select(id),
            onOpened: () => setState(() => _open = true),
            onCanceled: () => setState(() => _open = false),
            itemBuilder: (ctx) => [
              for (final opt in _state.options)
                PopupMenuItem<String>(
                  value: opt.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt.label,
                          style: TextStyle(
                            color: opt.danger
                                ? aliases.stateErrorPrimary
                                : aliases.labelPrimary,
                            fontWeight: _state.currentValue == opt.id
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (_state.currentValue == opt.id)
                        Icon(
                          Icons.check,
                          size: 14,
                          color: aliases.stateBusinessPrimary,
                        ),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: aliases.specificSelector,
                borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                border: Border.all(color: aliases.borderL2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
