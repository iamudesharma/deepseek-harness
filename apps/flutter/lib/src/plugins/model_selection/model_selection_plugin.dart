/// The `ui-model-selection` plugin — Flutter port of
/// `packages/client/ui-model-selection/src/client/index.ts` `apply()`,
/// sliced to the hub surface the Dart conversation plugin declares.
///
/// Registered here: the `model` locale dictionaries, the per-session
/// directory resolver (`modelDirectories` service), the `/model`
/// command-menu contribution over that shared directory (a switch in the
/// popup is what the composer seat shows next, as in React), and the
/// composer's named `conversation.input.model` seat over that shared
/// directory — a switch in the seat is what any later popup entry shows
/// next, as in React.
library;

import '../commands/command_service.dart' show CommandUiService;
import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'model_command.dart';
import 'model_directory_service.dart';
import 'ui/model_seat.dart';

/// Plugin identity.
const String kModelSelectionPluginId = 'ui-model-selection';

/// The `ui-model-selection` plugin.
class ModelSelectionPlugin extends DshPlugin {
  /// Creates the plugin.
  const ModelSelectionPlugin();

  @override
  String get id => kModelSelectionPluginId;

  @override
  List<String> get inject => ['commandUi', 'connection', 'slots', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final CommandUiService commandUi = ctx.require<CommandUiService>(
      'commandUi',
    );
    final ConnectionClient client = ctx.require<ConnectionClient>('connection');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    final directories = ModelDirectoryService(client);
    ctx.provide(kModelDirectoriesServiceName, directories);
    // Widget bridge: slot occupants resolve the service through this global
    // (bound at activation, cleared on teardown).
    bindActivatedModelDirectories(directories);
    ctx.onDispose(() => bindActivatedModelDirectories(null));

    ctx.onDispose(
      locale.register(kModelNamespace, {'zh': kModelZh, 'en': kModelEn}),
    );

    // `/model` slash-menu row (client contribution, not a Host command —
    // React `command.register({name:'model',…})`). The description snapshots
    // the locale at registration, exactly like React.
    final stopModelCommand = commandUi.register(
      buildModelContribution(
        directories,
        locale.bind(kModelNamespace)('command.description'),
      ),
    );
    ctx.onDispose(stopModelCommand);
    ctx.onDispose(() {
      // Teardown drops every live directory with the plugin.
      directories.clearAll();
    });

    // The composer seat waits for the conversation-owned hole, installs
    // atomically, and leaves with this plugin.
    final stopInject = ctx.slots.inject('conversation.input.model', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(name: 'conversation.input.model'),
          (context, props) => const ModelSeat(),
        ),
      ];
    });
    ctx.onDispose(stopInject);
  }
}
