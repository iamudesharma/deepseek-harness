import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';

enum PresetTrust { system, user }

class AgentPresetOption {
  const AgentPresetOption({
    required this.id,
    required this.name,
    this.description,
    required this.trust,
    this.isDefault = false,
    this.broken,
    this.displayName,
  });
  final String id;
  final String name;
  final String? description;
  final PresetTrust trust;
  final bool isDefault;

  /// Why the preset fails to compose; non-null marks the card broken.
  final String? broken;

  /// Host display name (falls back to [id] when absent).
  final String? displayName;
}

/// One `agentPreset.list` read: the roster plus its deployment gates.
///
/// `authorable` gates copy/delete (a read-only deployment can neither);
/// `hasDocument` distinguishes open-in-editor from reveal-path (the
/// location action lands with the native opener face).
class AgentPresetRoster {
  const AgentPresetRoster({
    required this.presets,
    this.authorable = false,
    this.hasDocument = false,
  });

  final List<AgentPresetOption> presets;
  final bool authorable;
  final bool hasDocument;

  static const empty = AgentPresetRoster(presets: []);
}

/// Real `agentPreset.list` provider — parses `presets` plus `authorable` /
/// `hasDocument`. Calls
/// `ref.watch(connectionClientProvider).agentPresetList()` and maps
/// `AgentPresetEntry` (id, trust, isDefault, name, description, broken) to
/// [AgentPresetOption]. No synthetic delay — host is the source of truth.
final agentPresetListProvider = FutureProvider<AgentPresetRoster>((ref) async {
  final client = ref.watch(connectionClientProvider);
  final value = await client.agentPresetList();
  final presetsRaw = value['presets'] as List<dynamic>? ?? const [];
  return AgentPresetRoster(
    presets: presetsRaw.map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      final String id = map['id'] as String? ?? '';
      final String trustStr = map['trust'] as String? ?? 'system';
      final PresetTrust trust = trustStr == 'user'
          ? PresetTrust.user
          : PresetTrust.system;
      final bool isDefault = map['isDefault'] as bool? ?? false;
      final String? name = map['name'] as String?;
      final String? description = map['description'] as String?;
      final String? broken = map['broken'] as String?;
      // displayName fallback to id per contract.
      final String display = name ?? id;
      return AgentPresetOption(
        id: id,
        name: display,
        displayName: name ?? display,
        description: description,
        trust: trust,
        isDefault: isDefault,
        broken: broken,
      );
    }).toList(),
    authorable: value['authorable'] as bool? ?? false,
    hasDocument: value['hasDocument'] as bool? ?? false,
  );
});

/// Reads one shipped preset's composition through `agentPresets/read`
/// (React `section-store.ts:view`); failures surface to the caller.
Future<String> readPresetComposition(
  ConnectionClient client,
  String presetId,
) async {
  final value = await client.callMethod('agentPresets/read', {
    'agentPreset': presetId,
  });
  return value['content'] as String? ?? '';
}

/// Copies a preset through `agentPresets/copy {from, id, name}`
/// (React `confirmCopy`); the reply echoes the created id.
Future<String> copyPreset(
  ConnectionClient client, {
  required String from,
  required String presetId,
  String? name,
}) async {
  final value = await client.callMethod('agentPresets/copy', {
    'from': from,
    'id': presetId,
    if (name != null && name.isNotEmpty) 'name': name,
  });
  return value['agentPreset'] as String? ?? value['id'] as String? ?? presetId;
}

/// Deletes a user preset through `agentPresets/deletePreset` (React `remove`);
/// running sessions keep their mounted composition.
Future<void> removePreset(ConnectionClient client, String presetId) async {
  await client.callMethod('agentPresets/deletePreset', {'id': presetId});
}

// Synthetic fallback kept for offline / tests — not used when real provider succeeds.
final agentPresetOptionsProvider = StateProvider<List<AgentPresetOption>>(
  (ref) => const [
    AgentPresetOption(
      id: 'default',
      name: 'Default',
      description: 'Balanced general agent',
      trust: PresetTrust.system,
      isDefault: true,
    ),
    AgentPresetOption(
      id: 'plan',
      name: 'Plan',
      description: 'Read-only planning',
      trust: PresetTrust.system,
    ),
    AgentPresetOption(
      id: 'my-preset',
      name: 'My Custom Preset',
      description: 'Locally authored',
      trust: PresetTrust.user,
    ),
  ],
);

final agentPresetCurrentProvider = StateProvider<String>((ref) => 'default');

/// Legacy loading provider — now backed by real `agentPreset.list`.
///
/// Previously a synthetic `Future.delayed` stub; now waits for the real
/// [agentPresetListProvider] so legacy callers still hit the host without
/// duplication. New code should watch [agentPresetListProvider] directly.
final agentPresetLoadingProvider = FutureProvider<void>((ref) async {
  await ref.watch(agentPresetListProvider.future);
});
final agentPresetSavingProvider = StateProvider<bool>((ref) => false);
