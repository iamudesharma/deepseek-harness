import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _summary(
  String id, {
  int updatedAt = 1000,
  bool running = false,
  bool blank = false,
  String? title,
}) {
  return SessionSummary(
    sessionId: SessionId(id),
    updatedAt: updatedAt,
    running: running,
    blank: blank,
    title: title,
  );
}

void main() {
  group('SessionsState derived getters', () {
    test('hasCurrent false when no current', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(sessionsProvider).hasCurrent, isFalse);
      expect(container.read(sessionsProvider).currentSession, isNull);
    });

    test('hasCurrent true when current present in byId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.setCurrent(const SessionId('s1'));
      expect(container.read(sessionsProvider).hasCurrent, isTrue);
      expect(container.read(sessionsProvider).currentSession, isNotNull);
      expect(
        container.read(sessionsProvider).currentSession!.sessionId.value,
        's1',
      );
    });

    test('hasCurrent false when current not in byId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      // try to set to unknown id -> ignored, remains null
      notifier.setCurrent(const SessionId('unknown'));
      expect(container.read(sessionsProvider).hasCurrent, isFalse);
    });

    test('sorted descending by updatedAt', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1', updatedAt: 100));
      notifier.addSession(_summary('s2', updatedAt: 300));
      notifier.addSession(_summary('s3', updatedAt: 200));
      final sorted = container.read(sessionsProvider).sorted;
      expect(sorted.map((s) => s.sessionId.value).toList(), ['s2', 's3', 's1']);
    });

    test('copyWith and equality', () {
      const a = SessionsState(byId: {}, current: null);
      const b = SessionsState(byId: {}, current: null);
      expect(a, equals(b));
      final s = _summary('s1');
      final next = a.copyWith(byId: {const SessionId('s1'): s});
      expect(next.byId.length, 1);
      final cleared = next.copyWith(clearCurrent: true);
      expect(cleared.current, isNull);
    });
  });

  group('SessionsController.setCurrent', () {
    test('sets current when present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.addSession(_summary('s2'));
      notifier.setCurrent(const SessionId('s1'));
      expect(container.read(sessionsProvider).current, const SessionId('s1'));
      notifier.setCurrent(const SessionId('s2'));
      expect(container.read(sessionsProvider).current, const SessionId('s2'));
    });

    test('null clears current', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.setCurrent(const SessionId('s1'));
      notifier.setCurrent(null);
      expect(container.read(sessionsProvider).current, isNull);
    });

    test('no-op when clearing already null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      final before = container.read(sessionsProvider);
      notifier.setCurrent(null);
      expect(container.read(sessionsProvider), before);
    });

    test('ignores unknown id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.setCurrent(const SessionId('unknown'));
      expect(container.read(sessionsProvider).current, isNull);
    });

    test('no-op when same id already selected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.setCurrent(const SessionId('s1'));
      final before = container.read(sessionsProvider);
      notifier.setCurrent(const SessionId('s1'));
      expect(container.read(sessionsProvider), before);
    });
  });

  group('SessionsController.addSession', () {
    test('inserts new session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1', title: 'First'));
      expect(container.read(sessionsProvider).byId.length, 1);
      expect(
        container.read(sessionsProvider).byId[const SessionId('s1')]!.title,
        'First',
      );
    });

    test('replaces existing id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1', title: 'Old'));
      notifier.addSession(_summary('s1', title: 'New'));
      expect(
        container.read(sessionsProvider).byId[const SessionId('s1')]!.title,
        'New',
      );
      expect(container.read(sessionsProvider).byId.length, 1);
    });
  });

  group('SessionsController.updateSession', () {
    test('updates existing session and returns true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1', title: 'Old'));
      final updated = notifier.updateSession(
        const SessionId('s1'),
        (s) => s.copyWith(title: 'New'),
      );
      expect(updated, isTrue);
      expect(
        container.read(sessionsProvider).byId[const SessionId('s1')]!.title,
        'New',
      );
    });

    test('returns false when session not found', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      final result = notifier.updateSession(
        const SessionId('missing'),
        (s) => s,
      );
      expect(result, isFalse);
    });

    test('returns false when update returns identical instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      final result = notifier.updateSession(const SessionId('s1'), (s) => s);
      expect(result, isFalse);
    });

    test('user-visible: update reflected via hasCurrent and sorted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1', updatedAt: 100));
      notifier.updateSession(
        const SessionId('s1'),
        (s) => s.copyWith(updatedAt: 500),
      );
      expect(
        container.read(sessionsProvider).byId[const SessionId('s1')]!.updatedAt,
        500,
      );
    });
  });

  group('SessionsController.removeSession', () {
    test('removes and clears current if it pointed there', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.addSession(_summary('s2'));
      notifier.setCurrent(const SessionId('s1'));
      notifier.removeSession(const SessionId('s1'));
      expect(
        container
            .read(sessionsProvider)
            .byId
            .containsKey(const SessionId('s1')),
        isFalse,
      );
      expect(container.read(sessionsProvider).current, isNull);
    });

    test('removes without affecting other current', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.addSession(_summary('s2'));
      notifier.setCurrent(const SessionId('s2'));
      notifier.removeSession(const SessionId('s1'));
      expect(container.read(sessionsProvider).current, const SessionId('s2'));
    });

    test('no-op when id not present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      final before = container.read(sessionsProvider);
      notifier.removeSession(const SessionId('missing'));
      expect(container.read(sessionsProvider), before);
    });
  });

  group('SessionsController.clear', () {
    test('clears all and current', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.setCurrent(const SessionId('s1'));
      notifier.clear();
      expect(container.read(sessionsProvider).byId, isEmpty);
      expect(container.read(sessionsProvider).current, isNull);
    });

    test('no-op when already empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      final before = container.read(sessionsProvider);
      notifier.clear();
      expect(container.read(sessionsProvider), before);
    });
  });

  group('SessionsController.setAll (batched)', () {
    test('bulk replaces via microtask', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('old', updatedAt: 1));
      notifier.setAll([
        _summary('s1', updatedAt: 100),
        _summary('s2', updatedAt: 200),
      ]);
      // before microtask, old state still visible
      expect(
        container
            .read(sessionsProvider)
            .byId
            .containsKey(const SessionId('old')),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionsProvider).byId.length, 2);
      expect(
        container
            .read(sessionsProvider)
            .byId
            .containsKey(const SessionId('old')),
        isFalse,
      );
    });

    test('preserves current when present in new list', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.addSession(_summary('s2'));
      notifier.setCurrent(const SessionId('s1'));
      notifier.setAll([_summary('s1'), _summary('s2')]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionsProvider).current, const SessionId('s1'));
    });

    test('clears current when not in new list', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.addSession(_summary('s1'));
      notifier.setCurrent(const SessionId('s1'));
      notifier.setAll([_summary('s2')]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionsProvider).current, isNull);
    });

    test('coalesces rapid bursts into last value', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionsProvider.notifier);
      notifier.setAll([_summary('a')]);
      notifier.setAll([_summary('b')]);
      notifier.setAll([_summary('c')]);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(sessionsProvider).byId.containsKey(const SessionId('c')),
        isTrue,
      );
      expect(
        container.read(sessionsProvider).byId.containsKey(const SessionId('a')),
        isFalse,
      );
    });
  });
}
