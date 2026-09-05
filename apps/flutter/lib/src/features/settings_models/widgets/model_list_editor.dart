import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/primitives/ds_button.dart';
import '../../../widgets/primitives/ds_input.dart';

/// One configured model row. Structurally open like React's `ModelDraft`:
/// fields this editor does not touch survive an edit.
typedef ModelDraft = Map<String, dynamic>;

/// Model fields this editor writes.
const List<String> _catalogFields = [
  'id',
  'name',
  'contextWindow',
  'maxTokens',
];

/// Capacity fields edited as K/M-suffixed text behind a row's disclosure.
const List<String> _capacityFields = ['contextWindow', 'maxTokens'];

/// Accepted capacity spellings: a decimal count with an optional K/M suffix.
final RegExp _capacityPattern = RegExp(r'^(\d+(?:\.\d+)?)([kKmM])?$');

/// Decimal suffix scales — `1M` is 1000K, matching how capacities are quoted.
const Map<String, int> _capacityScale = {'k': 1000, 'm': 1000000};

/// Read a typed capacity: `256K`/`1M` spellings become plain token counts.
///
/// Returns null when blank (inherit). Returns [double.nan] when unreadable;
/// [validateModels] rejects it before any write, mirroring React's
/// `parseCapacity` NaN contract.
num? parseCapacity(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final RegExpMatch? match = _capacityPattern.firstMatch(trimmed);
  if (match == null) return double.nan;
  final String digits = match.group(1)!;
  final String? suffix = match.group(2)?.toLowerCase();
  final int scale = suffix == null ? 1 : _capacityScale[suffix]!;
  final double scaled = double.parse(digits) * scale;
  final int rounded = scaled.round();
  return (scaled - rounded).abs() < 1e-6 ? rounded : scaled;
}

/// Whether capacity text is storable: blank (inherit) or a readable spelling.
bool isCapacityTextValid(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return true;
  final num? parsed = parseCapacity(trimmed);
  return parsed is int && parsed > 0;
}

/// Spell a stored count back in the shortest form that survives a round trip
/// through [parseCapacity].
String formatCapacity(num value) {
  if (value is! int || value <= 0) return value.toString();
  if (value % _capacityScale['m']! == 0) {
    return '${value ~/ _capacityScale['m']!}M';
  }
  if (value % _capacityScale['k']! == 0) {
    return '${value ~/ _capacityScale['k']!}K';
  }
  return value.toString();
}

/// Convert a raw models value into drafts without dropping hidden fields.
List<ModelDraft> modelDrafts(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is Map<String, dynamic>)
        Map<String, dynamic>.from(entry)
      else if (entry is Map)
        entry.cast<String, dynamic>()
      else
        <String, dynamic>{},
  ];
}

/// First invalid row of a user-owned models array, mirroring React's
/// `validateDeepSeekModels` adapter constraints.
({int index, String key})? validateModels(List<ModelDraft> models) {
  final Set<String> seen = {};
  for (int index = 0; index < models.length; index++) {
    final ModelDraft model = models[index];
    final dynamic rawId = model['id'];
    final String? id = rawId is String ? rawId.trim() : null;
    if (id == null || id.isEmpty) return (index: index, key: 'modelIdRequired');
    if (!seen.add(id)) return (index: index, key: 'modelIdDuplicate');
    final dynamic name = model['name'];
    if (name != null && (name is! String || name.isEmpty)) {
      return (index: index, key: 'modelNameInvalid');
    }
    for (final String field in _capacityFields) {
      final dynamic capacity = model[field];
      if (capacity != null && (capacity is! int || capacity <= 0)) {
        return (
          index: index,
          key: field == 'contextWindow'
              ? 'modelContextInvalid'
              : 'modelMaxTokensInvalid',
        );
      }
    }
  }
  return null;
}

/// What an interrogation needs, taken from the live form — mirrors React's
/// `ProbeTarget`: the endpoint the form currently shows, including a key
/// typed but not yet saved, so adding a provider is one pass.
class ProbeTarget {
  const ProbeTarget({
    required this.settingsNs,
    this.provider,
    this.baseURL,
    this.api,
    this.apiKey,
  });

