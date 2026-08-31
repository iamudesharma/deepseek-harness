import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/ds_button.dart';
import '../../../widgets/primitives/ds_input.dart';
import '../../../widgets/primitives/ds_select.dart';
import '../models_store.dart';

/// Localized copy for Models settings — mirrors `en` in `locales.ts`.
const Map<String, String> _t = {
  'keyInput': 'API key',
  'keyPlaceholder': 'Enter your API key',
  'keyPlaceholderNative':
      'Enter an API key, or leave blank to use environment authentication',
  'keyStored': 'Configured — enter a new value to replace',
  'keyEnvLocked': 'Provided by the launch environment (read-only)',
  'baseUrl': 'Base URL',
  'baseUrlDefault': 'Provider default',
  'customized': 'Customized settings',
  'customDisplayName': 'Display name',
  'customApi': 'API protocol',
  'customApiUnset': 'Not selected',
  'advancedHint':
      'Other fields live in settings.yaml; edit that section directly.',
  'cancel': 'Cancel',
  'apply': 'Apply',
  'applying': 'Applying…',
  'model': 'Model',
  'keyBlank':
      'Enter the API key, or leave the field empty to keep the stored one.',
  'keyIllegalCharacters':
      'This API key is not in a valid format. Please check it.',
  'conflict': 'Someone else changed these settings while this card was open. Close it and reopen to edit the current values.',
};

String _tr(String key) => _t[key] ?? key;

// ---------------------------------------------------------------------------
// Validation helpers — mirrors `apiKey.ts`
// ---------------------------------------------------------------------------

final RegExp _legalApiKey = RegExp(r'^[\x21-\x7E]+$');
final RegExp _envLine = RegExp(r'^[A-Z][A-Z0-9_]*=[^=]');

bool _isQuoted(String value) {
  if (value.isEmpty) return false;
  final first = value[0];
  if (first != '"' && first != "'" && first != '`') return false;
  return value.length > 1 && value.endsWith(first);
}

String? _apiKeyFailure(String draft) {
  if (draft.isEmpty) return null;
  final value = draft.trim();
  if (value.isEmpty) return 'keyBlank';
  if (_envLine.hasMatch(value) || _isQuoted(value))
    return 'keyIllegalCharacters';
  if (!_legalApiKey.hasMatch(value)) return 'keyIllegalCharacters';
  return null;
}

// ---------------------------------------------------------------------------
// Path ops — mirrors `pathOps` in `ProviderEditor.tsx`
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> pathOps(
  List<String> base,
  dynamic before,
  Map<String, dynamic> after,
) {
  final previous = before is Map<String, dynamic>
      ? before
      : before is Map
      ? before.cast<String, dynamic>()
      : <String, dynamic>{};
  final ops = <Map<String, dynamic>>[];
  for (final entry in after.entries) {
    final prevVal = previous[entry.key];
    // JSON equality check like original
    if (prevVal != null && prevVal.toString() == entry.value.toString()) {
      // Rough check; use deep equality via stringify if needed
      // Keep simple but preserve semantics: if JSON strings equal skip
      // Use accurate JSON compare for primitives already.
      if (_jsonEquals(prevVal, entry.value)) continue;
    } else if (prevVal == null && entry.value == null) {
      continue;
    }
    // Deeper JSON equality
    if (_jsonEquals(prevVal, entry.value)) continue;
    ops.add({
      'op': 'set',
      'path': [...base, entry.key],
      'value': entry.value,
    });
  }
  for (final key in previous.keys) {
    if (!after.containsKey(key)) {
      ops.add({
        'op': 'unset',
        'path': [...base, key],
      });
    }
  }
  return ops;
}

bool _jsonEquals(dynamic a, dynamic b) {
  // Simple deep equality via stringify for small maps
  if (a == b) return true;
  if (a == null || b == null) return false;
  try {
    // Use toString comparison as fallback; adequate for our usage
    return a.toString() == b.toString();
  } catch (_) {
    return false;
  }
}

Map<String, dynamic> _draftAt(
  SettingsNamespaceView namespace,
  List<String> path,
) {
  final subtree = getPath(namespace.user, path);
  if (subtree is Map<String, dynamic>)
    return Map<String, dynamic>.from(subtree);
  if (subtree is Map) return subtree.cast<String, dynamic>();
  return <String, dynamic>{};
}

