/// Tool Plugin — Flutter port of the `ui-tool` package boundary
/// (`packages/client/ui-tool/src/client/apply.ts`): the whole-call tree
/// renderer and built-in keyed tool presentations.
///
/// Seam mapping (React → Dart):
/// - `conversation.chat.node` key `'tool-call'` entry → single renderer on
///   [ConversationController.renderers] (ToolCallTree) that owns root/subcall
///   composition and then dispatches the atomic tool name via
///   [ToolPresentationRegistry] (`tool.call.toolview`).
/// - `tool.call.toolview` child hole → [ToolPresentationRegistry] provided as
///   service `'toolPresentation'` (keyed, open key domain, generic fallback).
/// - `conversation.details.tool` → not registered yet: the hole is undeclared
///   in the Dart ledger and the details panel has no session share to read;
///   it lands with the details-panel integration work.
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/slots/slot_registry.dart';
import '../conversation/hub.dart' show ConversationController;
import 'tool_presentation_registry.dart';
import 'ui/keyed_tool_card.dart';
import 'ui/tool_call_tree.dart'
    show
        AskQuestionToolCard,
        BashToolCard,
        DiffToolCard,
        GenericToolCard,
        ReadToolCard,
        SearchToolCard,
        TodoToolCard,
        WebToolCard;

/// The shipped presentations mirroring React's per-tool registrations:
/// bash-sample (bash), read-row (read), file-mutation-row (edit/write),
/// search-row (grep/glob), web-row (web_search/web_fetch),
/// todo-row (todo_write), ask-question-row (ask_user_question).
/// All shipped names are claimed here; an unclaimed name renders the generic
/// fallback by design.
final Map<String, ToolCardBuilder> kBuiltInToolPresentations = {
  'bash': (_, call) => BashToolCard(call: call),
  'read': (_, call) => ReadToolCard(call: call),
  'edit': (_, call) => DiffToolCard(call: call),
  'write': (_, call) => DiffToolCard(call: call),
  'grep': (_, call) => SearchToolCard(call: call),
  'glob': (_, call) => SearchToolCard(call: call),
  'web_search': (_, call) => WebToolCard(call: call),
  'web_fetch': (_, call) => WebToolCard(call: call),
  'todo_write': (_, call) => TodoToolCard(call: call),
  'ask_user_question': (_, call) => AskQuestionToolCard(call: call),
};

/// The `ui-tool` plugin.
class ToolPlugin extends DshPlugin {
  @override
  String get id => 'ui-tool';

  @override
  List<String> get inject => ['slots', 'conversation'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge recorded in the React apply().
    // React also injects 'connection' for the host description used for
    // POSIX `~` summaries; no Dart service carries that yet.
    ctx.require<SlotRegistry>('slots');
    final conversation = ctx.require<ConversationController>('conversation');

    final presentations = ToolPresentationRegistry();
    for (final MapEntry(key: name, value: builder)
        in kBuiltInToolPresentations.entries) {
      presentations.register(name, builder);
    }
    ctx.provide('toolPresentation', presentations);

    // Chat-node registration mirrors React's `conversation.chat.node` key
    // `tool-call` (ui-tool/src/client/apply.ts): one entry whose component
    // is the ToolCallTree (root/subcall) and whose child dispatch is the
    // keyed `tool.call.toolview` table. A second registration for the same
    // key would throw, matching ChatNodeRendererRegistry semantics.
    conversation.renderers.register(
      'tool-call',
      toolCallTreeRenderer(presentations),
    );
  }
}
