import 'dart:async';

import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsFace implements SettingsFace {
  Map<String, Object?> document = {
    'namespaces': {
      'ui-theme': {
        'value': {'preference': 'system'},
        'base': {'preference': 'system'},
        'user': {},
        'revision': 3,
        'writable': true,
      },
      'read-only-ns': {'value': {}, 'writable': false},
    },
  };

  final List<
    ({String ns, List<Map<String, Object?>> ops, int? expectedRevision})
  >
  mutations = [];

  /// When set, the next mutate completes with this instead of a normal answer.
  Completer<Map<String, Object?>>? gate;

  @override
  Future<Map<String, Object?>> describe() async => document;

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async {
    mutations.add((ns: ns, ops: ops, expectedRevision: expectedRevision));
    if (gate != null) return gate!.future;
    final currentRevision =
        (((document['namespaces'] as Map)[ns] as Map)['revision'] as int?) ?? 0;
    if (expectedRevision != null && expectedRevision != currentRevision) {
      // Simulate the host rejecting a stale fence.
      throw StateError('settings-conflict');
    }
    for (final op in ops) {
      if (op['op'] == 'set') {
        final section = (document['namespaces'] as Map)[ns] as Map;
        (section['value'] as Map)[(op['path'] as List).single] = op['value'];
        section['revision'] = ((section['revision'] as int?) ?? 0) + 1;
      }
    }
    final section = (document['namespaces'] as Map)[ns];
    return {
      'namespace': {
        'value': section['value'],
        'revision': section['revision'],
        'writable': true,
      },
    };
  }
}

void main() {
  test(
    'refresh derives the namespace view with revision and writability',
    () async {
      final face = _FakeSettingsFace();
      final scope = SettingsScope<Object?>(face: face, namespace: 'ui-theme');
      expect(scope.snapshot.status, SettingsScopeStatus.loading);

      await scope.refreshFromDescribe();
      expect(scope.snapshot.status, SettingsScopeStatus.ready);
      expect(scope.snapshot.revision, 3);
      expect(scope.snapshot.writable, isTrue);
      expect((scope.snapshot.value as Map)['preference'], 'system');
    },
  );

  test('unknown namespace reports unavailable', () async {
    final scope = SettingsScope<Object?>(
      face: _FakeSettingsFace(),
      namespace: 'nope',
    );
    await scope.refreshFromDescribe();
    expect(scope.snapshot.status, SettingsScopeStatus.unavailable);
    expect(scope.snapshot.writable, isFalse);
  });

  test(
    'write fences with latest known revision and folds settlement',
    () async {
      final face = _FakeSettingsFace();
      final scope = SettingsScope<Object?>(face: face, namespace: 'ui-theme');
      await scope.refreshFromDescribe();

      await scope.set('preference', 'dark');

      expect(face.mutations.single.expectedRevision, 3);
      expect(face.mutations.single.ops.single, {
        'op': 'set',
        'path': ['preference'],
        'value': 'dark',
      });
      expect((scope.snapshot.value as Map)['preference'], 'dark');
      expect(scope.snapshot.revision, 4);
    },
  );

  test('serialized writes each fence at their own turn', () async {
    final face = _FakeSettingsFace();
    final scope = SettingsScope<Object?>(face: face, namespace: 'ui-theme');
    await scope.refreshFromDescribe();

    // Fire concurrently; ordering contract serializes fences 3 then 4.
    final a = scope.set('preference', 'light');
    final b = scope.set('other', 'x');
    await Future.wait([a, b]);

    expect(face.mutations[0].expectedRevision, 3);
    expect(face.mutations[1].expectedRevision, 4);
  });

  test(
    'conflicted write recovers via re-describe instead of throwing',
    () async {
      final face = _FakeSettingsFace();
      final scope = SettingsScope<Object?>(face: face, namespace: 'ui-theme');
      await scope.refreshFromDescribe();

      // Force a stale fence: pretend another writer moved the doc to rev 9.
      (face.document['namespaces'] as Map)['ui-theme']['revision'] = 9;
      await scope.set('preference', 'dark');

      // The stale fence (3) hit the conflict path; recovery re-described.
      expect(face.mutations.single.expectedRevision, 3);
      expect(scope.snapshot.revision, 9);
    },
  );

  test('subscribe fires on snapshot replacements only', () async {
    final face = _FakeSettingsFace();
    final scope = SettingsScope<Object?>(face: face, namespace: 'ui-theme');
    var calls = 0;
    scope.subscribe((_) => calls++);

    await scope.refreshFromDescribe();
    final afterLoad = calls;
    await scope.refreshFromDescribe(); // same content, fresh snapshot object
    expect(calls, afterLoad + 1);
  });
}
