import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/settings/settings_scope.dart' show SettingsScopeStatus;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/risk_confirmation.dart';
import '../../../plugins/permission_presets/locales.dart'
    show displayPermissionPreset, kFullAccessPreset, kPermissionSettingsNamespace;
import '../../../plugins/permission_presets/permission_presets_service.dart'
    show PermissionPresetsService;

// ---------------------------------------------------------------------------
// Preset labels live in the permission-presets plugin locales (mirrors
// `presentation.ts`); this file imports the single home.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Widget — mirrors `PermissionRow.tsx`
// ---------------------------------------------------------------------------

/// Permission preset default row — the default preset for subsequently
/// created sessions (current-session switches stay on the composer
/// `/permission` control).
///
/// Options come from the Host schema union via [PermissionPresetsService]
/// (never hardcoded); writes are revision-fenced through the `permission`
/// scope. The row hides itself when the Host serves no `permission`
/// namespace, mirroring React's `unavailable → null`. Selecting the
/// full-access preset opens the risk-confirmation gate first.
class PermissionPresetRow extends ConsumerStatefulWidget {
  const PermissionPresetRow({super.key});

  @override
  ConsumerState<PermissionPresetRow> createState() =>
      _PermissionPresetRowState();
}

class _PermissionPresetRowState extends ConsumerState<PermissionPresetRow> {
  late final PermissionPresetsService _service;
  bool _confirming = false;
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _service = PermissionPresetsService(
      PermissionPresetsService.wireScope(ref.read(connectionClientProvider)),
    );
    _service.addListener(_onService);
    _service.load();
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    _service.dispose();
    super.dispose();
  }

  void _onService() {
    if (!mounted) return;
    // Mirror React's effect: a lost namespace or read-only turn closes the
    // menu and resets the risk gate.
    if (_service.scope.snapshot.status == SettingsScopeStatus.unavailable ||
        !_service.writable) {
      _confirming = false;
      _acknowledged = false;
    }
    setState(() {});
  }

  Future<void> _select(String id) async {
    if (id == _service.current || _service.busy) return;
    if (id == kFullAccessPreset) {
      setState(() {
        _acknowledged = false;
        _confirming = true;
      });
      return;
    }
    final error = await _commit(id);
    if (!mounted || error == null) return;
    _showFailure(error);
  }

  /// Persists one preset; returns the failure text, if any.
  Future<String?> _commit(String id) async {
    await _service.select(id);
    return _service.error;
  }

  void _showFailure(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Theme.of(context)
            .extension<DswThemeExtension>()
            ?.aliases
            .stateErrorPrimary,
      ),
    );
  }

  Future<void> _confirmFullAccess() async {
    if (_service.busy) return;
    setState(() {
      _confirming = false;
      _acknowledged = false;
    });
    final error = await _commit(kFullAccessPreset);
    if (!mounted || error == null) return;
    _showFailure(error);
  }

  void _cancelFullAccess() {
    setState(() {
      _confirming = false;
      _acknowledged = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_service.scope.snapshot.status == SettingsScopeStatus.unavailable) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kPermissionSettingsNamespace);
    final options = _service.options;
    final current = _service.current;
    String labelFor(String id, String name) =>
        displayPermissionPreset(id, name, t);
    final selected = current == null
        ? null
        : options.where((o) => o.id == current).firstOrNull;
    final busy = _service.busy || _confirming;
    final label = selected != null
        ? labelFor(selected.id, selected.label)
        : (busy ? t('loading') : t('unavailable'));
    final description = _service.error ?? t('description');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: aliases.borderL2, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('title'),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w400,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: _service.error == null
                            ? aliases.labelTertiary
                            : aliases.stateErrorPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                enabled: !busy && _service.writable && options.isNotEmpty,
                offset: const Offset(0, 32),
                color: aliases.specificMenu,
                onSelected: _select,
                itemBuilder: (ctx) => [
                  for (final option in options)
                    PopupMenuItem<String>(
                      value: option.id,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              labelFor(option.id, option.label),
                              style: TextStyle(
                                color: option.id == kFullAccessPreset
                                    ? aliases.stateErrorPrimary
                                    : aliases.labelPrimary,
                                fontWeight: current == option.id
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (current == option.id)
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
        ),
        DsRiskConfirmation(
          open: _confirming,
          title: t('confirm.title'),
          description: t('confirm.description'),
          acknowledgeLabel: t('confirm.acknowledge'),
          cancelLabel: t('confirm.cancel'),
          confirmLabel: t('confirm.enable'),
          acknowledged: _acknowledged,
          disabled: _service.busy,
          onAcknowledgedChange: (value) =>
              setState(() => _acknowledged = value),
          onCancel: _cancelFullAccess,
          onConfirm: _confirmFullAccess,
        ),
      ],
    );
  }
}
