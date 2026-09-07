/// Conversation hub core: controller boundary, submission policy, transcript
/// sink contract, and the activation bridge for hub UI widgets.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/services/runtime_services.dart';
import '../../core/settings/settings_scope.dart';
import '../../core/session/session_models.dart';
import '../../core/slots/slot_registry.dart';
import 'nodes/chat_node_registry.dart'
    show ChatNodeData, ChatNodeRenderer, ChatNodeRendererRegistry;

export 'nodes/chat_node_registry.dart'
    show ChatNodeData, ChatNodeRenderer, ChatNodeRendererRegistry;

/// Busy-Enter preference stored under settings namespace `ui-conversation`
/// (mirrors submission-settings.ts).
enum BusyEnterBehavior { queue, steer }

/// Namespace owning conversation delivery preferences.
const String kConversationSettingsNamespace = 'ui-conversation';

/// Field carrying the plain-Enter behavior while an agent is busy.
const String kBusyEnterField = 'busyEnter';

/// Default preserves Enter-as-Queue for running conversations.
const BusyEnterBehavior kDefaultBusyEnter = BusyEnterBehavior.queue;

/// Submission policy: decides prompt delivery mode from durability
/// preference + live run state.
class ComposerPolicy {
  ComposerPolicy({this.scope});

  final SettingsScope<Object?>? scope;

  BusyEnterBehavior get preference {
    final value = scope?.snapshot.value;
    if (value is Map) {
      final raw = value[kBusyEnterField];
      if (raw == 'steer') return BusyEnterBehavior.steer;
      if (raw == 'queue') return BusyEnterBehavior.queue;
    }
    return kDefaultBusyEnter;
  }

  String resolveMode({required bool agentRunning}) {
    if (!agentRunning) return 'queue';
    return preference == BusyEnterBehavior.steer ? 'steer' : 'queue';
  }

  Future<void> loadFromScope() async {
    await scope?.refreshFromDescribe();
  }
}

/// Conversation service boundary — the Dart slice of `IConversation`.
class ConversationController {
  ConversationController({
    required ConnectionClient client,
    required SettingsScope<Object?> settingsScope,
    ChatNodeRendererRegistry? renderers,
  }) : _client = client,
       settingsScope = settingsScope,
       policy = ComposerPolicy(scope: settingsScope),
       renderers = renderers ?? ChatNodeRendererRegistry();

  final ConnectionClient _client;
  final SettingsScope<Object?> settingsScope;
  final ComposerPolicy policy;
  final ChatNodeRendererRegistry renderers;

  final Map<String, DockBuilder> _docks = {};

  VoidCallback registerDock(String id, DockBuilder builder) {
    if (_docks.containsKey(id)) {
      throw StateError('dock "$id" already registered');
    }
    _docks[id] = builder;
    return () => _docks.remove(id);
  }

  Iterable<String> get dockIds => _docks.keys;
  DockBuilder dock(String id) => _docks[id]!;

  Future<void> send(
    SessionId sessionId,
    String text, {
    required bool agentRunning,
  }) {
    final mode = policy.resolveMode(agentRunning: agentRunning);
    return _client.sendMessage(sessionId: sessionId, content: text, mode: mode);
  }

  Future<void> cancelTurn(SessionId sessionId) => _client.cancelTurn(sessionId);

  Future<void> updateQueue(
    SessionId sessionId,
    MessageId itemId,
    QueueAction action,
  ) =>
      _client.updateQueue(sessionId: sessionId, itemId: itemId, action: action);
}

/// Composer dock registration builder type.
typedef DockBuilder = WidgetBuilder;

/// Hub view bound at plugin activation; UI widgets read this instead of the
/// bootstrap module.
class ConversationHub {
  ConversationHub({required this.slots, required this.controller});
  final SlotRegistry slots;
  final ConversationController controller;
}

ConversationHub? _activatedHub;

/// Currently bound hub (null before first activation).
ConversationHub? get activatedHub => _activatedHub;

/// Binds (or clears) the activated hub view and notifies listeners.
void bindActivatedHub(ConversationHub? hub) {
  _activatedHub = hub;
  _activatedHubRef.value = hub;
}

final ValueNotifier<ConversationHub?> _activatedHubRef =
    ValueNotifier<ConversationHub?>(null);

ValueListenable<ConversationHub?> get activatedHubListenable =>
    _activatedHubRef;

/// Activated controller bridge for UI widgets.
final hubControllerProvider = Provider<ConversationController?>(
  (ref) => activatedHub?.controller,
);

/// Per-session composer submit hook registered by the composer state so the
/// shortcut seam can trigger the same submission path as the send button.
final composerSubmitHookProvider =
    StateProvider.family<void Function()?, String>((ref, sessionId) => null);
