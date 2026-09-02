/// Shared form model behind every plugin card.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/card-form.ts`:
/// staged edits over one settings namespace, revision-fenced writes via
/// [SettingsScope], overridden detection via user-layer presence, invalid
/// blocking save, and retained drafts on failure.
library;

import 'package:flutter/foundation.dart';

import '../../core/settings/settings_scope.dart';

/// The write one field's staged text performs when the card is saved.
sealed class FieldWrite {
  const FieldWrite();
}

/// Set a value.
class FieldWriteSet extends FieldWrite {
  const FieldWriteSet(this.value);
  final Object? value;
}

/// Clear back to composition layer.
class FieldWriteClear extends FieldWrite {
  const FieldWriteClear();
}

/// How one section field converts between stored value and draft text.
class CardFieldSpec {
  /// Creates spec for [field].
  const CardFieldSpec({
    required this.field,
    required this.format,
    required this.parse,
  });

  /// Field name inside namespace section.
  final String field;

  /// Render stored value as draft text; empty when section carries none.
  final String Function(Object? value) format;

  /// The write this draft stages, or null when draft is invalid.
  final FieldWrite? Function(String text) parse;
}

/// A control whose value is written outside settings section (credentials).
class CardSecretSpec {
  const CardSecretSpec({required this.field, required this.write});

  /// Field name addressing this control inside the card's form.
  final String field;

  /// Write staged text; true if host accepted.
  final Future<bool> Function(String text) write;
}

/// One field as a control renders it.
class CardFieldState {
  const CardFieldState({
    required this.text,
    required this.overridden,
    required this.invalid,
  });

  final String text;
  final bool overridden;
  final bool invalid;
}

/// Form state every plugin card shares.
class CardShell {
  const CardShell({
    required this.available,
    required this.writable,
    required this.dirty,
    required this.invalid,
    required this.saving,
    required this.failed,
  });

  final bool available;
  final bool writable;
  final bool dirty;
  final bool invalid;
  final bool saving;
  final bool failed;
}

/// One field's staged edit.
class _StagedEdit {
  const _StagedEdit({required this.text, required this.clear});
  final String text;
  final bool clear;
}

/// Planned write with optional run; null run means invalid.
class _PlannedWrite {
  const _PlannedWrite({required this.field, required this.run});
  final String field;
  final Future<bool> Function()? run;
}

/// Whole-number field. Empty draft clears; non-finite blocks save.
CardFieldSpec numberField(String field) => CardFieldSpec(
      field: field,
      format: (Object? value) => value is num ? value.toString() : '',
      parse: (String text) {
        final String trimmed = text.trim();
        if (trimmed.isEmpty) return const FieldWriteClear();
        final num? parsed = num.tryParse(trimmed);
        if (parsed != null && parsed.isFinite) {
          return FieldWriteSet(parsed);
        }
        return null;
      },
    );

/// Free-text field. Empty draft clears.
CardFieldSpec textField(String field) => CardFieldSpec(
      field: field,
      format: (Object? value) => value is String ? value : '',
      parse: (String text) {
        final String trimmed = text.trim();
        if (trimmed.isEmpty) return const FieldWriteClear();
        return FieldWriteSet(trimmed);
      },
    );

/// Boolean field stored as `bool` — rendered as 'true'/'false' strings.
CardFieldSpec boolField(String field) => CardFieldSpec(
      field: field,
      format: (Object? value) {
        if (value is bool) return value ? 'true' : 'false';
        if (value is String) return value;
        if (value is num) return value != 0 ? 'true' : 'false';
        return '';
      },
      parse: (String text) {
        final String trimmed = text.trim().toLowerCase();
        if (trimmed.isEmpty) return const FieldWriteClear();
        if (trimmed == 'true' || trimmed == 'false' || trimmed == '1' || trimmed == '0') {
          return FieldWriteSet(trimmed == 'true' || trimmed == '1');
        }
        return null;
      },
    );

/// Stages one card's edits over one settings namespace and writes them on save.
///
/// Notifies listeners via ChangeNotifier semantics so widgets can rebuild.
/// Every projection is rebuilt from scope + drafts.
class CardForm<T> extends ChangeNotifier {
  CardForm({
    required SettingsScope<T> scope,
    required List<CardFieldSpec> specs,
    List<CardSecretSpec> secrets = const [],
  })  : _scope = scope,
        _specs = {for (final s in specs) s.field: s},
        _secretSpecs = {for (final s in secrets) s.field: s} {
    _scope.subscribe((_) => notifyListeners());
  }

  final SettingsScope<T> _scope;
  final Map<String, CardFieldSpec> _specs;
  final Map<String, CardSecretSpec> _secretSpecs;
  final Map<String, _StagedEdit> _staged = {};
  bool _saving = false;
  bool _failed = false;

