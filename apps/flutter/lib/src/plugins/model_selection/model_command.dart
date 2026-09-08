/// `/model` slash-menu contribution — Flutter port of the `popupSelect`
/// contribution in `packages/client/ui-model-selection/src/client/index.ts`
/// (`command.register({name:'model', …})`).
///
/// The row is client-owned: `/model` is not a Host command (a same-named
/// Host row would collide and fail loud at candidate synthesis, exactly like
/// React). Options come from the session's shared [ModelDirectory] — the
/// same store the composer seat renders — so a switch in either surface is
/// what the other shows. Like React, the description is snapshotted from the
/// `model` locale at registration time.
library;

import '../commands/command_service.dart' show CommandContribution, SelectOption;
import '../../core/session/session_models.dart';
import '../../features/model_selection/model_directory.dart';
import 'model_directory_service.dart';

/// Builds the `/model` contribution over [directories].
///
/// [modelDescription] is `t('command.description')` read once by the owning
/// plugin at registration (React snapshots it the same way; a locale switch
/// needs re-registration to refresh the row).
CommandContribution buildModelContribution(
  ModelDirectoryService directories,
  String modelDescription,
) {
  return CommandContribution(
    name: 'model',
    description: modelDescription,
    // Availability follows the composer seat (no gate there either):
    // every session with a directory can open the picker.
    available: (_) => true,
    options: (sessionId) async {
      final directory = directories.directoryFor(sessionId);
      await directory.load();
      final state = directory.state;
      final current = state.current;
      final rows = <SelectOption>[
        for (final group in state.groups)
          for (final model in group.models)
            SelectOption(
              id: '${group.id}/${model.id}',
              label: model.name,
              detail: group.name,
              active:
                  current?.provider == group.id &&
                  current?.model == model.id,
            ),
        for (var i = 0; i < state.failures.length; i++)
          if (state.failures[i] is Map)
            SelectOption(
              id: 'failure/$i',
              label:
                  '${(state.failures[i] as Map)['name'] ?? (state.failures[i] as Map)['id']}',
              detail: 'failed to load',
            ),
      ];
      if (rows.isEmpty && state.status == 'error') {
        throw StateError(state.error ?? 'Model catalog failed to load.');
      }
      return rows;
    },
    onSelect: (option, sessionId) async {
      if (option.id.startsWith('failure/')) {
        throw StateError(
          "This provider's catalog failed to load — pick an available model.",
        );
      }
      final slash = option.id.indexOf('/');
      if (slash <= 0 || slash == option.id.length - 1) {
        throw StateError('Unknown model option "${option.id}".');
      }
      final directory = directories.directoryFor(sessionId);
      // Mirror the composer seat: a fresh pick resets to the model's
      // advertised default effort.
      ModelInfo? target;
      for (final group in directory.state.groups) {
        if (group.id != option.id.substring(0, slash)) continue;
        for (final model in group.models) {
          if (model.id == option.id.substring(slash + 1)) {
            target = model;
            break;
          }
        }
        if (target != null) break;
      }
      await directory.select(
        ModelSelection(
          provider: option.id.substring(0, slash),
          model: option.id.substring(slash + 1),
          reasoningEffort: target?.reasoning?.defaultEffort,
        ),
      );
    },
  );
}
