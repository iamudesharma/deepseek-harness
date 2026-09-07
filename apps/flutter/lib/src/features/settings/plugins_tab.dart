/// Live Plugins configuration tab — parity with React `ConfigurablePluginsTab`
/// + the four shipped cards.
///
/// Replaces the stub `_PluginsTab` that rendered 6 hardcoded `_PluginInfo`
/// toggles. This tab enumerates settings namespaces but never interprets one
/// beyond the card key: a card arrives keyed by namespace so a plugin that
/// ships a browser half owns its controls. Here the four stock cards are
/// registered directly; the registry abstraction from the plan is deferred
/// until a third-party card needs it — the tab already mirrors
/// `served ∩ registered` filtering by hiding unavailable cards (they return
/// `SizedBox.shrink`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/settings/settings_scope.dart';
import '../../theme/app_theme.dart';
import '../settings_plugins/card_form.dart';
import '../settings_plugins/cards/agent_loop_card.dart';
import '../settings_plugins/cards/shell_card.dart';
import '../settings_plugins/cards/subagent_card.dart';
import '../settings_plugins/cards/subagent_controller.dart';
import '../settings_plugins/cards/web_search_card.dart';
import '../settings_plugins/widgets/fields.dart';
import '../settings_plugins/widgets/plugin_card.dart';
import '../../plugins/settings/registry/settings_plugin_registry.dart';

/// Namespace keys — must match Host `settings.describe` entries and
/// `packages/client/ui-settings-plugins/src/client/*-controller.ts`.
const String _kShellNs = 'shell';
const String _kAgentLoopNs = 'agent-loop';
const String _kWebSearchNs = 'web-search-deepseek';
const String _kSubagentNs = 'subagent-model-selection';

/// Plugins tab shown inside `SettingsScreen` TabBarView.
///
/// Live: builds per-namespace [SettingsScope] + [CardForm] and renders
/// `PluginCard` chrome with `ValueField`/`SecretField`. Unavailable namespaces
/// render nothing (no trace), matching React `if (!state.available) return null`.
class PluginsTab extends ConsumerStatefulWidget {
  const PluginsTab({super.key, required this.aliases});

  final DswAliases aliases;