  /// Settings namespace whose adapter family answers.
  final String settingsNs;

  /// Route being edited; an adapter that already describes it answers from
  /// its own registry with no endpoint needed.
  final String? provider;

  /// Endpoint as the form currently shows it.
  final String? baseURL;

  /// Wire protocol the form names.
  final String? api;

  /// Key typed into the form and not yet stored.
  final String? apiKey;

  /// A route the adapter describes answers without an endpoint; otherwise an
  /// endpoint is needed — mirrors React's `askable`.
  bool get askable =>
      (provider != null && provider!.isNotEmpty) ||
      (baseURL != null && baseURL!.isNotEmpty);
}

/// Model list of one provider profile, plus the action that asks the
/// provider what it serves — Flutter port of React `ModelListEditor.tsx`.
///
/// An empty list means "serve this route's built-in catalog"; any entry
/// replaces it, so rows are only ever added deliberately. Fetching asks the
/// endpoint the form currently shows and returns candidates the user picks
/// from — never configuration written behind them. A provider that cannot be
/// interrogated is not a dead end: the failure shows next to rows the user
/// can still fill in by hand.
class ModelListEditor extends ConsumerStatefulWidget {
  const ModelListEditor({
    super.key,
    required this.models,
    required this.overridden,
    required this.onChange,
    this.onReset,
    required this.probe,
    this.probeBlockedMessage,
    required this.onDiscover,
    required this.disabled,
    required this.t,
  });

  /// Rows as currently drafted (effective rows when inherited).
  final List<ModelDraft> models;

  /// Whether the user layer owns the whole array; reset returns to inherit.
  final bool overridden;

  /// Replace the drafted rows (materializes the user override).
  final ValueChanged<List<ModelDraft>> onChange;

  /// Remove the user-owned array and return to inheritance; null on create.
  final VoidCallback? onReset;

  /// Endpoint facts for the fetch action.
  final ProbeTarget probe;

  /// Why fetch is unavailable (e.g. the key field already refused), or null.
  final String? probeBlockedMessage;

  /// Interrogation face (production: `llm.discoverModels`); injected for tests.
  final Future<List<Map<String, dynamic>>> Function(ProbeTarget probe)
  onDiscover;

  /// Disable every control (read-only deployment or a pending write).
  final bool disabled;

  /// Section copy lookup.
  final String Function(String key) t;

  @override
  ConsumerState<ModelListEditor> createState() => _ModelListEditorState();
}

class _ModelListEditorState extends ConsumerState<ModelListEditor> {
  /// Text controllers keyed `id:<i>` / `name:<i>` / `ctx:<i>` / `max:<i>`,
  /// parent-owned so typing survives rebuilds. Reindexed on row removal
  /// (React's `reindexOnRemove`): only the row number moves.
  final Map<String, TextEditingController> _controllers = {};