Map<String, dynamic> _setPath(
  Map<String, dynamic> root,
  List<String> path,
  dynamic value,
) {
  if (path.isEmpty) return Map<String, dynamic>.from(root);
  final copy = Map<String, dynamic>.from(root);
  if (path.length == 1) {
    copy[path[0]] = value;
    return copy;
  }
  // Nested one level only for our fields; generalize for arbitrary depth
  Map<String, dynamic> cur = copy;
  for (int i = 0; i < path.length - 1; i++) {
    final key = path[i];
    final next = cur[key];
    final nextMap = next is Map<String, dynamic>
        ? Map<String, dynamic>.from(next)
        : next is Map
        ? next.cast<String, dynamic>()
        : <String, dynamic>{};
    cur[key] = nextMap;
    cur = nextMap;
  }
  cur[path.last] = value;
  return copy;
}

Map<String, dynamic> _deletePath(Map<String, dynamic> root, List<String> path) {
  if (path.isEmpty) return Map<String, dynamic>.from(root);
  final copy = Map<String, dynamic>.from(root);
  if (path.length == 1) {
    copy.remove(path[0]);
    return copy;
  }
  Map<String, dynamic>? cur = copy;
  for (int i = 0; i < path.length - 1; i++) {
    final key = path[i];
    final next = cur?[key];
    if (next is Map<String, dynamic>) {
      final nextCopy = Map<String, dynamic>.from(next);
      cur![key] = nextCopy;
      cur = nextCopy;
    } else if (next is Map) {
      final nextCopy = next.cast<String, dynamic>();
      cur![key] = nextCopy;
      cur = nextCopy as Map<String, dynamic>?;
    } else {
      return copy;
    }
  }
  cur?.remove(path.last);
  return copy;
}

String _refFor(
  SettingsNamespaceView namespace,
  List<String> path,
  String provider,
) {
  final profile = getPath(namespace.value, path);
  if (profile is Map) {
    final named = profile['apiKeyEnv'];
    if (named is String && named.isNotEmpty) return named;
  }
  return deriveKeyRef(provider);
}

String? _stringAt(
  SettingsNamespaceView? namespace,
  Map<String, dynamic> draft,
  String key, {
  bool fromDraft = true,
}) {
  if (fromDraft) {
    final v = draft[key];
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }
  // fallback read from namespace value
  final v = namespace != null ? getPath(namespace.value, [key]) : null;
  if (v is String && v.trim().isNotEmpty) return v;
  return null;
}

/// ProviderEditor — Flutter port of `ProviderEditor.tsx`.
///
/// Props mirror the React `ProviderEditorProps` but with Flutter-idiomatic
/// types: `namespace` is a [SettingsNamespaceView], `settingsPath` is the
/// provider settings address, and `onClose` carries `changed`.
class ProviderEditor extends ConsumerStatefulWidget {
  const ProviderEditor({
    super.key,
    required this.provider,
    required this.displayName,
    required this.settingsPath,
    required this.namespace,
    this.declared = false,
    this.hideTitle = false,
    this.readOnly = false,
    required this.onClose,
  });

  final String provider;
  final String displayName;
  final List<String> settingsPath;
  final SettingsNamespaceView namespace;
  final bool declared;
  final bool hideTitle;
  final bool readOnly;
  final ValueChanged<bool> onClose;