  @override
  ConsumerState<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends ConsumerState<PluginsTab> {
  late final SettingsScope<Map<String, Object?>> _shellScope;
  late final SettingsScope<Map<String, Object?>> _agentScope;
  late final SettingsScope<Map<String, Object?>> _webScope;
  late final SettingsScope<Map<String, Object?>> _subagentScope;

  late final CardForm<Map<String, Object?>> _shellForm;
  late final CardForm<Map<String, Object?>> _agentForm;
  late final CardForm<Map<String, Object?>> _webForm;
  late final SubagentController _subagentController;
  late final PluginCardFormStore _extraStore;
  late final SettingsPluginRegistry _registry;
  VoidCallback? _registryUnsub;

  bool _ready = false;
  String? _error;
  bool _webKeyConfigured = false;
  bool _webKeyWritable = true;

  @override
  void initState() {
    super.initState();
    final ConnectionClient client = ref.read(connectionClientProvider);
    final SettingsRpcFace face = SettingsRpcFace(client);

    _shellScope = SettingsScope<Map<String, Object?>>(
      face: face,
      namespace: _kShellNs,
    );
    _agentScope = SettingsScope<Map<String, Object?>>(
      face: face,
      namespace: _kAgentLoopNs,
    );
    _webScope = SettingsScope<Map<String, Object?>>(
      face: face,
      namespace: _kWebSearchNs,
    );
    _subagentScope = SettingsScope<Map<String, Object?>>(
      face: face,
      namespace: _kSubagentNs,
    );

    _shellForm = CardForm<Map<String, Object?>>(
      scope: _shellScope,
      specs: [numberField('timeoutMs'), numberField('maxOutputBytes')],
    );
    _agentForm = CardForm<Map<String, Object?>>(
      scope: _agentScope,
      specs: [numberField('maxParallelToolCalls')],
    );
    _webForm = CardForm<Map<String, Object?>>(
      scope: _webScope,
      specs: [textField('baseURL'), numberField('maxUses')],
      secrets: [
        CardSecretSpec(
          field: 'apiKey',
          write: (String text) async {
            if (text.trim().isEmpty) return true;
            try {
              // Resolve ref from current apiKeyEnv or default.
              final Object? v = _webScope.snapshot.value;
              String ref = 'DEEPSEEK_API_KEY';
              if (v is Map && v['apiKeyEnv'] is String && (v['apiKeyEnv'] as String).isNotEmpty) {
                ref = v['apiKeyEnv'] as String;
              }
              await client.credentialsSet(ref: ref, value: text);
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ],
    );
    _subagentController = SubagentController(scope: _subagentScope, client: client);
    _extraStore = PluginCardFormStore(
      settingsFaceFactory: (String ns) => SettingsScope<Map<String, Object?>>(
        face: SettingsRpcFace(ref.read(connectionClientProvider)),
        namespace: ns,
      ),
    );
    // React to third-party registry changes (ChangeNotifier).
    _registry = ref.read(settingsPluginRegistryProvider);
    void onRegistry() {
      if (mounted) setState(() {});
    }

    _registry.addListener(onRegistry);
    _registryUnsub = () => _registry.removeListener(onRegistry);

    // Attach listeners so any scope refresh rebuilds the tab.
    for (final s in <SettingsScope<Map<String, Object?>>>[
      _shellScope,
      _agentScope,
      _webScope,
      _subagentScope,
    ]) {
      s.subscribe((_) {
        if (mounted) setState(() {});
      });
    }
    _webScope.subscribe((_) => _refreshWebCredential());
    for (final f in <CardForm<Map<String, Object?>>>[
      _shellForm,
      _agentForm,
      _webForm,
    ]) {
      f.addListener(() {
        if (mounted) setState(() {});
      });
    }
    _subagentController.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _refreshWebCredential() async {
    final ConnectionClient client = ref.read(connectionClientProvider);
    final Object? v = _webScope.snapshot.value;
    String refName = 'DEEPSEEK_API_KEY';
    if (v is Map && v['apiKeyEnv'] is String && (v['apiKeyEnv'] as String).isNotEmpty) {
      refName = v['apiKeyEnv'] as String;
    }
    try {
      final Map<String, dynamic> res = await client.credentialsDescribe([refName]);
      // credentialsDescribe returns {refs: {ref: {configured,writable}}} or similar.
      // Handle both shapes: {value: {ref: ...}} or direct.
      Map<String, dynamic>? view;
      if (res.containsKey('value') && res['value'] is Map) {
        final Map m = res['value'] as Map;
        if (m.containsKey(refName)) view = (m[refName] as Map?)?.cast<String, dynamic>();
      } else if (res.containsKey(refName)) {
        view = (res[refName] as Map?)?.cast<String, dynamic>();
      }
      if (!mounted) return;
      setState(() {
        _webKeyConfigured = view?['configured'] as bool? ?? false;
        _webKeyWritable = view?['writable'] as bool? ?? true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _webKeyConfigured = false;
        _webKeyWritable = true;
      });
    }
  }

  Future<void> _load() async {
    try {
      await Future.wait([
        _shellScope.refreshFromDescribe(),
        _agentScope.refreshFromDescribe(),
        _webScope.refreshFromDescribe(),
        _subagentScope.refreshFromDescribe(),
      ]);
      await _refreshWebCredential();
      // Kick subagent catalog if enabled (controller also does on scope change).
      if (_subagentController.state.enabled && _subagentController.state.catalogStatus == 'idle') {
        _subagentController.refreshCatalog();
      }
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _registryUnsub?.call();
    _shellForm.dispose();
    _agentForm.dispose();
    _webForm.dispose();
    _subagentController.dispose();
    _extraStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          Text(
            'Loading plugin configuration failed: $_error',
            style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary),
          ),
          const SizedBox(height: DswTokens.spaceMd),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }

    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    // Stock cards.
    final List<Widget> cards = <Widget>[
      ShellCard(form: _shellForm),
      AgentLoopCard(form: _agentForm),
      SubagentCard(controller: _subagentController),
      WebSearchCard(
        form: _webForm,
        apiKeyConfigured: _webKeyConfigured,
        apiKeyWritable: _webKeyWritable,
      ),
    ];

    // Third-party cards via registry — mirrors `settings.plugin.item` slot.
    final SettingsPluginRegistry registry = _registry;
    for (final SettingsPluginCardDescriptor desc in registry.cards) {
      if ({_kShellNs, _kAgentLoopNs, _kWebSearchNs, _kSubagentNs}.contains(desc.namespace)) continue;
      final CardForm<Map<String, Object?>> form = _extraStore.formFor(desc);
      if (!form.shell().available) continue;
      cards.add(_GenericPluginCard(descriptor: desc, form: form));
    }

    // Determine visibility for empty state: how many scopes are ready (available).
    int availableCount = <bool>[
      _shellForm.shell().available,
      _agentForm.shell().available,
      _subagentController.state.available,
      _webForm.shell().available,
    ].where((v) => v).length;
    // Include third-party available cards already in `cards` beyond stock 4.
    // Stock cards are 4, extras are cards.length - 4 when all stock available,
    // but some stock may be hidden; simpler: count extras that were added.
    final int stockCount = 4;
    if (cards.length > stockCount) {
      availableCount += cards.length - stockCount;
    } else if (cards.length < stockCount) {
      // Some stock unavailable were still in list but hidden; availableCount already correct.
    }

    if (availableCount == 0) {
      return SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg),
        child: ListView(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          children: [
            _SectionHeader(title: 'Plugins', aliases: aliases),
            const SizedBox(height: 4),
            Text(
              'Configure and inspect the plugins installed in this deployment.',
              style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary),
            ),
            const SizedBox(height: DswTokens.spaceLg),
            Container(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              decoration: BoxDecoration(
                color: aliases.bgLayer2,
                borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                border: Border.all(color: aliases.borderL2),
              ),
              child: Text(
                'This deployment exposes no plugin settings.',
                style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
      child: ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          Text(
            'Plugins',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure and inspect the plugins installed in this deployment.',
            style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelTertiary),
          ),
          const SizedBox(height: DswTokens.spaceMd),
          for (final Widget card in cards) ...[
            card,
            const SizedBox(height: DswTokens.spaceSm),
          ],
          const SizedBox(height: DswTokens.spaceLg),
          Container(
            decoration: BoxDecoration(
              color: aliases.bgLayer2,
              borderRadius: BorderRadius.circular(DswTokens.radiusLg),
              border: Border.all(color: aliases.borderL2),
            ),
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: aliases.labelTertiary),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Text(
                    '$availableCount plugin settings · Cards are contributed via settings.plugin.item; unavailable plugins leave no trace.',
                    style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.aliases});
  final String title;
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) => Text(
        title,
        style: TextStyle(
          fontSize: DswTokens.fontSizeS14,
          fontWeight: FontWeight.w600,
          color: aliases.labelPrimary,
          letterSpacing: 0.2,
        ),
      );
}

/// Generic card for third-party `settings.plugin.item` descriptors.
class _GenericPluginCard extends StatelessWidget {
  const _GenericPluginCard({required this.descriptor, required this.form});

  final SettingsPluginCardDescriptor descriptor;
  final CardForm<Map<String, Object?>> form;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: form,
        builder: (context, _) {
          final CardShell shell = form.shell();
          return PluginCard(
            title: descriptor.title,
            description: descriptor.description,
            shell: shell,
            onSave: () => form.save(),
            onDiscard: () => form.discard(),
            child: Column(
              children: [
                for (final CardFieldSpec spec in descriptor.fieldSpecs)
                  Builder(
                    builder: (context) {
                      final CardFieldState st = form.field(spec.field);
                      return ValueField(
                        id: 'plugin-config-${descriptor.namespace}-${spec.field}',
                        label: spec.field,
                        hint: '',
                        text: st.text,
                        overridden: st.overridden,
                        invalid: st.invalid,
                        overriddenLabel: 'Overridden',
                        resetLabel: 'Reset to default',
                        invalidLabel: 'Enter a number, or leave blank to use the default.',
                        disabled: !shell.writable,
                        onEdit: (v) => form.edit(spec.field, v),
                        onReset: () => form.resetField(spec.field),
                      );
                    },
                  ),
                for (final CardSecretSpec secret in descriptor.secretSpecs)
                  Builder(
                    builder: (context) {
                      final CardFieldState st = form.field(secret.field);
                      return SecretField(
                        id: 'plugin-config-${descriptor.namespace}-${secret.field}',
                        label: secret.field,
                        hint: 'Stored outside the settings file. Leave blank to keep the current value.',
                        text: st.text,
                        disabled: false,
                        configured: false,
                        stateLabel: 'No value configured',
                        onEdit: (v) => form.edit(secret.field, v),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
}
