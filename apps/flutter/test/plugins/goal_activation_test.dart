import 'package:dsh_flutter/src/plugins/goal/goal_activation.dart';
import 'package:dsh_flutter/src/plugins/goal/goal_control.dart' show GoalRef;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted deps for the activation source (no Riverpod, no transport).
class _Script {
  GoalRef? ref;
  GoalView? goal;
  int getGoalCalls = 0;
  void Function(GoalView?)? activationListener;
  VoidCallback? resetListener;
  bool activationUnsubscribed = false;
  bool resetUnsubscribed = false;

  GoalActivationDeps get deps => GoalActivationDeps(
    projectionRef: () => ref,
    getGoal: () async {
      getGoalCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return goal;
    },
    subscribeActivation: (listener) {
      activationListener = listener;
      return () => activationUnsubscribed = true;
    },
    subscribeReset: (listener) {
      resetListener = listener;
      return () => resetUnsubscribed = true;
    },
  );

  void emitActivation(GoalView? value) => activationListener?.call(value);
  void emitReset() => resetListener?.call();
}

GoalRef _ref([String id = 'g1', int revision = 1]) =>
    GoalRef(id: id, revision: revision);

GoalView _view({
  String id = 'g1',
  int revision = 1,
  GoalActivation activation = GoalActivation.armed,
}) => GoalView(id: id, revision: revision, activation: activation);

void main() {
  group('GoalActivationSource epoch ordering', () {
    test('projection ref triggers a read that publishes the view', () async {
      final script = _Script()
        ..ref = _ref()
        ..goal = _view(activation: GoalActivation.armed);
      final source = GoalActivationSource(script.deps);
      expect(script.getGoalCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.snapshot.id, 'g1');
      expect(source.snapshot.activation, GoalActivation.armed);
      source.dispose();
      expect(script.activationUnsubscribed, isTrue);
      expect(script.resetUnsubscribed, isTrue);
    });

    test('stale read loses to a newer activation edge', () async {
      final script = _Script()
        ..ref = _ref()
        ..goal = _view(revision: 1);
      final source = GoalActivationSource(script.deps);
      // Edge lands while the read is in flight: the read is stale.
      script.emitActivation(
        _view(revision: 2, activation: GoalActivation.disarmed),
      );
      expect(source.snapshot.revision, 2);
      expect(source.snapshot.activation, GoalActivation.disarmed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // The stale read (revision 1) must not overwrite the edge.
      expect(source.snapshot.revision, 2);
      source.dispose();
    });

    test('identical snapshots publish nothing', () async {
      final script = _Script()
        ..ref = _ref()
        ..goal = _view();
      final source = GoalActivationSource(script.deps);
      var notifications = 0;
      source.addListener(() => notifications++);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final first = notifications;
      expect(first, greaterThan(0));
      // Same edge again: no new notification.
      script.emitActivation(_view());
      expect(notifications, first);
      source.dispose();
    });

    test('clear edge empties the snapshot', () async {
      final script = _Script()
        ..ref = _ref()
        ..goal = _view();
      final source = GoalActivationSource(script.deps);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.snapshot.id, 'g1');
      script.emitActivation(null);
      expect(source.snapshot, GoalActivationSnapshot.empty);
      source.dispose();
    });

    test('reset refreshes with a fresh read', () async {
      final script = _Script()
        ..ref = _ref()
        ..goal = _view(revision: 1);
      final source = GoalActivationSource(script.deps);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final calls = script.getGoalCalls;
      script.emitReset();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(script.getGoalCalls, greaterThan(calls));
      source.dispose();
    });

    test('no projection ref publishes nothing and reads nothing', () async {
      final script = _Script()..goal = _view();
      final source = GoalActivationSource(script.deps);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(script.getGoalCalls, 0);
      expect(source.snapshot, GoalActivationSnapshot.empty);
      source.dispose();
    });
  });

  group('GoalView parsing', () {
    test('malformed values read as no live goal', () {
      expect(GoalView.tryFromJson(null), isNull);
      expect(GoalView.tryFromJson({'id': 'g'}), isNull);
      expect(
        GoalView.tryFromJson({
          'id': 'g',
          'revision': 1,
          'activation': 'nope',
        }),
        isNull,
      );
      expect(
        GoalView.tryFromJson({
          'id': 'g',
          'revision': 1,
          'activation': 'disarmed',
        })?.activation,
        GoalActivation.disarmed,
      );
    });
  });
}
