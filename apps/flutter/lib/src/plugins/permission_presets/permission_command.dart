/// `/permission` bare-invocation decoration — Flutter port of the
/// `command.decorate({name:'permission',…})` in
/// `packages/client/ui-permission-presets/src/client/index.ts`.
///
/// Adds no menu row: a bare `/permission` pick/enter opens the picker shell
/// over the session's live `permissions` projection (read through
/// [PermissionSnapshotCache], the service-layer mirror `live_sync` feeds),
/// while argued lines keep the existing claim path. Settling runs the same
/// `/permission <preset>` Host line the composer seat submits; the pushed
/// projection frame is the confirmation.
library;

import '../commands/command_service.dart'
    show CommandDecoration, CommandExecutor, SelectConfirmation, SelectOption;
import '../../core/session/session_models.dart';
import 'permission_session_provider.dart';

/// Copy for the full-access risk gate (snapshotted from the
/// `permission.access` `confirm.*` keys by the owning plugin at
/// registration, like React builds it in render context).
class PermissionConfirmCopy {
  /// Creates the copy bundle.
  const PermissionConfirmCopy({
    required this.title,
    required this.description,
    required this.acknowledge,
    required this.cancel,
    required this.enable,
  });

  /// Gate headline.
  final String title;

  /// Gate body.
  final String description;

  /// Checkbox label.
  final String acknowledge;

  /// Back-out label.
  final String cancel;

  /// Settle label.
  final String enable;
}

/// Builds the `/permission` decoration.
///
/// [execute] is the canonical command channel (`CommandUiService.execute`):
/// settling posts `/permission <preset>` and throws the Host error text
/// back into the shell's error strip on refusal.
CommandDecoration buildPermissionDecoration({
  required PermissionSnapshotCache snapshots,
  required CommandExecutor execute,
  required PermissionConfirmCopy confirm,
}) {
  return CommandDecoration(
    name: 'permission',
    // React `available: selectOf(session) !== undefined`.
    available: (sessionId) => snapshots.read(sessionId.value) != null,
    options: (sessionId) async {
      final select = snapshots.read(sessionId.value);
      if (select == null) {
        throw StateError(
          'permission presets are not available on this host',
        );
      }
      return [
        for (final option in select.options)
          // The `custom` value is display-only state, never a switch target
          // (React `optionsOf` filters it too).
          if (option.value != 'custom')
            SelectOption(
              id: option.value,
              label: option.name,
              detail: option.description,
              active: option.value == select.currentValue,
              confirmation: option.value == 'danger-full-access'
                  ? SelectConfirmation(
                      title: confirm.title,
                      description: confirm.description,
                      acknowledgeLabel: confirm.acknowledge,
                      cancelLabel: confirm.cancel,
                      confirmLabel: confirm.enable,
                    )
                  : null,
            ),
      ];
    },
    onSelect: (option, sessionId) async {
      final outcome = await execute(sessionId, '/permission ${option.id}');
      if (!outcome.ok) {
        throw StateError(outcome.text ?? 'permission switch failed');
      }
    },
  );
}