  bool _busy = false;
  String? _failure;
  List<Map<String, dynamic>>? _candidates;
  final Set<String> _picked = {};
  String _query = '';
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.models);
  }

  @override
  void didUpdateWidget(covariant ModelListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.models, widget.models)) {
      _syncControllers(widget.models);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _textOf(ModelDraft model, String key) {
    final dynamic value = model[key];
    if (key == 'contextWindow' || key == 'maxTokens') {
      return value is int ? formatCapacity(value) : '';
    }
    return value is String ? value : '';
  }

  void _syncControllers(List<ModelDraft> models) {
    // Drop controllers past the end.
    final List<String> dead = [];
    for (final key in _controllers.keys) {
      final int at = int.tryParse(key.split(':').last) ?? -1;
      if (at < 0 || at >= models.length) dead.add(key);
    }
    for (final key in dead) {
      _controllers.remove(key)?.dispose();
    }
    // Seed missing controllers; resync ones whose row was replaced
    // underneath them (reset / inherited swap). Our own keystrokes already
    // updated controller and draft identically, so a mismatch means an
    // external replacement and the write is a no-op otherwise.
    for (int i = 0; i < models.length; i++) {
      for (final field in ['id', 'name', 'ctx', 'max']) {
        final String key = '$field:$i';
        final String modelKey = field == 'ctx'
            ? 'contextWindow'
            : field == 'max'
            ? 'maxTokens'
            : field;
        final String want = _textOf(models[i], modelKey);
        final TextEditingController? existing = _controllers[key];
        if (existing == null) {
          _controllers[key] = TextEditingController(text: want);
        } else if (existing.text != want) {
          existing.text = want;
        }
      }
    }
  }

  TextEditingController _controller(String key) => _controllers[key]!;

  void _patch(int index, Map<String, dynamic> next) {
    final List<ModelDraft> models = widget.models
        .map(Map<String, dynamic>.from)
        .toList();
    if (index < 0 || index >= models.length) return;
    final Map<String, dynamic> merged = {...models[index], ...next};
    // An emptied optional field leaves the profile instead of being stored
    // as a value the schema would reject — mirrors React's patch.
    merged.removeWhere(
      (k, v) =>
          _catalogFields.contains(k) &&
          (v == null || (v is String && v.isEmpty)),
    );
    // Unknown/hidden fields on the row survive: rebuild from the full row.
    models[index] = merged;
    widget.onChange(models);
  }

  void _editCapacity(int index, String field, String text) {
    final num? parsed = parseCapacity(text);
    _patch(index, {
      field: parsed == null
          ? null
          : parsed is int
          ? parsed
          : double.nan,
    });
  }

  void _removeAt(int index) {
    final List<ModelDraft> models = widget.models
        .map(Map<String, dynamic>.from)
        .toList();
    if (index < 0 || index >= models.length) return;
    models.removeAt(index);
    // Shift controllers down so surviving rows keep their typed text —
    // mirrors React's reindex (only the row number moves).
    final Map<String, TextEditingController> next = {};
    for (final entry in _controllers.entries) {
      final List<String> parts = entry.key.split(':');
      final int at = int.tryParse(parts.last) ?? -1;
      if (at == index) {
        entry.value.dispose();
        continue;
      }
      final String shifted = at > index
          ? '${parts.first}:${at - 1}'
          : entry.key;
      next[shifted] = entry.value;
    }
    _controllers
      ..clear()
      ..addAll(next);
    _expanded.remove(index);
    final Set<int> shiftedExpanded = {};
    for (final at in _expanded) {
      if (at > index) shiftedExpanded.add(at - 1);
    }
    _expanded
      ..clear()
      ..addAll(shiftedExpanded);
    widget.onChange(models);
  }

  Future<void> _fetchModels() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final List<Map<String, dynamic>> found = await widget.onDiscover(
        widget.probe,
      );
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() => _failure = widget.t('fetchEmpty'));
        return;
      }
      // Everything already configured starts unchecked, so adopting a
      // selection never silently rewrites a capacity the user corrected.
      final Set<String> known = {
        for (final m in widget.models)
          if (m['id'] is String) (m['id'] as String),
      };
      setState(() {
        _candidates = found;
        _picked
          ..clear()
          ..addAll([
            for (final c in found)
              if (c['id'] is String && !known.contains(c['id'])) c['id'],
          ]);
        _query = '';
      });
      await _openPicker();
    } catch (e) {
      if (!mounted) return;
      setState(() => _failure = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPicker() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _FetchDialog(
        candidates: _candidates ?? const [],
        picked: _picked,
        query: _query,
        t: widget.t,
        onQuery: (v) => setState(() => _query = v),
        onToggle: (id) => setState(() {
          _picked.contains(id) ? _picked.remove(id) : _picked.add(id);
        }),
        onToggleVisible: (ids, select) => setState(() {
          select ? _picked.addAll(ids) : _picked.removeAll(ids);
        }),
        onAdopt: () {
          _adoptPicked();
          Navigator.of(context).pop();
        },
      ),
    );
    if (mounted) {
      setState(() {
        _candidates = null;
        _picked.clear();
        _query = '';
      });
    }
  }

  void _adoptPicked() {
    final List<Map<String, dynamic>>? candidates = _candidates;
    if (candidates == null) return;
    final Map<String, ModelDraft> byId = {
      for (final m in widget.models)
        if (m['id'] is String) m['id'] as String: Map<String, dynamic>.from(m),
    };
    final List<String> order = [
      for (final m in widget.models)
        if (m['id'] is String) m['id'] as String,
    ];
    for (final c in candidates) {
      final dynamic rawId = c['id'];
      if (rawId is! String || !_picked.contains(rawId)) continue;
      // A row the user already tuned wins over the provider's numbers.
      if (!byId.containsKey(rawId)) {
        byId[rawId] = {
          'id': rawId,
          if (c['name'] is String) 'name': c['name'],
          if (c['contextWindow'] is int) 'contextWindow': c['contextWindow'],
          if (c['maxTokens'] is int) 'maxTokens': c['maxTokens'],
        };
        order.add(rawId);
      }
    }
    _syncControllersForAdopt(order);
    widget.onChange([for (final id in order) byId[id]!]);
  }

  /// Seed controllers for appended adopted rows; existing rows keep theirs.
  void _syncControllersForAdopt(List<String> order) {
    for (int i = 0; i < order.length; i++) {
      for (final field in ['id', 'name', 'ctx', 'max']) {
        _controllers.putIfAbsent('$field:$i', TextEditingController.new);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool fetchBlocked =
        widget.disabled ||
        _busy ||
        !widget.probe.askable ||
        widget.probeBlockedMessage != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.t('models'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              widget.overridden
                  ? widget.t('modelsCustomized')
                  : widget.t('modelsInherited'),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.overridden && widget.onReset != null)
              TextButton(
                onPressed: widget.disabled ? null : widget.onReset,
                child: Text(widget.t('restoreDefaults')),
              ),
            TextButton(
              onPressed: fetchBlocked ? null : _fetchModels,
              child: Text(
                _busy ? widget.t('fetching') : widget.t('fetchModels'),
              ),
            ),
          ],
        ),
        if (widget.models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              widget.t('modelsEmpty'),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (int i = 0; i < widget.models.length; i++)
          _ModelRow(
            key: ValueKey('model-row-$i'),
            index: i,
            idController: _controller('id:$i'),
            nameController: _controller('name:$i'),
            ctxController: _controller('ctx:$i'),
            maxController: _controller('max:$i'),
            expanded: _expanded.contains(i),
            disabled: widget.disabled,
            t: widget.t,
            onIdChanged: (v) => _patch(i, {'id': v}),
            onNameChanged: (v) => _patch(i, {'name': v}),
            onCtxChanged: (v) => _editCapacity(i, 'contextWindow', v),
            onMaxChanged: (v) => _editCapacity(i, 'maxTokens', v),
            onToggleExpanded: () => setState(() {
              _expanded.contains(i) ? _expanded.remove(i) : _expanded.add(i);
            }),
            onRemove: () => _removeAt(i),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: DsButton(
            variant: DsButtonVariant.ghost,
            size: DsButtonSize.md,
            label: widget.t('addModel'),
            onPressed: widget.disabled
                ? null
                : () => widget.onChange([
                    ...widget.models,
                    <String, dynamic>{'id': ''},
                  ]),
          ),
        ),
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _failure!,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    super.key,
    required this.index,
    required this.idController,
    required this.nameController,
    required this.ctxController,
    required this.maxController,
    required this.expanded,
    required this.disabled,
    required this.t,
    required this.onIdChanged,
    required this.onNameChanged,
    required this.onCtxChanged,
    required this.onMaxChanged,
    required this.onToggleExpanded,
    required this.onRemove,
  });

  final int index;
  final TextEditingController idController;
  final TextEditingController nameController;
  final TextEditingController ctxController;
  final TextEditingController maxController;
  final bool expanded;
  final bool disabled;
  final String Function(String key) t;
  final ValueChanged<String> onIdChanged;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onCtxChanged;
  final ValueChanged<String> onMaxChanged;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DsInput(
                  hintText: t('modelId'),
                  controller: idController,
                  enabled: !disabled,
                  onChanged: onIdChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DsInput(
                  hintText: t('modelName'),
                  controller: nameController,
                  enabled: !disabled,
                  onChanged: onNameChanged,
                ),
              ),
              IconButton(
                tooltip: t('modelAdvanced'),
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                ),
                onPressed: onToggleExpanded,
                style: IconButton.styleFrom(
                  minimumSize: const Size(28, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                tooltip: t('removeModel'),
                icon: const Icon(Icons.delete_outline, size: 16),
                color: Theme.of(context).colorScheme.error,
                onPressed: disabled ? null : onRemove,
                style: IconButton.styleFrom(
                  minimumSize: const Size(28, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DsInput(
                    label: t('modelContextWindow'),
                    hintText: '256K',
                    controller: ctxController,
                    enabled: !disabled,
                    onChanged: onCtxChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DsInput(
                    label: t('modelMaxTokens'),
                    hintText: '32K',
                    controller: maxController,
                    enabled: !disabled,
                    onChanged: onMaxChanged,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FetchDialog extends StatefulWidget {
  const _FetchDialog({
    required this.candidates,
    required this.picked,
    required this.query,
    required this.t,
    required this.onQuery,
    required this.onToggle,
    required this.onToggleVisible,
    required this.onAdopt,
  });

  final List<Map<String, dynamic>> candidates;
  final Set<String> picked;
  final String query;
  final String Function(String key) t;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onToggle;
  final void Function(List<String> ids, bool select) onToggleVisible;
  final VoidCallback onAdopt;

  @override
  State<_FetchDialog> createState() => _FetchDialogState();
}

class _FetchDialogState extends State<_FetchDialog> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String q = widget.query.trim().toLowerCase();
    final List<Map<String, dynamic>> visible = q.isEmpty
        ? widget.candidates
        : widget.candidates.where((c) {
            final String id = (c['id'] as String? ?? '').toLowerCase();
            final String name = (c['name'] as String? ?? '').toLowerCase();
            return id.contains(q) || name.contains(q);
          }).toList();
    final List<String> visibleIds = [
      for (final c in visible)
        if (c['id'] is String) c['id'] as String,
    ];
    final bool allPicked =
        visibleIds.isNotEmpty && visibleIds.every(widget.picked.contains);
    return AlertDialog(
      title: Text(widget.t('fetchTitle')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DsInput(
                    hintText: widget.t('fetchSearch'),
                    controller: _search,
                    onChanged: (v) => setState(() => widget.onQuery(v)),
                  ),
                ),
                const SizedBox(width: 8),
                DsButton(
                  variant: DsButtonVariant.ghost,
                  size: DsButtonSize.md,
                  label: widget.t(
                    allPicked ? 'fetchDeselectAll' : 'fetchSelectAll',
                  ),
                  onPressed: visibleIds.isEmpty
                      ? null
                      : () => setState(
                          () => widget.onToggleVisible(visibleIds, !allPicked),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: visibleIds.isEmpty
                  ? Text(widget.t('fetchNoMatches'))
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final id in visibleIds)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                id,
                                style: const TextStyle(fontSize: 13),
                              ),
                              value: widget.picked.contains(id),
                              onChanged: (_) =>
                                  setState(() => widget.onToggle(id)),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        DsButton(
          variant: DsButtonVariant.ghost,
          size: DsButtonSize.md,
          label: widget.t('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        DsButton(
          variant: DsButtonVariant.ghost,
          size: DsButtonSize.md,
          label: widget.t('fetchAdopt'),
          onPressed: widget.onAdopt,
        ),
      ],
    );
  }
}
