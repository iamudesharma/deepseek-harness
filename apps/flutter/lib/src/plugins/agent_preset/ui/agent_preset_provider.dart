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
/// `hasDocument` distinguishes open-in-editor from reveal-path for the
/// location action. `hasDocument` is the Host's opener capability
/// (`settings/canOpenAgentPresetDirectory`), NOT a roster property — the host
/// docstring on `remoteExportList` is explicit that a caller needing both
/// joins them, and `agentPresets/list` answers `{presets, authorable}` only.
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

/// Copy-id rule mirroring React `PRESET_ID` (`section-store.ts`): the id
/// becomes the preset's directory name, so it is required.
final RegExp kPresetIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// Why a copy draft cannot be submitted yet, as a locale key, or null when
/// it can. Exact port of React `draftBlocker`: empty, then shape, then
/// collision (a copy never overwrites).
///
/// @param id - the id typed into the copy dialog.
/// @param rows - the roster, for the collision check.
/// @returns the blocking reason's locale key, or null when submittable.
String? presetCopyBlocker(String id, List<AgentPresetOption> rows) {
  if (id.isEmpty) return 'idRequired';
  if (!kPresetIdPattern.hasMatch(id)) return 'idInvalid';
  if (rows.any((row) => row.id == id)) return 'idTaken';
  return null;
}

/// Where one preset's files landed: opened on the host desktop, or revealed
/// as text where the deployment has no opener.
class PresetLocation {
  const PresetLocation.opened() : opened = true, path = null;
  const PresetLocation.revealed(this.path) : opened = false;

  /// True when the host desktop took the directory (nothing to show).
  final bool opened;

  /// The resolved directory, set only when [opened] is false.
  final String? path;
}

/// Preset directories shown as text because the host has no desktop opener —
/// the answer `openAgentPresetDirectory` gives instead of opening. Keyed by
/// preset id; a reveal outlives a reload but not its preset (entries for ids
/// the roster no longer lists are pruned on the next load).
final agentPresetRevealedPathsProvider =
    StateProvider<Map<String, String>>((ref) => const {});

/// Real `agentPreset.list` provider — parses `presets` plus `authorable`,
/// joined with `settings/canOpenAgentPresetDirectory` exactly like React
/// `section-store.ts:load`. A refused opener removes only the native-open
/// affordance (`hasDocument: false`); the roster still loads. Calls
/// `ref.watch(connectionClientProvider).agentPresetList()` and maps
/// `AgentPresetEntry` (id, trust, isDefault, name, description, broken) to
/// [AgentPresetOption]. No synthetic delay — host is the source of truth.
final agentPresetListProvider = FutureProvider<AgentPresetRoster>((ref) async {
  final client = ref.watch(connectionClientProvider);
  // Issued together like React: one round trip decides the page, and a load
  // that waited for them in turn would hold the section in `loading` twice
  // as long. The opener error is contained here so it never fails the roster.
  final Future<bool> opener = client
      .settingsCanOpenAgentPresetDirectory()
      .then<bool>((bool v) => v, onError: (_) => false);
  final value = await client.agentPresetList();
  final bool hasDocument = await opener;
  final presetsRaw = value['presets'] as List<dynamic>? ?? const [];
  final List<AgentPresetOption> presets = presetsRaw.map((dynamic e) {
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
  }).toList();
  final ids = presets.map((p) => p.id).toSet();
  final revealed = ref.read(agentPresetRevealedPathsProvider);
  if (revealed.keys.any((id) => !ids.contains(id))) {
    ref.read(agentPresetRevealedPathsProvider.notifier).state = {
      for (final entry in revealed.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    };
  }
  return AgentPresetRoster(
    presets: presets,
    authorable: value['authorable'] as bool? ?? false,
    hasDocument: hasDocument,
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

/// Persists one preset as the default for sessions created later (React
/// `writeDefaultPreset` in `settings-store.ts` over
/// `settings.update('agent-presets', {default: id})`).
///
/// The default is a settings field rather than a preset property; the host
/// resolves it at session creation, so this is what makes a management-card
/// pick reflect throughout the app. Running sessions keep the composition
/// they began with. Returns the failure message, or null once the write
/// landed and the caller should re-read the roster.
Future<String?> makeDefaultPreset(ConnectionClient client, String id) async {
  try {
    await client.settingsUpdate(
      ns: 'agent-presets',
      patch: {'default': id},
    );
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// Opens one user preset's directory on the host desktop, or reveals its
/// path where the deployment has no opener (React `section-store.ts:
/// openLocation` over `settings/openAgentPresetDirectory`). Failures surface
/// to the caller; a refused open is a page-level error in React, while the
/// reveal path is stored by the caller in [agentPresetRevealedPathsProvider].
Future<PresetLocation> openPresetLocation(
  ConnectionClient client,
  String presetId,
) async {
  final value = await client.settingsOpenAgentPresetDirectory(
    agentPreset: presetId,
  );
  if (value['opened'] == true) return const PresetLocation.opened();
  return PresetLocation.revealed(value['path'] as String? ?? '');
}

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
