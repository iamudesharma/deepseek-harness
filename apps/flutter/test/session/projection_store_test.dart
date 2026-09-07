import 'package:dsh_flutter/src/core/session/live_sync.dart'
    show publishableProjectionKeys;
import 'package:dsh_flutter/src/core/session/projection_store.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

SessionProjectionsBlock block(int asOfSeq, Map<String, dynamic> values) =>
    SessionProjectionsBlock(asOfSeq: asOfSeq, values: values);

void main() {
  group('SessionProjectionStore — higher seq wins', () {
    test('first value for a key is accepted regardless of seq', () {
      final store = SessionProjectionStore();
      expect(store.offer('title', 'A', 5), isTrue);
      expect(store.valueOf('title'), 'A');
      expect(store.rowOf('title')!.seq, 5);
    });

    test('higher seq replaces; lower and equal seq lose', () {
      final store = SessionProjectionStore()..offer('title', 'A', 5);
      expect(store.offer('title', 'B', 6), isTrue);
      expect(store.valueOf('title'), 'B');
      // A replayed frame cannot regress a value.
      expect(store.offer('title', 'stale', 6), isFalse);
      expect(store.offer('title', 'older', 4), isFalse);
      expect(store.valueOf('title'), 'B');
    });

    test(
      'keys are independent; unknown key reads null (capability absent)',
      () {
        final store = SessionProjectionStore()
          ..offer('title', 'A', 5)
          ..offer('permissions', {'options': []}, 3);
        expect(store.valueOf('plan'), isNull);
        expect(store.offer('plan', {'active': false}, 2), isTrue);
        expect(store.valueOf('title'), 'A');
        expect(store.valueOf('permissions'), {'options': []});
      },
    );
  });

  group('history tail baseline seeding', () {
    test('seeds every key at the block cut', () {
      final store = SessionProjectionStore();
      final accepted = store.seed(
        block(9, {
          'title': 'History title',
          'permissions': {'currentValue': 'default'},
        }),
      );
      expect(accepted, containsAll(<String>['title', 'permissions']));
      expect(store.valueOf('title'), 'History title');
      expect(store.rowOf('title')!.seq, 9);
    });

    test('a stale baseline cannot overwrite a newer push frame', () {
      final store = SessionProjectionStore();
      // Push frame lands first (live races the history fetch).
      store.offer('title', 'Pushed live', 12);
      // History tail page was cut earlier.
      final withheld = store.seed(block(9, {'title': 'Stale tail'}));
      expect(withheld, isNot(contains('title')));
      expect(store.valueOf('title'), 'Pushed live');
    });

    test('publishableProjectionKeys withholds regressed keys from folding', () {
      final store = SessionProjectionStore()
        ..offer('permissions', {'currentValue': 'pushed'}, 20);
      final publishable = publishableProjectionKeys(
        store,
        block(15, {
          'permissions': {'currentValue': 'tail'},
        }),
      );
      // The permissions key must not reach its reactive surface…
      expect(publishable.contains('permissions'), isFalse);
      // …and an absent key stays unpublishable too (no block → nothing).
      expect(publishableProjectionKeys(store, null), isEmpty);
    });

    test(
      're-seeding the same cut refreshes values without regression risk',
      () {
        final store = SessionProjectionStore();
        store.seed(block(9, {'title': 'T1'}));
        // Same-cut reseed after reconnect resync: equal seq loses, so a second
        // identical fold is idempotent rather than double-publishing.
        final again = store.seed(block(9, {'title': 'T1'}));
        expect(again, isEmpty);
        expect(store.valueOf('title'), 'T1');
      },
    );
  });
}
