/// The `ui-subagent` plugin — Flutter port of
/// `packages/client/ui-subagent/src/client/index.ts` `apply()`.
///
/// Registrations, in React order: the `subagent` locale dictionaries, the
/// session-header catalog action (`conversation.session.header.actions`,
/// id `subagent-catalog`, order 10), and the keyed child-transcript chat-node
/// renderer (hub map §6). The read-only composer takeover ships as widget +
/// selector (`ui/subagent_read_only_composer.dart`) and registers once the
/// conversation hub declares a composer chain seat — the Dart hub has no
/// `conversation.composer` hole yet, and a bare register there would fail
/// loud by design.
///
/// The navigation face is constructor-injected ([link]) because the Dart
/// `'sessions'` service slice does not yet carry selection; boot wiring lands
/// with integration (tracker: subagent.runtime-link).
library;

import 'package:flutter/widgets.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import '../conversation/hub.dart' show ConversationController;
import 'locales.dart';
import 'subagent_link.dart';
import 'ui/subagent_catalog_action.dart';
import 'ui/subagent_node_card.dart';

/// Plugin identity.
const String kSubagentPluginId = 'ui-subagent';

/// Chat-node key this package claims (delegation-tool nodes fold here).
const String kSubagentNodeKey = 'subagent';

/// Header list entry id (React `id: 'subagent-catalog'`).
const String kSubagentCatalogId = 'subagent-catalog';

/// The `ui-subagent` plugin.
class SubagentPlugin extends DshPlugin {
  /// Creates the plugin over [link]'s navigation ports.
  const SubagentPlugin({required this.link});

  /// Open/refresh/catalog-state face provided as the `'subagents'` service.
  final SubagentLink link;

  @override
  String get id => kSubagentPluginId;

  @override
  List<String> get inject => ['slots', 'sessions', 'locale', 'conversation'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge.
    final LocaleService locale = ctx.require<LocaleService>('locale');
    ctx.require<SessionsService>('sessions');
    final ConversationController controller = ctx
        .require<ConversationController>('conversation');

    ctx.provide('subagents', link);

    // Dictionaries leave with the plugin (the ctx.effect analog).
    ctx.onDispose(
      locale.register(kSubagentNamespace, {
        'zh': kSubagentZh,
        'en': kSubagentEn,
      }),
    );

    // Child-transcript renderer on the keyed chat-node seam. The registry
    // exposes registration only — no removal — so this contribution lives
    // until host teardown, unlike the slot and dock contributions below.
    controller.renderers.register(kSubagentNodeKey, renderSubagentNode);

    // Catalog action waits for the conversation-owned header hole, installs
    // atomically, and leaves with this plugin.
    final stopInject = ctx.slots.inject(
      'conversation.session.header.actions',
      () {
        return [
          ctx.slots.register(
            const RegistrationOptions(
              name: 'conversation.session.header.actions',
              id: kSubagentCatalogId,
              order: 10,
            ),
            (BuildContext context, dynamic props) =>
                SubagentCatalogAction(link: link),
          ),
        ];
      },
    );
    ctx.onDispose(stopInject);
  }
}
