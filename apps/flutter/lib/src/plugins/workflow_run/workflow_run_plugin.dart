/// The `ui-workflow-run` plugin — Flutter port of
/// `packages/client/ui-workflow-run/src/client/index.ts` `apply()`.
///
/// Registrations, in React order: the `workflowRun` locale dictionaries and
/// the keyed `workflow-run` chat-node renderer. The Definition half
/// (folding the `tool-workflow/*` event family) lands with the
/// conversation-fold workstream — until then the renderer consumes the
/// seam's line contract ([decodeWorkflowRun]) and renders nothing for nodes
/// that do not carry a run payload.
///
/// The navigation face is constructor-injected (`openSession`, React's
/// `ctx.sessions.open`) because the Dart `'sessions'` service slice does not
/// yet carry selection; members render inert until boot wiring passes it.
library;

import 'package:flutter/widgets.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../conversation/hub.dart' show ConversationController;
import 'locales.dart';
import 'ui/workflow_run_panel.dart';
import 'workflow_run_models.dart';

/// Plugin identity.
const String kWorkflowRunPluginId = 'ui-workflow-run';

/// Chat-node key this package claims (durable workflow-run nodes).
const String kWorkflowRunNodeKey = 'workflow-run';

/// The `ui-workflow-run` plugin.
class WorkflowRunPlugin extends DshPlugin {
  /// Creates the plugin over the child-session opener.
  const WorkflowRunPlugin({this.openSession});

  /// Opens a member's child session; null keeps rows inert (React's
  /// `ctx.sessions.open` inject face).
  final void Function(String childId)? openSession;

  @override
  String get id => kWorkflowRunPluginId;

  @override
  List<String> get inject => ['slots', 'locale', 'conversation'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge. React also declares
    // 'conversationEvents' (the Definition registration) and 'sessions'
    // (selection); both faces land with their runtime rows here.
    final LocaleService locale = ctx.require<LocaleService>('locale');
    final ConversationController controller = ctx
        .require<ConversationController>('conversation');

    ctx.onDispose(
      locale.register(kWorkflowRunNamespace, {
        'zh': kWorkflowRunZh,
        'en': kWorkflowRunEn,
      }),
    );

    // Keyed chat-node renderer. The registry exposes registration only — no
    // removal — so this contribution lives until host teardown.
    controller.renderers.register(kWorkflowRunNodeKey, (context, data) {
      final run = decodeWorkflowRun(data);
      if (run == null) return const SizedBox.shrink();
      return WorkflowRunPanel(data: run, openSession: openSession);
    });
  }
}
