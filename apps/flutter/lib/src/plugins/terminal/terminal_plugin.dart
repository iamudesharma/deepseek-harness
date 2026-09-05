/// The `ui-terminal` plugin — console terminal panel over
/// `ctx.remote.terminal`.
///
/// Registrations: the `terminal` locale dictionaries and the session-header
/// console-terminal action (`conversation.session.header.actions`, id
/// `terminal`, order 21 — right after the `job-list` entry). No RPC, no
/// store: rows come from [terminalSessionsProvider], which drives the six
/// `terminal/*` faces on [ConnectionClient].
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'terminal_models.dart';
import 'ui/terminal_action.dart';

/// Plugin identity (the locale namespace is `terminal`).
const String kTerminalPluginId = 'ui-terminal';

/// Header action entry id.
const String kTerminalActionId = 'terminal';

/// The `ui-terminal` plugin.
class TerminalPlugin extends DshPlugin {
  /// Creates the plugin.
  const TerminalPlugin();

  @override
  String get id => kTerminalPluginId;

  @override
  List<String> get inject => ['slots', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.onDispose(
      locale.register(kTerminalNamespace, {'zh': kTerminalZh, 'en': kTerminalEn}),
    );

    final stopInject = ctx.slots.inject(
      'conversation.session.header.actions',
      () {
        return [
          ctx.slots.register(
            const RegistrationOptions(
              name: 'conversation.session.header.actions',
              id: kTerminalActionId,
              order: 21,
            ),
            (context, props) => const TerminalAction(),
          ),
        ];
      },
    );
    ctx.onDispose(stopInject);
  }
}
