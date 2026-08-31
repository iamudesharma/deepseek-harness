/// The `ui-deliverables` plugin — Flutter port of
/// `packages/client/ui-deliverables/src/client/index.ts` `apply()`.
///
/// Registration: the `deliverables` locale dictionaries and the
/// `'chatFileMentions'` service (the inline-code mention resolver over one
/// turn's produced paths). React also registers the turn-tail chain entry
/// (`conversation.chat.turnTail`, selector-matched) and the produced-file
/// derivation fold; both land when the Dart conversation hub grows the
/// turn-tail seam and the deliverables fold family — composing this plugin
/// out removes the vocabulary entirely, and the owning view renders an empty
/// chain at zero cost, exactly like React.
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import 'deliverables_mentions.dart';
import 'locales.dart';

/// Plugin identity.
const String kDeliverablesPluginId = 'ui-deliverables';

/// Service name the mention face is published under.
const String kChatFileMentionsServiceName = 'chatFileMentions';

/// The chat-prose mention face (`ChatFileMentions` analog): resolves an
/// inline-code token against one turn's produced paths.
abstract interface class ChatFileMentions {
  /// Resolution for [token] over [paths], or null when nothing matches —
  /// exact path first, then a unique basename; shared basenames stay inert.
  ResolvedMention? resolve({
    required List<String> paths,
    required String token,
    required void Function(String path) openFile,
  });
}

class _DeliverablesMentions implements ChatFileMentions {
  const _DeliverablesMentions();

  @override
  ResolvedMention? resolve({
    required List<String> paths,
    required String token,
    required void Function(String path) openFile,
  }) {
    return resolveFileMention(paths, token, openFile);
  }
}

/// The `ui-deliverables` plugin.
class DeliverablesPlugin extends DshPlugin {
  /// Creates the plugin.
  const DeliverablesPlugin();

  @override
  String get id => kDeliverablesPluginId;

  @override
  List<String> get inject => ['slots', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge. React also declares 'connection'
    // for the loopback/Host-description facts gating `Show in folder`; no
    // Dart service carries those yet, so the row takes canOpenPath from its
    // mount site until they land.
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.onDispose(
      locale.register(kDeliverablesNamespace, {
        'zh': kDeliverablesZh,
        'en': kDeliverablesEn,
      }),
    );

    // Same claim test the turn-tail chain entry runs: no produced files, no
    // vocabulary — the two surfaces agree by construction once the chain
    // lands, because it feeds this same resolver.
    ctx.provide(kChatFileMentionsServiceName, const _DeliverablesMentions());
  }
}
