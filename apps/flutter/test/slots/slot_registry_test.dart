import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SlotRegistry registry;

  setUp(() => registry = SlotRegistry());

  /// Declares `root` with a child table, the minimal legal boot shape.
  void declareRoot({Map<String, SlotSpec>? children}) {
    registry.register(
      RegistrationOptions(name: 'root', children: children),
      'shell-component',
    );
  }

  group('register validation', () {
    test('rejects registration into an undeclared slot', () {
      expect(
        () => registry.register(const RegistrationOptions(name: 'nope'), 'x'),
        throwsArgumentError,
      );
    });

    test('single slot: same-priority double registration throws naming the occupant', () {
      declareRoot(
        children: {
          'app.header': const SlotSpec(
            kind: SlotKind.single,
            scope: SlotScope.root,
          ),
        },
      );
      registry.register(
        RegistrationOptions(name: 'app.header', registrant: 'first'),
        'a',
      );
      expect(
        () => registry.register(
          RegistrationOptions(name: 'app.header', registrant: 'second'),
          'b',
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError && e.message.contains('(registered by first)'),
          ),
        ),
      );
    });

    test('single slot: a different priority shadows instead of throwing', () {
      declareRoot(
        children: {
          'app.header': const SlotSpec(
            kind: SlotKind.single,
            scope: SlotScope.root,
          ),
        },
      );
      registry.register(const RegistrationOptions(name: 'app.header'), 'base');
      registry.register(
        const RegistrationOptions(name: 'app.header', priority: -1),
        'override',
      );
      final winners = registry.winnersOfSlot('app.header');
      expect(winners.single.component, 'override');
    });

    test(
      'keyed slot requires key; list slot requires id; chain requires select',
      () {
        declareRoot(
          children: {
            'k.slot': const SlotSpec(
              kind: SlotKind.keyed,
              scope: SlotScope.session,
            ),
            'l.slot': const SlotSpec(
              kind: SlotKind.list,
              scope: SlotScope.session,
            ),
            'c.slot': const SlotSpec(
              kind: SlotKind.chain,
              scope: SlotScope.session,
            ),
          },
        );
        expect(
          () =>
              registry.register(const RegistrationOptions(name: 'k.slot'), 'x'),
          throwsArgumentError,
        );
        expect(
          () =>
              registry.register(const RegistrationOptions(name: 'l.slot'), 'x'),
          throwsArgumentError,
        );
        expect(
          () =>
              registry.register(const RegistrationOptions(name: 'c.slot'), 'x'),
          throwsArgumentError,
        );
        expect(
          () => registry.register(
            RegistrationOptions(name: 'c.slot', select: (owner) => null),
            'x',
          ),
          returnsNormally,
        );
      },
    );

    test('declaring an already-declared child throws naming the declarer', () {
      // List slots allow multiple coexisting entries, so both declarers reach
      // the children validation.
      declareRoot(
        children: {
          'p.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
        },
      );
      registry.register(
        RegistrationOptions(
          name: 'p.slot',
          id: 'first',
          children: {
            'app.body': const SlotSpec(
              kind: SlotKind.single,
              scope: SlotScope.root,
            ),
          },
          registrant: 'original',
        ),
        'one',
      );
      expect(
        () => registry.register(
          RegistrationOptions(
            name: 'p.slot',
            id: 'second',
            children: {
              'app.body': const SlotSpec(
                kind: SlotKind.single,
                scope: SlotScope.root,
              ),
            },
            registrant: 'impostor',
          ),
          'two',
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError &&
                e.message.contains(
                  'already declared (by an entry in "p.slot" (original))',
                ),
          ),
        ),
      );
    });
  });

  group('store handle scope pinning', () {
    test('one shared handle under two scopes throws', () {
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
          'b.slot': const SlotSpec(
            kind: SlotKind.list,
            scope: SlotScope.session,
          ),
        },
      );
      final handle = Object();
      registry.register(
        RegistrationOptions(name: 'a.slot', id: 'one', store: handle),
        'x',
      );
      expect(
        () => registry.register(
          RegistrationOptions(name: 'b.slot', id: 'two', store: handle),
          'y',
        ),
        throwsA(
          predicate(
            (e) =>
                e is StateError && e.message.contains('one handle, one scope'),
          ),
        ),
      );
    });

    test('handle pin releases on dispose so it can remount elsewhere', () {
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
        },
      );
      final handle = Object();
      final dispose = registry.register(
        RegistrationOptions(name: 'a.slot', id: 'one', store: handle),
        'x',
      );
      dispose();
      expect(
        () => registry.register(
          RegistrationOptions(name: 'a.slot', id: 'two', store: handle),
          'y',
        ),
        returnsNormally,
      );
    });

    test('factory stores are exempt from scope pinning', () {
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
          'b.slot': const SlotSpec(
            kind: SlotKind.list,
            scope: SlotScope.session,
          ),
        },
      );
      Object factory() => Object;
      registry.register(
        RegistrationOptions(name: 'a.slot', id: 'one', store: factory),
        'x',
      );
      expect(
        () => registry.register(
          RegistrationOptions(name: 'b.slot', id: 'two', store: factory),
          'y',
        ),
        returnsNormally,
      );
    });
  });

  group('disposal and cascade collapse', () {
    test('dispose removes only its own entry', () {
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
        },
      );
      final d1 = registry.register(
        const RegistrationOptions(name: 'a.slot', id: 'one'),
        'x',
      );
      registry.register(
        const RegistrationOptions(name: 'a.slot', id: 'two'),
        'y',
      );
      d1();
      expect(registry.entries('a.slot').map((e) => e.component), ['y']);
    });

    test('dispose is idempotent', () {
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
        },
      );
      final d = registry.register(
        const RegistrationOptions(name: 'a.slot', id: 'one'),
        'x',
      );
      d();
      expect(d, returnsNormally);
    });

    test('disposing a parent collapses declared children and their occupants recursively', () {
      registry.register(
        RegistrationOptions(
          name: 'root',
          children: {
            'parent.slot': const SlotSpec(
              kind: SlotKind.single,
              scope: SlotScope.root,
            ),
          },
        ),
        'shell',
      );
      final disposeParentEntry = registry.register(
        RegistrationOptions(
          name: 'parent.slot',
          children: {
            'child.slot': const SlotSpec(
              kind: SlotKind.list,
              scope: SlotScope.root,
            ),
          },
        ),
        'parent-component',
      );
      final disposeChildOccupant = registry.register(
        const RegistrationOptions(name: 'child.slot', id: 'leaf'),
        'leaf-component',
      );

      disposeParentEntry();

      expect(registry.isDeclared('child.slot'), isFalse);
      expect(registry.entries('child.slot'), isEmpty);
      expect(
        disposeChildOccupant,
        returnsNormally,
      ); // stale disposer is a no-op
    });
  });

  group('winners and ordering', () {
    test('list keeps ledger sequence by priority then order', () {
      declareRoot(
        children: {
          'dock.items': const SlotSpec(
            kind: SlotKind.list,
            scope: SlotScope.root,
          ),
        },
      );
      registry.register(
        const RegistrationOptions(name: 'dock.items', id: 'c', order: 2),
        'C',
      );
      registry.register(
        const RegistrationOptions(name: 'dock.items', id: 'a', priority: -1),
        'A',
      );
      registry.register(
        const RegistrationOptions(name: 'dock.items', id: 'b', order: 1),
        'B',
      );
      expect(
        registry.winnersOfSlot('dock.items').map((e) => e.component).toList(),
        ['A', 'B', 'C'],
      );
    });

    test('keyed winners are one per key, lowest priority wins each cell', () {
      declareRoot(
        children: {
          'chat.node': const SlotSpec(
            kind: SlotKind.keyed,
            scope: SlotScope.session,
          ),
        },
      );
      registry.register(
        const RegistrationOptions(name: 'chat.node', key: 'tool'),
        'tool-v1',
      );
      registry.register(
        const RegistrationOptions(name: 'chat.node', key: 'goal'),
        'goal',
      );
      registry.register(
        const RegistrationOptions(name: 'chat.node', key: 'tool', priority: -1),
        'tool-v0',
      );
      expect(
        registry.winnersOfSlot('chat.node').map((e) => e.component).toList(),
        ['tool-v0', 'goal'],
      );
    });

    test('chain returns raw entries for election rather than winners', () {
      declareRoot(
        children: {
          'composer.bar': const SlotSpec(
            kind: SlotKind.chain,
            scope: SlotScope.sessionMaybe,
          ),
        },
      );
      Object? selectLow(Object? owner) => 'low';
      Object? selectHigh(Object? owner) => null;
      registry.register(
        RegistrationOptions(
          name: 'composer.bar',
          select: selectHigh,
          priority: 5,
        ),
        'high',
      );
      registry.register(
        RegistrationOptions(
          name: 'composer.bar',
          select: selectLow,
          priority: 1,
        ),
        'low',
      );
      expect(registry.winnersOfSlot('composer.bar').length, 2);
    });
  });

  group('inject contribution queue', () {
    test('waits for declaration, installs, retires on collapse, reruns on redeclare', () {
      var runs = 0;
      var disposed = 0;
      final stop = registry.inject('late.slot', () {
        runs++;
        return [() => disposed++];
      });
      expect(runs, 0);

      final disposeShell = registry.register(
        RegistrationOptions(
          name: 'root',
          children: {
            'late.slot': const SlotSpec(
              kind: SlotKind.list,
              scope: SlotScope.root,
            ),
          },
        ),
        'shell',
      );
      expect(runs, 1);
      expect(disposed, 0);

      // Collapse removes the declaration and retires the contribution.
      disposeShell();
      expect(disposed, 1);

      // Redeclaration reruns the still-registered injection.
      registry.register(
        RegistrationOptions(
          name: 'root',
          children: {
            'late.slot': const SlotSpec(
              kind: SlotKind.list,
              scope: SlotScope.root,
            ),
          },
        ),
        'shell-2',
      );
      expect(runs, 2);

      // Unsubscribing disposes the live contribution and stops future runs.
      stop();
      expect(disposed, 2);
    });

    test('immediate install when the slot is already declared', () {
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
        },
      );
      var runs = 0;
      registry.inject('a.slot', () {
        runs++;
        return const [];
      });
      expect(runs, 1);
    });

    test(
      'failed effect retires permanently and reports through onInjectionError',
      () {
        final errors = <Object>[];
        registry.onInjectionError = (error, key) => errors.add(error);
        registry.inject('root', () => throw StateError('bad effect'));
        expect(errors, hasLength(1));
      },
    );
  });

  group('change notification', () {
    test('version bumps and listeners fire with changed keys', () {
      final seen = <String>[];
      registry.onChanged(seen.add);
      declareRoot(
        children: {
          'a.slot': const SlotSpec(kind: SlotKind.list, scope: SlotScope.root),
        },
      );
      registry.register(
        const RegistrationOptions(name: 'a.slot', id: 'one'),
        'x',
      );
      expect(seen, containsAll(['root', 'a.slot']));
      expect(registry.version, greaterThan(0));
    });
  });
}
