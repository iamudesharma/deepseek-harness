/// `/permission` decoration tests — bare invocations open the picker shell
/// over the live projection mirror; argued lines keep the claim path.
library;

import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/commands/command_directory.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:dsh_flutter/src/plugins/input_trigger/trigger_source.dart'
    show ClaimOutcome, HandledOutcome;
import 'package:dsh_flutter/src/plugins/permission_presets/permission_command.dart';
import 'package:dsh_flutter/src/plugins/permission_presets/permission_session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _confirm = PermissionConfirmCopy(
  title: 'Enable Full access?',
  description: 'Risky.',
  acknowledge: 'I understand',
  cancel: 'Cancel',
  enable: 'Enable',
);

PermissionSelect _select() => const PermissionSelect(
  options: [
    PresetOption(value: 'read-only', name: 'Read only'),
    PresetOption(
      value: 'danger-full-access',
      name: 'Full access',
      description: 'Everything',
    ),
    PresetOption(value: 'custom', name: 'Custom'),
  ],
  currentValue: 'read-only',
);

Future<CommandExecutionOutcome> _ok(SessionId _, String __) async =>
    CommandExecutionOutcome.success('preset danger-full-access');

CommandUiService _service({
  required PermissionSnapshotCache snapshots,
  CommandExecutor? execute,
}) {
  final directory = CommandDirectory(
    fetchCommands: (_) async => const [
      CommandDescriptor(
        name: 'permission',
        description: 'Switch the permission preset',
        hint: '<preset>',
      ),
    ],
  );
  final service = CommandUiService(
    directory: directory,
    execute: execute ?? _ok,
  );
  service.decorate(
    buildPermissionDecoration(
      snapshots: snapshots,
      execute: service.execute,
      confirm: _confirm,
    ),
  );
  return service;
}

void main() {
  test('available follows the projection mirror', () {
    final snapshots = PermissionSnapshotCache();
    final decoration = buildPermissionDecoration(
      snapshots: snapshots,
      execute: _ok,
      confirm: _confirm,
    );
    expect(decoration.available(SessionId('s1')), isFalse);
    snapshots.write('s1', _select());
    expect(decoration.available(SessionId('s1')), isTrue);
  });

  test('options filter custom, mark active, gate full access', () async {
    final snapshots = PermissionSnapshotCache()..write('s1', _select());
    final decoration = buildPermissionDecoration(
      snapshots: snapshots,
      execute: _ok,
      confirm: _confirm,
    );
    final options = await decoration.options(SessionId('s1'));
    expect(options.map((o) => o.id), ['read-only', 'danger-full-access']);
    expect(
      options.firstWhere((o) => o.id == 'read-only').active,
      isTrue,
    );
    final danger = options.firstWhere(
      (o) => o.id == 'danger-full-access',
    );
    expect(danger.active, isFalse);
    expect(danger.detail, 'Everything');
    expect(danger.confirmation, isNotNull);
    expect(danger.confirmation!.title, 'Enable Full access?');
    expect(danger.confirmation!.confirmLabel, 'Enable');
  });

  test('options throw when the projection is absent', () async {
    final decoration = buildPermissionDecoration(
      snapshots: PermissionSnapshotCache(),
      execute: _ok,
      confirm: _confirm,
    );
    await expectLater(
      decoration.options(SessionId('s1')),
      throwsStateError,
    );
  });

  test('onSelect posts the canonical line; refusals throw', () async {
    final calls = <String>[];
    Future<CommandExecutionOutcome> execute(SessionId _, String line) async {
      calls.add(line);
      return CommandExecutionOutcome.success('preset danger-full-access');
    }
    final snapshots = PermissionSnapshotCache()..write('s1', _select());
    final decoration = buildPermissionDecoration(
      snapshots: snapshots,
      execute: execute,
      confirm: _confirm,
    );
    final options = await decoration.options(SessionId('s1'));
    await decoration.onSelect(options[1], SessionId('s1'));
    expect(calls, ['/permission danger-full-access']);

    Future<CommandExecutionOutcome> refusing(SessionId _, String __) async =>
        CommandExecutionOutcome.error('unknown preset');
    final refusingDecoration = buildPermissionDecoration(
      snapshots: snapshots,
      execute: refusing,
      confirm: _confirm,
    );
    await expectLater(
      refusingDecoration.onSelect(options[0], SessionId('s1')),
      throwsStateError,
    );
  });

  test('duplicate decorations throw', () {
    final snapshots = PermissionSnapshotCache();
    final service = _service(snapshots: snapshots);
    expect(
      () => service.decorate(
        buildPermissionDecoration(
          snapshots: snapshots,
          execute: service.execute,
          confirm: _confirm,
        ),
      ),
      throwsStateError,
    );
  });

  test('bare enter opens the picker; argued lines claim', () async {
    final snapshots = PermissionSnapshotCache()..write('s1', _select());
    final service = _service(snapshots: snapshots);
    await service.directory.refresh(SessionId('s1'));

    final bare = await service.matchEnter(SessionId('s1'), '/permission');
    expect(bare, isA<HandledOutcome>());
    expect(service.popupOf(SessionId('s1')).state.value.open, isTrue);
    expect(
      service.popupOf(SessionId('s1')).state.value.command,
      'permission',
    );
    service.popupOf(SessionId('s1')).dismiss();

    final argued = await service.matchEnter(
      SessionId('s1'),
      '/permission read-only',
    );
    expect(argued, isA<ClaimOutcome>());
    expect(service.popupOf(SessionId('s1')).state.value.open, isFalse);
  });

  test('bare enter without the projection falls through to claim', () async {
    final service = _service(snapshots: PermissionSnapshotCache());
    await service.directory.refresh(SessionId('s1'));
    final bare = await service.matchEnter(SessionId('s1'), '/permission');
    // No decoration available: the hinted Host row claims like any argued
    // input-taking command (the composer shows the `/permission ` token).
    expect(bare, isA<ClaimOutcome>());
    expect(service.popupOf(SessionId('s1')).state.value.open, isFalse);
  });
}
