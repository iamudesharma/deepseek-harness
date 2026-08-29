/// P1 business-plugin integration evidence: pumps the REAL application
/// (`DshApp` → `buildAppHost` → `PluginHost.activateAll`) with a stubbed
/// carrier and proves the five workstreams coexist — DI ordering resolves,
/// every conversation-owned hole receives its contributions, the keyed
/// chat-node registry holds all cross-plugin claims without conflict, and no
/// boot error surfaces.
///
/// This is the co-activation gate tracker `Integrated` transitions cite:
/// registration-order independence (Commands/Reference declare
/// 'inputTriggers'), slot declaration/contribution composition, and the
/// fail-loud renderer registry (duplicate keys would throw here).
library;

import 'package:dsh_flutter/main.dart' show DshApp;
import 'package:dsh_flutter/src/core/bootstrap/app_plugins.dart'
    show activeSlotsProvider;
import 'package:dsh_flutter/src/core/connection/connection_controller.dart'
    show connectionClientProvider;
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart'
    show activatedHub;
import 'package:dsh_flutter/src/plugins/goal/goal_plugin.dart'
    show kGoalCommandInputNodeKey;
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_plugin.dart'
    show kInputMenuOverlayId;
import 'package:dsh_flutter/src/plugins/input_trigger/input_trigger_service.dart'
    show activatedRegistry;
import 'package:dsh_flutter/src/plugins/skill/skill_plugin.dart'
    show kSkillNodeKey;
import 'package:dsh_flutter/src/plugins/subagent/subagent_plugin.dart'
    show kSubagentNodeKey;
import 'package:dsh_flutter/src/plugins/user_questions/user_questions_plugin.dart'
    show kQuestionNodeKey;
import 'package:dsh_flutter/src/plugins/workflow_run/workflow_run_plugin.dart'
    show kWorkflowRunNodeKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plugins/ws_input/host_fixture.dart' show WsInputRecordingClient;

void main() {
  testWidgets('all five workstreams activate together in the real app host '
      '(DI order, hole composition, cross-plugin renderers)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionClientProvider.overrideWithValue(WsInputRecordingClient()),
        ],
        child: const DshApp(),
      ),
    );

    // Drive the async activation to quiescence.
    final element = tester.element(find.byType(DshApp));
    final container = ProviderScope.containerOf(element);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      if (container.read(activeSlotsProvider) != null &&
          activatedHub != null &&
          activatedRegistry != null) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
    }

    // Boot succeeded end-to-end: the shell swapped in and no error screen.
    expect(find.textContaining('failed to activate'), findsNothing);
    final slots = container.read(activeSlotsProvider);
    expect(slots, isNotNull, reason: 'host activation completed');

    // Conversation-owned declarations exist for every consumer workstream.
    const declared = [
      'conversation.composer',
      'conversation.input.overlay',
      'conversation.input.left',
      'conversation.input.right',
      'conversation.input.model',
      'layout.sidebar',
    ];
    for (final key in declared) {
      expect(slots!.isDeclared(key), isTrue, reason: '$key declared');
    }

    // Contributions landed across workstreams (WS-Input seats + overlay +
    // composer chain + sidebar shell).
    List<String> ids(String key) => slots!
        .entries(key)
        .map((e) => e.options.id)
        .whereType<String>()
        .toList();
    expect(
      ids('conversation.input.overlay'),
      containsAll([kInputMenuOverlayId, 'ui-commands-popup']),
      reason: 'WS-Input slash menu + popupSelect share the overlay anchor',
    );
    // The tool-row seats stay declared but unoccupied (React parity —
    // nothing registers into conversation.input.left/right yet).
    expect(
      ids('conversation.input.left'),
      isEmpty,
      reason: 'left seat declared, unoccupied',
    );
    expect(
      ids('conversation.input.right'),
      isEmpty,
      reason: 'right seat declared, unoccupied',
    );
    expect(
      ids('conversation.composer'),
      contains('ui-user-questions-composer'),
      reason: 'WS-Input question composer chain entry',
    );
    expect(
      slots!.entries('conversation.input.model'),
      isNotEmpty,
      reason: 'WS-Surfaces model seat',
    );
    expect(
      slots!.entries('layout.sidebar'),
      hasLength(1),
      reason: 'shell sidebar',
    );

    // Cross-plugin chat-node registry: five plugins claimed distinct keys;
    // a duplicate would have thrown at activation (fail loud).
    final hub = activatedHub!;
    expect(
      hub.controller.renderers.keys,
      containsAll([
        kSubagentNodeKey,
        kQuestionNodeKey,
        kWorkflowRunNodeKey,
        kSkillNodeKey,
        kGoalCommandInputNodeKey,
      ]),
      reason: 'WS-Agent + WS-Tasks + WS-Input node renderers',
    );

    // Service seams resolved through their globals: the conversation hub and
    // the input-trigger registry are alive (consumers resolve them by name).
    expect(hub.controller, isNotNull);
    expect(activatedRegistry, isNotNull);
  });
}
