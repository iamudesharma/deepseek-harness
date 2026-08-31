import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PermissionPreset { defaultRead, workspaceWrite, fullAccess }

extension PermissionPresetLabel on PermissionPreset {
  String get id => switch (this) {
    PermissionPreset.defaultRead => 'default',
    PermissionPreset.workspaceWrite => 'workspace-write',
    PermissionPreset.fullAccess => 'danger-full-access',
  };
  String get label => switch (this) {
    PermissionPreset.defaultRead => 'Read only',
    PermissionPreset.workspaceWrite => 'Workspace write',
    PermissionPreset.fullAccess => 'Full access',
  };
  String get description => switch (this) {
    PermissionPreset.defaultRead =>
      'Can read files, no edits without approval.',
    PermissionPreset.workspaceWrite =>
      'Can edit inside workspace; outside needs approval.',
    PermissionPreset.fullAccess => 'No permission prompts — full host access.',
  };
}

final permissionSelectedProvider = StateProvider<PermissionPreset>(
  (ref) => PermissionPreset.workspaceWrite,
);
final permissionLoadingProvider = FutureProvider<void>((ref) async {
  await Future.delayed(const Duration(milliseconds: 300));
});
final permissionSavingProvider = StateProvider<bool>((ref) => false);
