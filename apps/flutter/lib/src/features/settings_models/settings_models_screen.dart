import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../theme/app_theme.dart';
import '../../plugins/settings/children/models/models_settings_plugin.dart'
    show kModelsNamespace;
import '../../widgets/primitives/bottom_sheet.dart';
import '../../widgets/primitives/ds_button.dart';
import '../../widgets/primitives/ds_modal.dart';
import '../../widgets/primitives/ds_select.dart';
import 'models_store.dart';
import 'widgets/provider_editor.dart';

// The live translate face [_t] lives on the screen State below: it binds
// against the `models` namespace registered by ModelsSettingsPlugin's apply,
// and the revision watch inside bindLocale re-renders on a Language-row
// switch.

String _providerLabel(String provider, String displayName) =>
    provider == displayName ? provider : '$displayName ($provider)';

String _providerCopy(String template, String provider, String displayName) =>
    template.replaceAll('{provider}', _providerLabel(provider, displayName));

/// EditorTarget — mirrors `EditorTarget` in `ModelsSection.tsx`.
class _EditorTarget {
  const _EditorTarget({
    required this.provider,
    required this.displayName,
    required this.settingsNs,
    required this.settingsPath,
    this.credentialRef,
    this.declared = false,
  });

  final String provider;
  final String displayName;
  final String settingsNs;
  final List<String> settingsPath;
  final String? credentialRef;
  final bool declared;
}

_EditorTarget _targetOf(ProviderRow row) {
  final managedRef = deriveKeyRef(row.entry.provider);
  final credentialRef =
      row.apiKeyEnv == managedRef &&
          row.credential?.configured == true &&
          row.credential!.writable
      ? managedRef
      : null;
  return _EditorTarget(
    provider: row.entry.provider,
    displayName: row.entry.displayName,
    settingsNs: row.entry.settingsNs,
    settingsPath: row.entry.settingsPath,
    credentialRef: credentialRef,
    declared: row.entry.declared == true,
  );
}

bool _needsSetup(ProviderRow row, bool anyUsable) {
  if (anyUsable) return false;
  if (row.entry.settingsPath.isNotEmpty) return false;
  return row.credential?.configured != true;
}

Future<String?> _removeProviderProfile(
  ConnectionClient client,
  ModelsSettingsController controller,
  _EditorTarget target,
) async {
  try {
    if (target.credentialRef != null) {
      await client.credentialsUnset(ref: target.credentialRef!);
    }
    await client.settingsMutate(
      ns: target.settingsNs,
      ops: [
        {'op': 'unset', 'path': target.settingsPath},
      ],
    );
  } catch (e) {
    return e.toString().contains(':')
        ? e.toString().split(':').last.trim()
        : e.toString();
  }
  await controller.load();
  return null;
}

/// SettingsModelsScreen — full port of `ModelsSection.tsx`.
///
/// Handles idle/loading/error, header intro, readOnly notice, savedNotice,
/// rows with setupCard vs rowCard, editing/adding/declaring states,
/// addActions, and delete Modal via [DsModal]/[DsBottomSheet].
class SettingsModelsScreen extends ConsumerStatefulWidget {
  const SettingsModelsScreen({super.key});

  @override
  ConsumerState<SettingsModelsScreen> createState() =>
      _SettingsModelsScreenState();
}

class _SettingsModelsScreenState extends ConsumerState<SettingsModelsScreen> {
  /// Live translate face for the section copy — binds against the `models`
  /// namespace registered by ModelsSettingsPlugin's apply; the revision watch
  /// inside bindLocale re-renders on a Language-row switch.
  Translate get _t => ref.bindLocale(kModelsNamespace);
  _EditorTarget? _editing;
  bool _adding = false;
  _EditorTarget? _deleteTarget;
  bool _deleting = false;
  String? _deleteFailure;
  _EditorTarget? _savedTarget;
  bool _declaring = false;
  Set<String> _dismissedSetup = {};

  // Custom provider creation draft state — mirrors CustomProviderCard minimal
  bool _customCommitted = false;
  String _customRoute = '';
  String _customDisplayName = '';
  String _customBaseUrl = '';
  String _customProtocol = 'openai';
  String _customKeyDraft = '';
  String _customModelsText = '';
  bool _customBusy = false;
  String? _customFailure;

  void _announceSaved(_EditorTarget target) {
    // Reload then show saved notice, like React `announceSaved`
    final controller = ref.read(modelsSettingsControllerProvider.notifier);
    controller.load().then((_) {
      if (!mounted) return;
      setState(() => _savedTarget = target);
    });
  }

