/// Slot composition ledger mirrored from `packages/client/ui-slots/src/index.ts`
/// (`SlotCore`) and the `SlotRegistry` service face in
/// `packages/client/runtime/src/client/slots.ts`.
///
/// One registration API: [SlotRegistry.register] contributes a component into a
/// declared slot; a parent entry's `children` table is both the declaration and
/// the authorization for child slots. Disposing a registration cascades the
/// collapse of every child slot it declared. Pure Dart on purpose: the render
/// machinery ([package:dsh_flutter/src/core/renderer/slot_outlet.dart]) reads
/// this ledger; nothing here imports Flutter, exactly as `ui-slots` stays
/// framework-machinery-free on the React side.
library;

import 'package:meta/meta.dart';

/// Slot cardinality, mirrored from `SlotKind`.
enum SlotKind {
  /// One occupant cell.
  single,

  /// Ordered occupant list; display refines equal priorities by [RegistrationOptions.order].
  list,

  /// Key-dispatched cells; one cell per [RegistrationOptions.key].
  keyed,

  /// Selector-routed chain; election consumes every entry, shadowing does not apply.
  chain,
}

/// Data visibility scope, mirrored from `SlotScope`.
enum SlotScope {
  /// Rendered once for the whole app (only the shell renders `'root'`).
  root,

  /// Rendered with a session when one is selected, without otherwise.
  sessionMaybe,

  /// Always rendered inside a selected session.
  session,
}

/// Declaration record for one slot key: kind + scope, mirrored from `SlotEntryDef`.
@immutable
class SlotSpec {
  /// Creates a declaration.
  const SlotSpec({required this.kind, required this.scope});

  /// Cardinality.
  final SlotKind kind;

  /// Data scope.
  final SlotScope scope;
}

/// Owner-supplied selection function for chain slots, mirrored from
/// `ChainSelect`: `(owner) => M | null`. Returning null abdicates the entry's
/// turn; election continues down the chain in priority order.
typedef ChainSelect = Object? Function(Object? owner);

/// Registration options, mirrored from `SlotCore.register`'s first argument.
@immutable
class RegistrationOptions {
  /// Creates options for one register call.
  const RegistrationOptions({
    required this.name,
    this.children,
    this.store,
    this.registrant,
    this.key,
    this.id,
    this.order,
    this.priority,
    this.select,
  });

  /// Target slot key, named `<domain>.<entry>.<hole>`.
  final String name;

  /// Child-slot declarations: keys here become renderable and authorized for
  /// exactly this entry; declaring an already-declared key throws at load.
  final Map<String, SlotSpec>? children;

  /// Shared store handle (any non-function object) or exclusive factory
  /// (function). A shared handle pins to one [SlotScope] for its lifetime.
  final Object? store;

  /// Diagnostics label stamped into conflict messages.
  final String? registrant;

  /// Required for keyed slots.
  final String? key;

  /// Required for list slots.
  final String? id;

  /// List display refinement within equal priorities.
  final int? order;

  /// Cell shadowing rank (ascending, default 0, lowest renders). Same-cell
  /// same-priority double registration throws; a different priority shadows.
  final int? priority;

  /// Required for chain slots: selects the matched model or abdicates.
  final ChainSelect? select;
}

/// One live registration in the ledger, mirrored from `StoredEntry`.
class SlotEntry {
  SlotEntry._({required this.options, required this.component});

  /// Original options; priority defaults applied only at read sites.
  final RegistrationOptions options;

  /// The contributed component value; the render layer owns its concrete type.
  final Object component;

  /// Effective priority (0 default).
  int get priority => options.priority ?? 0;
}

/// Unsubscriber returned by registering calls, mirrored from the TS disposer.
///
/// Removing a registration also cascades collapse of every child slot its
/// `children` table declared (recursively disposing their occupants).
typedef Disposer = void Function();

/// Transactional multi-registration callback result for [SlotRegistry.inject]:
/// every yielded disposer installs atomically and tears down in reverse order.
typedef SlotInjectionEffect = List<Disposer> Function();

/// Listener notified with the changed slot key after any ledger mutation.
typedef SlotChangedListener = void Function(String key);

/// One slot key's mutable record, mirrored from `SlotRecord`.
class _SlotRecord {
  SlotSpec? spec;
  String? declaredBy;
  String? parent;
  final List<SlotEntry> entries = [];
}

class _HandlePin {
  _HandlePin(this.scope, this.count);
  final SlotScope scope;
  int count;
}

/// The composition ledger, mirroring `SlotCore.register` validation order and
/// the `SlotRegistry` service surface (`inject`, winners, inspection, events).
class SlotRegistry {
  SlotRegistry() {
    // Built-in seed from ui-slots: only the shell renders 'root'.
    _record('root').spec = const SlotSpec(
      kind: SlotKind.single,
      scope: SlotScope.root,
    );
    _record('root').declaredBy = 'built-in';
  }

  final Map<String, _SlotRecord> _records = {};
  final Map<Object, _HandlePin> _handleScopes = {};
  final Map<String, List<_PendingInjection>> _pendingInjections = {};
  final List<SlotChangedListener> _changedListeners = [];

