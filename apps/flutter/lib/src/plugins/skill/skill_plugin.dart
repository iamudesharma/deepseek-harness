/// The `ui-skill` plugin — Flutter port of
/// `packages/client/ui-skill/src/client/index.ts` `apply()`.
///
/// Registrations: the `skill` locale dictionaries, the keyed `skill` tool row
/// on the chat-node seam (the `tool.call.toolview` key='skill' analog — the
/// Dart hub resolves tool nodes by name), and the `'/'` trigger source over
/// the session-keyed [SkillCatalog] (exposed as the `'skills'` service). A
/// preset decides which skill providers an agent reads, so a switched
/// session's cached catalog belongs to the composition it no longer runs:
/// `agent-preset/selected` drops that one key, mirroring the React
/// invalidation. Connection-reset clearing lands with the connection
/// generation row; teardown drops the source and every cached key.
library;

import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/session/session_models.dart';
import '../conversation/hub.dart' show ConversationController;
import '../input_trigger/input_trigger_plugin.dart'
    show kInputTriggersServiceName;
import '../input_trigger/input_trigger_service.dart';
import '../input_trigger/trigger_source.dart';
import 'locales.dart';
import 'skill_catalog.dart';
import 'ui/skill_row.dart';

/// Chat-node key this package claims (tool nodes named `skill`).
const String kSkillNodeKey = 'skill';

/// Trigger-source group name (React `name: 'skill'`).
const String kSkillSourceName = 'skill';

/// Service name the slash-source face is published under.
const String kSkillsServiceName = 'skills';

/// The `ui-skill` plugin.
class SkillPlugin extends DshPlugin {
  /// Creates the plugin.
  const SkillPlugin();

  @override
  String get id => 'ui-skill';

  @override
  List<String> get inject => [
    'connection',
    'sessions',
    'slots',
    'locale',
    'remote',
    'conversation',
    'inputTriggers',
  ];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge.
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    ctx.require<SessionsService>('sessions');
    final LocaleService locale = ctx.require<LocaleService>('locale');
    final RemoteEventBus remote = ctx.require<RemoteEventBus>('remote');
    final ConversationController controller = ctx
        .require<ConversationController>('conversation');
    final inputTriggers = ctx.require<TriggerSourceRegistry>(
      kInputTriggersServiceName,
    );

    final catalog = SkillCatalog(connection: client);
    ctx.provide(kSkillsServiceName, catalog);

    ctx.onDispose(
      locale.register(kSkillNamespace, {'zh': kSkillZh, 'en': kSkillEn}),
    );

    // Dedicated tool row: keyed by the folded node's tool name. The registry
    // exposes registration only — no removal — so this contribution lives
    // until host teardown.
    controller.renderers.register(kSkillNodeKey, renderSkillRow);

    // The '/' trigger source: candidates filter the session's cached catalog;
    // the pick lands the plain `/name ` literal. Teardown removes the source
    // and drops every cached key together with the catalog invalidation below.
    final disposeSource = inputTriggers.registerSource(_SkillSource(catalog));
    ctx.onDispose(disposeSource);

    // A preset switch drops exactly that session's cached catalog; teardown
    // drops the listener with its own unsubscriber plus every cached key.
    final stopInvalidation = remote.$on('agent-preset/selected', (args) {
      if (args.isEmpty || args.first is! String) return;
      catalog.invalidate(SessionId(args.first as String));
    });
    ctx.onDispose(() {
      stopInvalidation();
      catalog.clearAll();
    });
  }
}

/// The `'/'` skill source — Dart port of the `InputTriggerSource` literal in
/// `ui-skill/src/client/index.ts` `apply()`: prefix-filtered candidates over
/// the per-session catalog, the user-only marker riding the description, and
/// the plain-text pick.
class _SkillSource extends InputTriggerSource {
  const _SkillSource(this._catalog);

  final SkillCatalog _catalog;

  @override
  TriggerChar get trigger => '/';

  @override
  String get name => kSkillSourceName;

  @override
  int get order => 2;

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    if (request.cancelled?.call() ?? false) return const [];
    final entries = await _catalog.candidates(
      SessionId(sessionId),
      query: request.query,
    );
    return [
      for (final SkillEntry entry in entries)
        InputTriggerCandidate(
          name: entry.name,
          description: entry.menuDescription,
        ),
    ];
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    return TextOutcome(
      _catalog.pickText(SkillEntry(name: pick.candidate.name)),
    );
  }

  @override
  void warm(String sessionId) {
    // Fire-and-forget scope-birth prewarm; failures stay retryable in the
    // catalog and surface through the next candidates read.
    _catalog
        .candidates(SessionId(sessionId))
        .catchError((_) => const <SkillEntry>[]);
  }

  @override
  List<String>? lexicon(String sessionId) =>
      _catalog.lexicon(SessionId(sessionId));

  @override
  void Function()? subscribeLexicon(
    String sessionId,
    void Function() listener,
  ) => _catalog.subscribeLexicon(SessionId(sessionId), listener);
}
