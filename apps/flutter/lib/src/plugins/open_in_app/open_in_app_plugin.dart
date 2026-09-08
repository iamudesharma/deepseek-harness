/// The `ui-open-in-app` plugin — Flutter port of
/// `packages/client/ui-open-in-app/src/client/index.ts` `apply()`.
///
/// Registration, in React order: the session-header split button
/// (`conversation.session.header.utilities`, id `open-in-app`, order -10).
/// No RPC, no store here: rows come from `openInAppAppsProvider` (the
/// host's `GET /open-in-app/apps` catalog) and the choice persists via
/// `SharedPreferences` (`dsh.open-in-app.choice`), mirroring React's
/// `OpenInAppController` persisted snapshot store.
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/slots/slot_registry.dart';
import 'ui/open_in_app_header_action.dart';

/// Plugin identity (the React package is `ui-open-in-app`).
const String kOpenInAppPluginId = 'ui-open-in-app';

/// Header utilities entry id (React `id: 'open-in-app'`).
const String kOpenInAppActionId = 'open-in-app';

/// The `ui-open-in-app` plugin.
class OpenInAppPlugin extends DshPlugin {
  /// Creates the plugin.
  const OpenInAppPlugin();

  @override
  String get id => kOpenInAppPluginId;

  @override
  List<String> get inject => ['slots', 'sessions'];

  @override
  Future<void> apply(DshContext ctx) async {
    final stopInject = ctx.slots.inject(
      'conversation.session.header.utilities',
      () {
        return [
          ctx.slots.register(
            const RegistrationOptions(
              name: 'conversation.session.header.utilities',
              id: kOpenInAppActionId,
              order: -10,
            ),
            (context, props) => const OpenInAppHeaderAction(),
          ),
        ];
      },
    );
    ctx.onDispose(stopInject);
  }
}