  @override
  ConsumerState<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends ConsumerState<ProviderEditor> {
  late Map<String, dynamic> _draft;
  String _keyDraft = '';
  CredentialView? _keyState;
  bool _busy = false;
  String? _failure;
  late dynamic _committedOriginal;
  late int _expectedRevision;

  late TextEditingController _keyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _displayNameController;
  late TextEditingController _modelsController;

  String? _selectedApi;
  bool _showCustomized = false;

  @override
  void initState() {
    super.initState();
    _draft = _draftAt(widget.namespace, widget.settingsPath);
    _committedOriginal = getPath(widget.namespace.user, widget.settingsPath);
    _expectedRevision = widget.namespace.revision;
    _keyController = TextEditingController(text: '');
    _baseUrlController = TextEditingController(
      text: _stringAt(null, _draft, 'baseURL') ?? '',
    );
    _displayNameController = TextEditingController(
      text: _stringAt(null, _draft, 'displayName') ?? '',
    );
    // Models as JSON-ish simple list string for now
    final models = _draft['models'];
    _modelsController = TextEditingController(
      text: models is List
          ? models
                .map(
                  (e) => e is Map
                      ? (e['id'] ?? e.toString()).toString()
                      : e.toString(),
                )
                .join(', ')
          : '',
    );
    // Determine initial api
    final probeApi =
        _stringAt(null, _draft, 'api') ??
        (getPath(widget.namespace.value, widget.settingsPath) is Map
            ? ((getPath(widget.namespace.value, widget.settingsPath)
                      as Map)['api']
                  as String?)
            : null);
    _selectedApi = probeApi;
    _fetchKeyState();
  }

  Future<void> _fetchKeyState() async {
    final ref_ = _refFor(
      widget.namespace,
      widget.settingsPath,
      widget.provider,
    );
    try {
      final client = ref.read(connectionClientProvider);
      final value = await client.credentialsDescribe([ref_]);
      final creds = value['credentials'] as Map? ?? {};
      final entry = creds[ref_];
      if (!mounted) return;
      if (entry is Map) {
        setState(
          () => _keyState = CredentialView.fromJson(
            entry.cast<String, dynamic>(),
          ),
        );
      }
    } catch (_) {
      // Silently render without hint, like React
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _displayNameController.dispose();
    _modelsController.dispose();
    super.dispose();
  }

  String get _layout {
    if (widget.namespace.ns == 'llm-deepseek') return 'deepseek';
    if (widget.namespace.ns == 'llm-pi-ai') return 'pi-ai';
    return 'unknown';
  }

  Future<String?> _applyOnce() async {
    final ns = widget.namespace.ns;
    final layout = _layout;
    // pi-ai profile names conventional ref only when storing a key
    final keyValue = _keyDraft.trim();
    final fallback = getPath(widget.namespace.value, widget.settingsPath);
    Map<String, dynamic> next = _draft;
    if (layout == 'pi-ai' &&
        _stringAt(null, _draft, 'apiKeyEnv') == null &&
        (fallback is Map ? fallback['apiKeyEnv'] == null : true) &&
        keyValue.isNotEmpty) {
      final ref_ = _refFor(
        widget.namespace,
        widget.settingsPath,
        widget.provider,
      );
      next = _setPath(_draft, ['apiKeyEnv'], ref_);
    }

    // Apply models from text field if changed
    if (_modelsController.text.trim().isNotEmpty) {
      final ids = _modelsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final models = ids.map((id) => <String, dynamic>{'id': id}).toList();
      // Only update if different from current
      next = _setPath(next, ['models'], models);
    } else if (_modelsController.text.trim().isEmpty &&
        _draft.containsKey('models')) {
      // Keep empty string as no change? If user cleared, unset?
      // For now if cleared and draft had models, remove?
      // Keep original draft behavior: only if field was explicitly cleared with spaces -> delete
    }

    // Sync typed fields into next
    final baseUrlText = _baseUrlController.text.trim();
    if (baseUrlText.isEmpty) {
      next = _deletePath(next, ['baseURL']);
    } else {
      next = _setPath(next, ['baseURL'], baseUrlText);
    }
    if (widget.declared) {
      final dn = _displayNameController.text.trim();
      if (dn.isEmpty) {
        next = _deletePath(next, ['displayName']);
      } else {
        next = _setPath(next, ['displayName'], dn);
      }
      if (_selectedApi != null && _selectedApi!.isNotEmpty) {
        next = _setPath(next, ['api'], _selectedApi!);
      } else {
        next = _deletePath(next, ['api']);
      }
    }

    final materializesNativeProfile =
        layout == 'pi-ai' &&
        fallback == null &&
        _committedOriginal == null &&
        next.isEmpty;
    final List<Map<String, dynamic>> effectiveOps = materializesNativeProfile
        ? [
            {
              'op': 'set',
              'path': widget.settingsPath,
              'value': <String, dynamic>{},
            },
          ]
        : pathOps(widget.settingsPath, _committedOriginal, next);

    if (effectiveOps.isNotEmpty) {
      final client = ref.read(connectionClientProvider);
      try {
        final result = await client.settingsMutate(
          ns: ns,
          ops: effectiveOps,
          expectedRevision: _expectedRevision,
        );
        // result is the new namespace view; update baselines
        final newUserPath =
            getPath(result['user'] ?? result['value'], widget.settingsPath) ??
            getPath(result, widget.settingsPath);
        // result itself may be the namespace view; try to get revision
        final rev = result['revision'] as int? ?? _expectedRevision;
        setState(() {
          _committedOriginal =
              getPath(result['user'], widget.settingsPath) ?? newUserPath;
          _expectedRevision = rev;
          _draft = next;
        });
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('settings-conflict')) return _tr('conflict');
        // Extract message after ':'
        return msg.contains(':') ? msg.split(':').last.trim() : msg;
      }
    } else {
      // Even if no ops, keep draft in sync
      setState(() => _draft = next);
    }

    if (keyValue.isNotEmpty) {
      final ref_ = _refFor(
        widget.namespace,
        widget.settingsPath,
        widget.provider,
      );
      try {
        await ref
            .read(connectionClientProvider)
            .credentialsSet(ref: ref_, value: keyValue);
      } catch (e) {
        return e.toString().contains(':')
            ? e.toString().split(':').last.trim()
            : e.toString();
      }
    }
    setState(() => _keyDraft = '');
    _keyController.clear();
    return null;
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final failure = await _applyOnce();
      if (!mounted) return;
      if (failure != null) {
        setState(() => _failure = failure);
        return;
      }
      widget.onClose(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _failure = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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

    final keyFailure = _apiKeyFailure(_keyDraft);
    final disabled = widget.readOnly || _busy;
    final layout = _layout;
    final isUnknown = layout == 'unknown';

    // Key placeholder logic
    final bool keyLocked = _keyState?.writable == false;
    final String keyPlaceholder;
    if (keyLocked) {
      keyPlaceholder = _tr('keyEnvLocked');
    } else if (_keyState?.configured == true) {
      keyPlaceholder = _tr('keyStored');
    } else if (layout == 'pi-ai') {
      keyPlaceholder = _tr('keyPlaceholderNative');
    } else {
      keyPlaceholder = _tr('keyPlaceholder');
    }

    final ownsIdentity = layout == 'pi-ai' && widget.declared;

    // For pi-ai, protocols are the union choices; fallback to common set
    final List<String> protocols = const ['openai', 'anthropic', 'google'];

    final bool submitDisabled =
        disabled ||
        isUnknown ||
        keyFailure != null ||
        _keyDraft.trim().isEmpty &&
            false; // credentialRequired not used in normal editor

    return Container(
      decoration: BoxDecoration(
        color: aliases.bgModulePlatform,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: DswTokens.transparent),
      ),
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.hideTitle) ...[
            Row(
              children: [
                Text(
                  widget.displayName,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
                if (widget.provider != widget.displayName) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.provider,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      height:
                          DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                      color: aliases.labelTertiary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: DswTokens.spaceMd),
          ],
          if (isUnknown)
            Text(
              '${_tr('advancedHint')} (${widget.namespace.ns})',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: 18 / 12,
                color: aliases.labelTertiary,
              ),
            )
          else ...[
            DsInput(
              label: _tr('keyInput'),
              hintText: keyPlaceholder,
              controller: _keyController,
              enabled: !disabled && !keyLocked,
              obscureText: true,
              onChanged: (v) => setState(() => _keyDraft = v),
              errorText: keyFailure != null ? _tr(keyFailure) : null,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            // Customized disclosure
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: aliases.borderL2)),
              ),
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _showCustomized = !_showCustomized),
                    borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showCustomized
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 14,
                          color: aliases.labelSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _tr('customized'),
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            fontWeight: FontWeight.w500,
                            color: aliases.labelSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showCustomized) ...[
                    const SizedBox(height: DswTokens.spaceMd),
                    if (ownsIdentity) ...[
                      DsInput(
                        label: _tr('customDisplayName'),
                        hintText: widget.provider,
                        controller: _displayNameController,
                        enabled: !disabled,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: DswTokens.spaceMd),
                    ],
                    DsInput(
                      label: _tr('baseUrl'),
                      hintText: layout == 'deepseek'
                          ? 'https://api.deepseek.com'
                          : _tr('baseUrlDefault'),
                      controller: _baseUrlController,
                      enabled: !disabled,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: DswTokens.spaceMd),
                    if (ownsIdentity)
                      DsSelect(
                        label: _tr('customApi'),
                        value: _selectedApi,
                        enabled: !disabled,
                        placeholder: _tr('customApiUnset'),
                        options: protocols
                            .map((p) => DsSelectOption(value: p, label: p))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedApi = v),
                      ),
                    if (ownsIdentity) const SizedBox(height: DswTokens.spaceMd),
                    DsInput(
                      label: _tr('model'),
                      hintText: 'model-id, comma separated',
                      controller: _modelsController,
                      enabled: !disabled,
                      onChanged: (_) => setState(() {}),
                      helperText: _tr('advancedHint'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_failure != null) ...[
            const SizedBox(height: DswTokens.spaceSm),
            Text(
              _failure!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: 18 / 12,
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
                size: DsButtonSize.md,
                label: _tr('cancel'),
                onPressed: _busy ? null : () => widget.onClose(false),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              DsButton(
                variant: DsButtonVariant.primary,
                size: DsButtonSize.md,
                label: _busy ? _tr('applying') : _tr('apply'),
                loading: _busy,
                onPressed: submitDisabled ? null : _apply,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