  /// Current shell state: availability, writability, dirty/invalid/saving/failed.
  CardShell shell() {
    final snapshot = _scope.snapshot;
    final List<_PlannedWrite> plan = _plan();
    return CardShell(
      available: snapshot.status == SettingsScopeStatus.ready,
      writable: snapshot.writable,
      dirty: plan.isNotEmpty,
      invalid: plan.any((item) => item.run == null),
      saving: _saving,
      failed: _failed,
    );
  }

  /// One control's state.
  CardFieldState field(String field) {
    final _StagedEdit? staged = _staged[field];
    if (_secretSpecs.containsKey(field)) {
      return CardFieldState(
        text: staged?.text ?? '',
        overridden: false,
        invalid: false,
      );
    }
    final CardFieldSpec spec = _specOrThrow(field);
    if (staged == null) {
      return CardFieldState(
        text: spec.format(_sectionValue(field)),
        overridden: _stored(field),
        invalid: false,
      );
    }
    final FieldWrite? write =
        staged.clear ? const FieldWriteClear() : spec.parse(staged.text);
    return CardFieldState(
      text: staged.text,
      overridden: write is FieldWriteSet,
      invalid: write == null,
    );
  }

  /// Stage draft text for one field.
  void edit(String field, String text) {
    _stage(field, _StagedEdit(text: text, clear: false));
  }

  /// Stage a clear, so saving lets field re-inherit composition layer.
  void resetField(String field) {
    final String baseText = _specOrThrow(field).format(_baseValue(field));
    _stage(field, _StagedEdit(text: baseText, clear: true));
  }

  /// Write every staged edit, then re-seed from what host accepted.
  Future<void> save() async {
    final List<_PlannedWrite> plan = _plan();
    final List<Future<bool> Function()> writes = <Future<bool> Function()>[
      for (final item in plan) if (item.run != null) item.run!,
    ];
    if (plan.isEmpty || _saving || writes.length != plan.length) return;
    _saving = true;
    _failed = false;
    notifyListeners();
    bool landed = true;
    for (final w in writes) {
      final bool ok = await w();
      landed = ok && landed;
    }
    if (landed) _staged.clear();
    _saving = false;
    _failed = !landed;
    notifyListeners();
  }

  /// Drop every staged edit.
  void discard() {
    if (_staged.isEmpty && !_failed) return;
    _staged.clear();
    _failed = false;
    notifyListeners();
  }

  List<_PlannedWrite> _plan() {
    final List<_PlannedWrite> plan = [];
    for (final MapEntry<String, _StagedEdit> entry in _staged.entries) {
      final String field = entry.key;
      final _StagedEdit staged = entry.value;
      final CardSecretSpec? secret = _secretSpecs[field];
      if (secret != null) {
        final String value = staged.text.trim();
        if (value.isNotEmpty) {
          plan.add(_PlannedWrite(field: field, run: () => secret.write(value)));
        }
        continue;
      }
      final CardFieldSpec spec = _specOrThrow(field);
      if (staged.clear) {
        if (_stored(field)) {
          plan.add(_PlannedWrite(field: field, run: () => _clear(field)));
        }
        continue;
      }
      if (staged.text == spec.format(_sectionValue(field))) continue;
      final FieldWrite? write = spec.parse(staged.text);
      if (write == null) {
        plan.add(const _PlannedWrite(field: '', run: null));
        // Use field-specific invalid entry; preserve field name for diagnostics.
        plan[plan.length - 1] = _PlannedWrite(field: field, run: null);
      } else if (write is FieldWriteClear) {
        plan.add(_PlannedWrite(field: field, run: () => _clear(field)));
      } else if (write is FieldWriteSet) {
        plan.add(_PlannedWrite(field: field, run: () => _store(field, write.value)));
      }
    }
    return plan;
  }

  Future<bool> _clear(String field) async {
    await _scope.unset(field);
    return !_stored(field);
  }

  Future<bool> _store(String field, Object? value) async {
    await _scope.set(field, value);
    final Map<String, Object?>? user = _userLayer();
    return user != null && user[field] == value;
  }

  void _stage(String field, _StagedEdit edit) {
    _staged[field] = edit;
    _failed = false;
    notifyListeners();
  }

  CardFieldSpec _specOrThrow(String field) {
    final CardFieldSpec? spec = _specs[field];
    if (spec == null) throw StateError('plugin card has no field $field');
    return spec;
  }

  SettingsScopeSnapshot<T> _snapshotOf() => _scope.snapshot;

  Object? _sectionValue(String field) {
    final Object? value = _snapshotOf().value;
    if (value is Map<String, Object?>) return value[field];
    if (value is Map) return value[field];
    return null;
  }

  Object? _baseValue(String field) {
    final Map<String, Object?>? base = _snapshotOf().base;
    if (base == null) return null;
    return base[field];
  }

  Map<String, Object?>? _userLayer() => _snapshotOf().user;

  bool _stored(String field) {
    final Map<String, Object?>? user = _userLayer();
    if (user == null) return false;
    return user.containsKey(field);
  }
}
