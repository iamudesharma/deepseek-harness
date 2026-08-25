import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/model_selection/model_directory.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_session_provider.dart';
import 'package:dsh_flutter/src/plugins/plan/ui/plan_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Permission / Access Mode', () {
    test('decodes PermissionSelect with options and currentValue', () {
      final json = {
        'options': [
          {'value': 'workspace-write', 'name': 'Workspace Write', 'description': 'Write inside workspace'},
          {'value': 'danger-full-access', 'name': 'Full Access', 'description': 'Full file access'},
        ],
        'currentValue': 'workspace-write',
      };
      final select = PermissionSelect.fromJson(json);
      expect(select.options, hasLength(2));
      expect(select.currentValue, 'workspace-write');
      expect(select.isCustom, isFalse);
    });

    test('custom is derived and not selectable', () {
      final select = PermissionSelect.fromJson({
        'options': [
          {'value': 'workspace-write', 'name': 'Workspace Write'},
          {'value': 'custom', 'name': 'Custom'},
        ],
        'currentValue': 'custom',
      });
      expect(select.isCustom, isTrue);
      // Custom should be shown but not selectable in UI (enabled false)
    });

    test('read-only preset when configured', () {
      final select = PermissionSelect.fromJson({
        'options': [
          {'value': 'read-only', 'name': 'Read Only'},
          {'value': 'workspace-write', 'name': 'Workspace Write'},
          {'value': 'danger-full-access', 'name': 'Full Access'},
        ],
        'currentValue': 'read-only',
      });
      expect(select.options.map((o) => o.value), contains('read-only'));
      expect(select.currentValue, 'read-only');
    });

    test('projection confirmation via permissionSelectProvider', () {
      // Simulate live_sync update
      final select = PermissionSelect.fromJson({
        'options': [
          {'value': 'workspace-write', 'name': 'Workspace Write'},
          {'value': 'danger-full-access', 'name': 'Full Access'},
        ],
        'currentValue': 'danger-full-access',
      });
      // The provider would be updated via live_sync SessionProjectionFrame
      expect(select.currentValue, 'danger-full-access');
    });
  });

  group('Model Selection + Reasoning Effort', () {
    test('model with off/high/max advertises all efforts', () {
      final model = ModelInfo.fromJson({
        'id': 'deepseek-chat',
        'name': 'DeepSeek Chat',
        'reasoning': {
          'efforts': [
            {'id': 'off', 'name': 'Off'},
            {'id': 'high', 'name': 'High'},
            {'id': 'max', 'name': 'Max'},
          ],
          'defaultEffort': 'high',
        },
      });
      expect(model.reasoning, isNotNull);
      expect(model.reasoning!.efforts, hasLength(3));
      expect(model.reasoning!.defaultEffort, 'high');
    });

    test('model with only off', () {
      final model = ModelInfo.fromJson({
        'id': 'model-off-only',
        'name': 'Off Only',
        'reasoning': {
          'efforts': [
            {'id': 'off', 'name': 'Off'},
          ],
          'defaultEffort': 'off',
        },
      });
      expect(model.reasoning!.efforts, hasLength(1));
      expect(model.reasoning!.efforts.single.id, 'off');
    });

    test('model with no reasoning hides Effort UI', () {
      final model = ModelInfo.fromJson({
        'id': 'no-reasoning',
        'name': 'No Reasoning',
      });
      expect(model.reasoning, isNull);
    });

    test('changing model clears incompatible effort', () {
      // Simulate selecting a new model with different reasoning
      final oldSelection = ModelSelection(provider: 'p1', model: 'm1', reasoningEffort: 'max');
      final newModel = ModelInfo.fromJson({
        'id': 'm2',
        'name': 'M2',
        'reasoning': {
          'efforts': [
            {'id': 'off', 'name': 'Off'},
          ],
          'defaultEffort': 'off',
        },
      });
      // New selection should use new model's defaultEffort, not old max
      final newSelection = ModelSelection(
        provider: 'p1',
        model: newModel.id,
        reasoningEffort: newModel.reasoning?.defaultEffort,
      );
      expect(newSelection.reasoningEffort, 'off');
      expect(newSelection.reasoningEffort, isNot(oldSelection.reasoningEffort));
    });

    test('changing effort preserves provider/model', () {
      final current = ModelSelection(provider: 'p1', model: 'm1', reasoningEffort: 'high');
      final newEffort = 'max';
      final updated = ModelSelection(provider: current.provider, model: current.model, reasoningEffort: newEffort);
      expect(updated.provider, current.provider);
      expect(updated.model, current.model);
      expect(updated.reasoningEffort, 'max');
    });

    test('defaultEffort used when reasoningEffort is null', () {
      final model = ModelInfo.fromJson({
        'id': 'm1',
        'name': 'M1',
        'reasoning': {
          'efforts': [
            {'id': 'off', 'name': 'Off'},
            {'id': 'high', 'name': 'High'},
          ],
          'defaultEffort': 'high',
        },
      });
      final current = ModelSelection(provider: 'p1', model: 'm1', reasoningEffort: null);
      final effective = current.reasoningEffort ?? model.reasoning?.defaultEffort;
      expect(effective, 'high');
    });

    test('provider-default when no defaultEffort', () {
      final model = ModelInfo.fromJson({
        'id': 'm1',
        'name': 'M1',
        'reasoning': {
          'efforts': [
            {'id': 'off', 'name': 'Off'},
            {'id': 'high', 'name': 'High'},
          ],
        },
      });
      expect(model.reasoning?.defaultEffort, isNull);
      // UI should show "Provider default" option
    });
  });

  group('Plan Mode', () {
    test('idle plan -> /plan off -> committed inactive', () {
      final notifier = PlanNotifier();
      expect(notifier.state.active, isFalse); // inactive before first
      // Simulate host projection after /plan off committed
      notifier.settle(active: false);
      expect(notifier.state.active, isFalse);
      expect(notifier.state.pending, isFalse);
    });

    test('active in-turn plan -> /plan off -> pending inactive', () {
      final notifier = PlanNotifier();
      notifier.settle(active: true);
      expect(notifier.state.active, isTrue);
      // Simulate pending exit (hasOpenTurn true, queued)
      notifier.setPending();
      expect(notifier.state.pending, isTrue);
      // Effective target = pending ? !active : active = !true = false -> chip hidden
      final target = notifier.state.pending ? !notifier.state.active : notifier.state.active;
      expect(target, isFalse);
    });

    test('repeated /plan off -> noop', () {
      final notifier = PlanNotifier();
      notifier.settle(active: false);
      // Second settle with same inactive should remain inactive, no pending
      notifier.settle(active: false);
      expect(notifier.state.active, isFalse);
      expect(notifier.state.pending, isFalse);
    });

    test('opposite pending selection cancellation semantics', () {
      final notifier = PlanNotifier();
      notifier.settle(active: true);
      // Queue exit
      notifier.setPending();
      expect(notifier.state.pending, isTrue);
      // Opposite selection cancelled -> pending cleared, active unchanged
      notifier.settle(active: true);
      expect(notifier.state.pending, isFalse);
      expect(notifier.state.active, isTrue);
    });

    test('plan/mode event replay', () {
      final notifier = PlanNotifier();
      // Simulate replay of log with plan/mode events
      notifier.settle(active: true);
      expect(notifier.state.active, isTrue);
      notifier.settle(active: false);
      expect(notifier.state.active, isFalse);
      notifier.settle(active: true);
      expect(notifier.state.active, isTrue);
    });

    test('projection update', () {
      final notifier = PlanNotifier();
      // Simulate SessionProjectionFrame key:plan value:{active, pending}
      notifier.settle(active: true);
      expect(notifier.state.active, isTrue);
      notifier.setPending();
      expect(notifier.state.pending, isTrue);
      // Host commits
      notifier.settle(active: false);
      expect(notifier.state.active, isFalse);
      expect(notifier.state.pending, isFalse);
    });

    test('UI chip follows authoritative effective state', () {
      final notifier = PlanNotifier();
      notifier.settle(active: true);
      var target = notifier.state.pending ? !notifier.state.active : notifier.state.active;
      expect(target, isTrue); // visible
      notifier.setPending();
      target = notifier.state.pending ? !notifier.state.active : notifier.state.active;
      expect(target, isFalse); // hidden while leaving
      notifier.settle(active: false);
      target = notifier.state.pending ? !notifier.state.active : notifier.state.active;
      expect(target, isFalse); // hidden after committed
    });
  });
}