  int _version = 0;

  /// Monotonic mutation counter; render machinery compares it between frames.
  int get version => _version;

  /// Subscribes to ledger mutations; receives the changed slot key.
  Disposer onChanged(SlotChangedListener listener) {
    _changedListeners.add(listener);
    return () => _changedListeners.remove(listener);
  }

  void _markDirty(String key) {
    _version++;
    for (final listener in List.of(_changedListeners)) {
      listener(key);
    }
  }

  _SlotRecord _record(String key) => _records.putIfAbsent(key, _SlotRecord.new);

  /// Whether [key] currently has a live declaration.
  bool isDeclared(String key) => _records[key]?.spec != null;

  /// The live declaration for [key], or null while undeclared.
  SlotSpec? specOf(String key) => _records[key]?.spec;

  /// Who declared [key], for conflict messages and diagnostics.
  String? declaredByOf(String key) => _records[key]?.declaredBy;

  /// Contributes [component] into the slot named [options.name].
  ///
  /// Throws [ArgumentError] when the slot is not declared, when kind-specific
  /// requirements are unmet, when the same cell is occupied twice at the same
  /// priority, or when a child key is already declared elsewhere. A shared
  /// [RegistrationOptions.store] handle mounted under a second scope throws.
  ///
  /// Returns a disposer whose invocation cascades the collapse of the children
  /// this call declared.
  Disposer register(RegistrationOptions options, Object component) {
    final rec = _record(options.name);
    final spec = rec.spec;
    if (spec == null) {
      throw ArgumentError.value(
        options.name,
        'name',
        'slot is not declared (a parent entry\'s children table must declare it)',
      );
    }
    final priority = options.priority ?? 0;
    String occupantHint(SlotEntry occupant) =>
        'at priority $priority${occupant.options.registrant != null ? ' (registered by ${occupant.options.registrant})' : ''}'
        ' — register at a different priority to shadow it (lowest renders)';
    switch (spec.kind) {
      case SlotKind.single:
        final occupant = rec.entries
            .whereType<SlotEntry>()
            .where((e) => e.priority == priority)
            .firstOrNull;
        if (occupant != null) {
          throw StateError(
            'single slot "${options.name}" already has a registration ${occupantHint(occupant)}',
          );
        }
      case SlotKind.keyed:
        final key = options.key;
        if (key == null) {
          throw ArgumentError(
            'keyed slot "${options.name}" requires options.key',
          );
        }
        final occupant = rec.entries
            .where((e) => e.options.key == key && e.priority == priority)
            .firstOrNull;
        if (occupant != null) {
          throw StateError(
            'keyed slot "${options.name}" already has an entry for key "$key" ${occupantHint(occupant)}',
          );
        }
      case SlotKind.list:
        final id = options.id;
        if (id == null) {
          throw ArgumentError(
            'list slot "${options.name}" requires options.id',
          );
        }
        final occupant = rec.entries
            .where((e) => e.options.id == id && e.priority == priority)
            .firstOrNull;
        if (occupant != null) {
          throw StateError(
            'list slot "${options.name}" already has an entry with id "$id" ${occupantHint(occupant)}',
          );
        }
      case SlotKind.chain:
        if (options.select == null) {
          throw ArgumentError(
            'chain slot "${options.name}" requires options.select',
          );
        }
    }
    if (options.children != null) {
      for (final childKey in options.children!.keys) {
        final childRec = _records[childKey];
        if (childRec?.spec != null) {
          throw StateError(
            'slot "$childKey" is already declared (by ${childRec!.declaredBy ?? 'an unknown entry'})',
          );
        }
      }
    }
    // Shared handles pin their scope on first mount; factories are exempt.
    final store = options.store;
    if (store != null && store is! Function) {
      final pinned = _handleScopes[store];
      if (pinned != null && pinned.scope != spec.scope) {
        throw StateError(
          'store handle mounted under "${options.name}" (scope "${spec.scope}") '
          'is already mounted under scope "${pinned.scope}" — one handle, one scope',
        );
      }
      if (pinned != null) {
        pinned.count += 1;
      } else {
        _handleScopes[store] = _HandlePin(spec.scope, 1);
      }
    }

    final entry = SlotEntry._(options: options, component: component);
    rec.entries.add(entry);
    _sortEntries(rec.entries, spec.kind);
    _markDirty(options.name);

    final children = options.children;
    if (children != null) {
      final declarations = <String, _SlotRecord>{};
      for (final MapEntry(key: childKey, value: childSpec)
          in children.entries) {
        final childRec = _record(childKey);
        childRec.spec = childSpec;
        childRec.declaredBy =
            'an entry in "${options.name}"'
            '${options.registrant != null ? ' (${options.registrant})' : ''}';
        childRec.parent = options.name;
        declarations[childKey] = childRec;
      }
      // Publish only after the whole children table owns its declarations, then
      // resolve anything queued against the freshly declared keys.
      for (final childKey in declarations.keys) {
        _markDirty(childKey);
      }
      for (final childKey in declarations.keys) {
        _resolveInjections(childKey);
      }
    }
    return () {
      if (!rec.entries.contains(entry)) return;
      rec.entries.remove(entry);
      _markDirty(options.name);
      _releaseEntry(entry);
    };
  }