  void _closeEditor(bool changed, _EditorTarget target) {
    setState(() {
      _editing = null;
      _adding = false;
      _declaring = false;
    });
    if (changed) _announceSaved(target);
  }

  void _closeSetup(bool changed, _EditorTarget target) {
    setState(() => _dismissedSetup = {..._dismissedSetup, target.provider});
    if (changed) _announceSaved(target);
  }

  void _closeDelete() {
    if (_deleting) return;
    setState(() {
      _deleteTarget = null;
      _deleteFailure = null;
    });
  }

  Future<void> _confirmDelete() async {
    if (_deleteTarget == null || _deleting) return;
    setState(() {
      _deleting = true;
      _deleteFailure = null;
    });
    final client = ref.read(connectionClientProvider);
    final controller = ref.read(modelsSettingsControllerProvider.notifier);
    final failure = await _removeProviderProfile(
      client,
      controller,
      _deleteTarget!,
    );
    if (!mounted) return;
    if (failure != null) {
      setState(() => _deleteFailure = failure);
    } else {
      setState(() => _deleteTarget = null);
    }
    setState(() => _deleting = false);
  }

  Future<void> _createCustom() async {
    final routePattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');
    if (_customRoute.isEmpty || !routePattern.hasMatch(_customRoute)) {
      setState(
        () => _customFailure = 'Start with a lowercase letter; then lowercase letters, digits, and dashes.',
      );
      return;
    }
    if (_customBaseUrl.isEmpty) {
      setState(() => _customFailure = 'A custom provider needs a base URL.');
      return;
    }
    final ids = _customModelsText
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      setState(
        () => _customFailure = 'A custom provider needs at least one model.',
      );
      return;
    }
    setState(() {
      _customBusy = true;
      _customFailure = null;
    });
    try {
      final client = ref.read(connectionClientProvider);
      final controller = ref.read(modelsSettingsControllerProvider.notifier);
      final ns = 'llm-pi-ai';
      final nsView = ref.read(modelsSettingsControllerProvider).namespaces[ns];
      final revision = nsView?.revision ?? 0;
      final keyValue = _customKeyDraft.trim();
      final keyRef = deriveKeyRef(_customRoute);
      final profile = <String, dynamic>{
        if (_customDisplayName.isNotEmpty) 'displayName': _customDisplayName,
        if (keyValue.isNotEmpty) 'apiKeyEnv': keyRef,
        'api': _customProtocol,
        'baseURL': _customBaseUrl,
        'models': ids.map((id) => {'id': id}).toList(),
      };
      if (!_customCommitted) {
        await client.settingsMutate(
          ns: ns,
          ops: [
            {
              'op': 'set',
              'path': ['providers', _customRoute],
              'value': profile,
            },
          ],
          expectedRevision: revision,
        );
        setState(() => _customCommitted = true);
      }
      if (keyValue.isNotEmpty) {
        await client.credentialsSet(ref: keyRef, value: keyValue);
      }
      if (!mounted) return;
      setState(() {
        _declaring = false;
        _customRoute = '';
        _customDisplayName = '';
        _customBaseUrl = '';
        _customKeyDraft = '';
        _customModelsText = '';
        _customCommitted = false;
        _customFailure = null;
      });
      await controller.load();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _customFailure = e.toString().contains(':')
            ? e.toString().split(':').last.trim()
            : e.toString(),
      );
    } finally {
      if (mounted) setState(() => _customBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final state = ref.watch(modelsSettingsControllerProvider);
    final controller = ref.read(modelsSettingsControllerProvider.notifier);

    // Idle auto-load like React `if (state.status === 'idle') void controller.load()`
    if (state.status == ModelsSettingsStatus.idle) {
      Future.microtask(() => controller.load());
    }

    if (state.status == ModelsSettingsStatus.error) {
      final errorText = state.error ?? '';
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_t('loadFailed')}: $errorText',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  height: 18 / 12,
                  color: aliases.stateErrorPrimary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              DsButton(
                variant: DsButtonVariant.ghost,
                size: DsButtonSize.md,
                label: _t('retry'),
                onPressed: () => controller.load(),
              ),
            ],
          ),
        ),
      );
    }

    final isLoading =
        state.status == ModelsSettingsStatus.loading && state.rows.isEmpty;

    if (isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.status == ModelsSettingsStatus.ready && state.rows.isEmpty) {
      // Host returned no providers: the wire call succeeded but the LLM plugin
      // and the user's settings profile produced an empty directory. Surface
      // the cause so the page never looks blank.
      final hint = state.writable
          ? 'No providers available. The host LLM plugin may not be mounted, '
              'or no profile is declared in your settings.'
          : 'No providers available, and settings are read-only in this host.';
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('title'),
                  style: TextStyle(
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t('intro'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    height: 22 / 14,
                    color: aliases.labelTertiary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    height: 18 / 12,
                    color: aliases.labelSecondary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceMd),
                DsButton(
                  variant: DsButtonVariant.ghost,
                  size: DsButtonSize.md,
                  label: _t('retry'),
                  onPressed: () => controller.load(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Derive savedIdentity like React
    ProviderRow? savedRow;
    if (_savedTarget != null) {
      for (final r in state.rows) {
        if (r.entry.provider == _savedTarget!.provider) {
          savedRow = r;
          break;
        }
      }
    }
    final savedIdentity = savedRow != null
        ? _EditorTarget(
            provider: savedRow.entry.provider,
            displayName: savedRow.entry.displayName,
            settingsNs: savedRow.entry.settingsNs,
            settingsPath: savedRow.entry.settingsPath,
          )
        : _savedTarget;

    final anyUsable = state.rows.any(providerUsable);
    final configured = state.rows.where((r) => r.configured).toList();
    final addable = state.rows
        .where((r) => !r.configured && r.entry.settingsNs.isNotEmpty)
        .toList();
    final addTarget = _adding ? _editing : null;
    final addNamespace = addTarget != null
        ? state.namespaces[addTarget.settingsNs]
        : null;
    final protocols = const ['openai', 'anthropic', 'google'];

    // show delete dialog if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deleteTarget != null && mounted) {
        // We render dialog inline below instead of post-frame show; no-op
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _t('title'),
                    style: TextStyle(
                      fontSize: 16,
                      height: 24 / 16,
                      fontWeight: FontWeight.w500,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('intro'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      height: 22 / 14,
                      color: aliases.labelTertiary,
                    ),
                  ),
                  if (!state.writable &&
                      state.status == ModelsSettingsStatus.ready) ...[
                    const SizedBox(height: DswTokens.spaceMd),
                    Text(
                      _t('readOnly'),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        height: 18 / 12,
                        color: aliases.stateWarnLabel,
                      ),
                    ),
                  ],
                  if (savedIdentity != null) ...[
                    const SizedBox(height: DswTokens.spaceSm),
                    Text(
                      _providerCopy(
                        _t('savedProvider'),
                        savedIdentity.provider,
                        savedIdentity.displayName,
                      ),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        height: 18 / 12,
                        color: aliases.stateSuccessPrimary,
                      ),
                    ),
                  ],
                  if (state.credentialError != null) ...[
                    const SizedBox(height: DswTokens.spaceSm),
                    Text(
                      'Credentials unavailable: ${state.credentialError}',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        height: 18 / 12,
                        color: aliases.stateWarnLabel,
                      ),
                    ),
                  ],
                  const SizedBox(height: DswTokens.spaceMd),
                  // Rows
                  ...configured.map((row) {
                    final target = _targetOf(row);
                    final namespace = state.namespaces[target.settingsNs];
                    if (namespace == null) return const SizedBox.shrink();
                    if (_needsSetup(row, anyUsable) &&
                        !_dismissedSetup.contains(row.entry.provider)) {
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: DswTokens.spaceSm,
                        ),
                        child: ProviderEditor(
                          provider: target.provider,
                          displayName: target.displayName,
                          settingsPath: target.settingsPath,
                          namespace: namespace,
                          declared: target.declared,
                          readOnly: !state.writable,
                          onClose: (changed) => _closeSetup(changed, target),
                        ),
                      );
                    }
                    final open =
                        !_adding && _editing?.provider == row.entry.provider;
                    final credentialConfigured =
                        row.credential?.configured == true;
                    final credentialMissing =
                        !credentialConfigured &&
                        row.apiKeyEnv != null &&
                        row.credential?.configured == false;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: aliases.borderL2),
                          borderRadius: BorderRadius.circular(
                            DswTokens.radiusLg,
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          row.entry.displayName,
                                          style: TextStyle(
                                            fontSize: DswTokens.fontSizeS14,
                                            height: 22 / 14,
                                            fontWeight: FontWeight.w500,
                                            color: aliases.labelPrimary,
                                          ),
                                        ),
                                      ),
                                      if (row.entry.declared == true) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: aliases.borderL3,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            _t('customTag'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 16 / 11,
                                              color: aliases.labelSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (credentialConfigured) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: aliases.stateSuccessPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ] else if (credentialMissing) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: aliases.stateErrorPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                DsButton(
                                  variant: DsButtonVariant.ghost,
                                  size: DsButtonSize.sm,
                                  label: _t('edit'),
                                  onPressed: () {
                                    setState(() {
                                      _savedTarget = null;
                                      _declaring = false;
                                      _adding = false;
                                      _editing = open ? null : target;
                                    });
                                  },
                                ),
                                if (row.removable) ...[
                                  const SizedBox(width: 4),
                                  DsButton(
                                    variant: DsButtonVariant.ghost,
                                    size: DsButtonSize.sm,
                                    label: _t('remove'),
                                    onPressed: !state.writable
                                        ? null
                                        : () {
                                            setState(() {
                                              _savedTarget = null;
                                              _deleteFailure = null;
                                              _deleteTarget = target;
                                            });
                                          },
                                  ),
                                ],
                              ],
                            ),
                            if (open) ...[
                              const SizedBox(height: DswTokens.spaceMd),
                              ProviderEditor(
                                provider: target.provider,
                                displayName: target.displayName,
                                settingsPath: target.settingsPath,
                                namespace: namespace,
                                declared: target.declared,
                                readOnly: !state.writable,
                                onClose: (changed) =>
                                    _closeEditor(changed, target),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: DswTokens.spaceMd),
                  // Add block
                  if (addTarget != null && addNamespace != null)
                    Container(
                      decoration: BoxDecoration(
                        color: aliases.bgModulePlatform,
                        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                      ),
                      padding: const EdgeInsets.all(DswTokens.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DsSelect(
                            label: _t('provider'),
                            value: addTarget.provider,
                            options: addable
                                .map(
                                  (r) => DsSelectOption(
                                    value: r.entry.provider,
                                    label: r.entry.displayName,
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              final row = addable.firstWhere(
                                (c) => c.entry.provider == v,
                                orElse: () => addable.first,
                              );
                              setState(() => _editing = _targetOf(row));
                            },
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          ProviderEditor(
                            key: ValueKey(addTarget.provider),
                            provider: addTarget.provider,
                            displayName: addTarget.displayName,
                            settingsPath: addTarget.settingsPath,
                            namespace: addNamespace,
                            declared: addTarget.declared,
                            hideTitle: true,
                            readOnly: !state.writable,
                            onClose: (changed) =>
                                _closeEditor(changed, addTarget),
                          ),
                        ],
                      ),
                    )
                  else if (_declaring)
                    Container(
                      decoration: BoxDecoration(
                        color: aliases.bgModulePlatform,
                        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                      ),
                      padding: const EdgeInsets.all(DswTokens.spaceLg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Custom provider',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w500,
                              color: aliases.labelPrimary,
                            ),
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Provider ID',
                              hintText: 'acme-gateway',
                              filled: true,
                              fillColor: aliases.bgLayer1,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  DswTokens.radiusMd,
                                ),
                              ),
                            ),
                            enabled:
                                !_customCommitted &&
                                !_customBusy &&
                                state.writable,
                            onChanged: (v) => setState(() => _customRoute = v),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Lowercase identifier, starting with a letter.',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelTertiary,
                            ),
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Display name',
                              hintText: _customRoute.isEmpty
                                  ? 'Custom provider'
                                  : _customRoute,
                              filled: true,
                              fillColor: aliases.bgLayer1,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  DswTokens.radiusMd,
                                ),
                              ),
                            ),
                            enabled:
                                !_customCommitted &&
                                !_customBusy &&
                                state.writable,
                            onChanged: (v) =>
                                setState(() => _customDisplayName = v),
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Base URL',
                              hintText: 'https://gateway.example/v1',
                              filled: true,
                              fillColor: aliases.bgLayer1,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  DswTokens.radiusMd,
                                ),
                              ),
                            ),
                            enabled:
                                !_customCommitted &&
                                !_customBusy &&
                                state.writable,
                            onChanged: (v) =>
                                setState(() => _customBaseUrl = v),
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          DsSelect(
                            label: 'API protocol',
                            value: _customProtocol,
                            enabled:
                                !_customCommitted &&
                                !_customBusy &&
                                state.writable,
                            options: protocols
                                .map((p) => DsSelectOption(value: p, label: p))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _customProtocol = v),
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'API key',
                              hintText: 'Enter your API key',
                              filled: true,
                              fillColor: aliases.bgLayer1,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  DswTokens.radiusMd,
                                ),
                              ),
                            ),
                            obscureText: true,
                            enabled: !_customBusy && state.writable,
                            onChanged: (v) =>
                                setState(() => _customKeyDraft = v),
                          ),
                          const SizedBox(height: DswTokens.spaceMd),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Models (comma separated)',
                              hintText: 'gpt-4, gpt-3.5-turbo',
                              filled: true,
                              fillColor: aliases.bgLayer1,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  DswTokens.radiusMd,
                                ),
                              ),
                            ),
                            enabled:
                                !_customCommitted &&
                                !_customBusy &&
                                state.writable,
                            onChanged: (v) =>
                                setState(() => _customModelsText = v),
                          ),
                          if (_customFailure != null) ...[
                            const SizedBox(height: DswTokens.spaceSm),
                            Text(
                              _customFailure!,
                              style: TextStyle(
                                fontSize: DswTokens.fontSizeXxs12,
                                color: aliases.stateErrorPrimary,
                              ),
                            ),
                          ],
                          const SizedBox(height: DswTokens.spaceMd),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              DsButton(
                                variant: DsButtonVariant.ghost,
                                label: _t('cancel'),
                                onPressed: _customBusy
                                    ? null
                                    : () {
                                        setState(() {
                                          _declaring = false;
                                          _customFailure = null;
                                        });
                                        if (_customCommitted) {
                                          controller.load();
                                          setState(
                                            () => _customCommitted = false,
                                          );
                                        }
                                      },
                              ),
                              const SizedBox(width: DswTokens.spaceSm),
                              DsButton(
                                variant: DsButtonVariant.primary,
                                label: _customBusy
                                    ? 'Creating…'
                                    : 'Create provider',
                                loading: _customBusy,
                                onPressed: !_customBusy && state.writable
                                    ? _createCustom
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _AddDashedButton(
                            icon: Icons.add,
                            label: _t('add'),
                            enabled: addable.isNotEmpty && state.writable,
                            onPressed: () {
                              final first = addable.isNotEmpty
                                  ? addable.first
                                  : null;
                              if (first == null) return;
                              setState(() {
                                _savedTarget = null;
                                _declaring = false;
                                _adding = true;
                                _editing = _targetOf(first);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AddDashedButton(
                            icon: Icons.add,
                            label: _t('customAdd'),
                            enabled: protocols.isNotEmpty && state.writable,
                            onPressed: () {
                              setState(() {
                                _savedTarget = null;
                                _adding = false;
                                _editing = null;
                                _declaring = true;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (!state.writable || addable.isEmpty) ...[
                      const SizedBox(height: DswTokens.spaceSm),
                      Text(
                        !state.writable
                            ? _t('readOnly')
                            : 'No declared providers available to add. '
                                'The host LLM plugin may not be mounted, or '
                                'every declared provider is already configured.',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          height: 18 / 12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          // Delete modal overlay — uses DsModal for wide, adaptive for narrow handled via show
          if (_deleteTarget != null)
            DsModalOverlay(
              open: true,
              title: _providerCopy(
                _t('deleteTitle'),
                _deleteTarget!.provider,
                _deleteTarget!.displayName,
              ),
              description: _providerCopy(
                _deleteTarget!.credentialRef == null
                    ? _t('deleteDescription')
                    : _t('deleteDescriptionWithCredential'),
                _deleteTarget!.provider,
                _deleteTarget!.displayName,
              ),
              onClose: _closeDelete,
              footer: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DsButton(
                    variant: DsButtonVariant.ghost,
                    label: _t('cancel'),
                    onPressed: _deleting ? null : _closeDelete,
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  DsButton(
                    variant: DsButtonVariant.ghost,
                    label: _providerCopy(
                      _deleting ? _t('deleting') : _t('deleteConfirm'),
                      _deleteTarget!.provider,
                      _deleteTarget!.displayName,
                    ),
                    loading: _deleting,
                    onPressed: _deleting ? null : _confirmDelete,
                  ),
                ],
              ),
              child: _deleteFailure == null
                  ? null
                  : Text(
                      _deleteFailure!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.stateErrorPrimary,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _AddDashedButton extends StatelessWidget {
  const _AddDashedButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(DswTokens.radiusLg),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: aliases.borderL3, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: aliases.labelPrimary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    height: 22 / 14,
                    color: aliases.labelPrimary,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
