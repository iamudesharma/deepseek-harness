/// The `ui-user-questions` plugin — Flutter port of
/// `packages/client/ui-user-questions/src/client/index.ts` (frame-fed slice):
/// the pending-question state rides the `question/requested` /
/// `question/resolved` mux frames through live_sync arms, and the keyed
/// `question` chat-node renderer renders the pending set and submits batch
/// answers echoing the requested frame's rpcId.
///
/// The React plugin registers into the composer chain (`conversation.composer`
/// selector-routed); the Dart hub exposes the same surface as the keyed
/// chat-node seam, so the card mounts there until a composer chain exists.
library;

import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart' show LocaleService;
import '../../core/slots/slot_registry.dart';
import '../conversation/hub.dart' show ConversationController;
import 'locales.dart';
import 'ui/approval_card.dart'
    show approvalComposerSelect, bindApprovalClient, renderApprovalNode;
import 'ui/question_composer_entry.dart'
    show questionComposerSelect, QuestionComposerEntry;
import 'ui/question_node_card.dart' show bindQuestionClient, renderQuestionNode;

/// Plugin identity.
const String kUserQuestionsPluginId = 'ui-user-questions';

/// Chat-node key this package claims (React key `question`).
const String kQuestionNodeKey = 'question';

/// The `ui-user-questions` plugin.
class UserQuestionsPlugin extends DshPlugin {
  /// Creates the plugin.
  const UserQuestionsPlugin();

  @override
  String get id => kUserQuestionsPluginId;

  @override
  List<String> get inject => ['slots', 'connection', 'conversation', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final client = ctx.require<ConnectionClient>('connection');
    final controller = ctx.require<ConversationController>('conversation');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    // Dictionaries land with the plugin and leave with it, like every other
    // namespace owner.
    ctx.onDispose(
      locale.register(kQuestionNamespace, {
        'zh': kQuestionZh,
        'en': kQuestionEn,
      }),
    );

    bindQuestionClient(client);
    bindApprovalClient(client);
    // Dedicated tool row keyed by the folded node name; the registry exposes
    // registration only, so the contribution lives until host teardown.
    controller.renderers.register(kQuestionNodeKey, renderQuestionNode);
    ctx.onDispose(() {
      bindQuestionClient(null);
      bindApprovalClient(null);
    });

    // The composer-chain takeover waits for the conversation-owned chain,
    // installs atomically, and leaves with this plugin. `select` narrows the
    // owner's currency to the question carrier (the React selector's job);
    // election happens at chain render time.
    final stopInject = ctx.slots.inject('conversation.composer', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: 'conversation.composer',
            id: 'ui-user-questions-composer',
            select: questionComposerSelect,
          ),
          (context, props) => const QuestionComposerEntry(),
        ),
      ];
    });
    ctx.onDispose(stopInject);

    // The approval takeover mirrors ui-conversation's ApprovalPanel
    // registration: priority 1 so a pending question (default priority 0)
    // wins the chain when both kinds wait — answering the conversation first
    // cannot strand the approval, which re-elects once the question settles.
    final stopApprovalInject = ctx.slots.inject('conversation.composer', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: 'conversation.composer',
            id: 'ui-user-questions-approval-composer',
            priority: 1,
            select: approvalComposerSelect,
          ),
          (context, props) => renderApprovalNode(context),
        ),
      ];
    });
    ctx.onDispose(stopApprovalInject);
  }
}