  void _sortEntries(List<SlotEntry> entries, SlotKind kind) {
    entries.sort((a, b) {
      final byPriority = a.priority.compareTo(b.priority);
      if (kind == SlotKind.list && byPriority == 0) {
        return (a.options.order ?? 0).compareTo(b.options.order ?? 0);
      }
      return byPriority;
    });
  }

  /// Removes [entry]'s side state: store pins and declared children (cascade).
  void _releaseEntry(SlotEntry entry) {
    final store = entry.options.store;
    if (store != null && store is! Function) {
      final pin = _handleScopes[store];
      if (pin != null) {
        pin.count -= 1;
        if (pin.count <= 0) _handleScopes.remove(store);
      }
    }
    final children = entry.options.children;
    if (children != null) {
      for (final childKey in children.keys) {
        _collapse(childKey, visited: {});
      }
    }
  }

  /// Clears [key]'s declaration and disposes every occupant, recursively
  /// collapsing their own declared children. Pending injections for collapsed
  /// keys retire their contributions until a redeclaration arrives.
  void _collapse(String key, {required Set<String> visited}) {
    if (visited.contains(key)) return;
    visited.add(key);
    final rec = _records[key];
    if (rec == null || rec.spec == null) return;
    final occupants = List.of(rec.entries);
    rec.entries.clear();
    rec.spec = null;
    rec.declaredBy = null;
    rec.parent = null;
    _markDirty(key);
    for (final occupant in occupants) {
      _releaseEntry(occupant);
    }
    _retireInjections(key);
  }

  /// Raw ledger view for [key]: entries in sorted sequence; empty when
  /// undeclared so callers may probe ahead of plugin load order.
  List<SlotEntry> entries(String key) =>
      List.unmodifiable(_records[key]?.entries ?? const []);

  /// Winners per occupied cell, mirrored from `entriesOfSlot`: the first
  /// entry of each cell in priority order (single: one cell; keyed: one per
  /// key; list: one per id). Chain keys return raw entries unchanged.
  List<SlotEntry> winnersOfSlot(String key) {
    final rec = _records[key];
    if (rec == null || rec.spec == null) return const [];
    if (rec.spec!.kind == SlotKind.chain) return List.unmodifiable(rec.entries);
    final seenCells = <String>{};
    final winners = <SlotEntry>[];
    for (final entry in rec.entries) {
      final cell = switch (rec.spec!.kind) {
        SlotKind.single => '',
        SlotKind.keyed => entry.options.key ?? '<null>',
        SlotKind.list => entry.options.id ?? '<null>',
        // Chain keys return early above; election consumes every entry and
        // shadowing cells do not apply.
        SlotKind.chain => throw StateError(
          'chain slot "$key" reached winner projection',
        ),
      };
      if (!seenCells.add(cell)) continue;
      winners.add(entry);
    }
    return winners;
  }

  static const unreachableCell = '';

  /// Runs [effect] whenever [key] is declared, retiring its contributions when
  /// the declaration collapses and rerunning after redeclaration — the
  /// `slots.inject` contract. Failures retire that injection permanently and
  /// surface through [onInjectionError].
  Disposer inject(String key, SlotInjectionEffect effect) {
    final pending = _PendingInjection(effect);
    _pendingInjections.putIfAbsent(key, () => []).add(pending);
    if (isDeclared(key)) {
      _run(pending, key);
    }
    return () {
      final list = _pendingInjections[key];
      if (list == null) return;
      list.remove(pending);
      if (list.isEmpty) _pendingInjections.remove(key);
      pending.disposeAll();
    };
  }

  /// Receives injection-effect failures; a failed injection is retired
  /// permanently (mirrors the TS fail-permanent posture).
  void Function(Object error, String key)? onInjectionError;

  void _resolveInjections(String key) {
    final list = _pendingInjections[key];
    if (list == null) return;
    for (final pending in List.of(list)) {
      if (!pending.installed) _run(pending, key);
    }
  }

  void _retireInjections(String key) {
    final list = _pendingInjections[key];
    if (list == null) return;
    for (final pending in list) {
      pending.disposeAll();
      pending.installed = false;
    }
  }

  void _run(_PendingInjection pending, String key) {
    try {
      pending.replace(pending.effect());
      pending.installed = true;
    } catch (error) {
      onInjectionError?.call(error, key);
      pending.disposeAll();
      final list = _pendingInjections[key];
      list?.remove(pending);
    }
  }
}

class _PendingInjection {
  _PendingInjection(this.effect);

  final SlotInjectionEffect effect;
  List<Disposer> _disposers = [];
  bool installed = false;

  void replace(List<Disposer> next) {
    disposeAll();
    _disposers = next;
  }

  void disposeAll() {
    for (final disposer in _disposers.reversed) {
      disposer();
    }
    _disposers = [];
    installed = false;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
