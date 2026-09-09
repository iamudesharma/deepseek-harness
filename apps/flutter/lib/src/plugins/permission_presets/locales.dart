/// `settings.permission` + `permission.access` namespace dictionaries — port
/// of `packages/client/ui-permission-presets/src/client/locales.ts`.
library;

/// Locale namespace owning the settings row copy.
const String kPermissionSettingsNamespace = 'settings.permission';

/// Locale namespace owning the current-session popup gate copy.
const String kPermissionAccessNamespace = 'permission.access';

/// Simplified Chinese dictionary for the settings row (key-set source).
const Map<String, String> kPermissionSettingsZh = {
  'title': '权限',
  'description': '选择新会话的默认权限模式',
  'loading': '加载中',
  'unavailable': '不可用',
  'preset.readOnly': '仅可查看',
  'preset.workspaceWrite': '工作区内修改',
  'preset.fullAccess': '完全权限',
  'confirm.title': '确认启用 Full access？',
  'confirm.description': '启用 Full access 后，新会话将减少确认步骤，并且可以直接执行更多操作，包括敏感操作、文件修改或外部命令。仅建议在你信任后续任务时使用。',
  'confirm.acknowledge': '我已了解风险，并愿意继续',
  'confirm.cancel': '取消',
  'confirm.enable': '启用 Full access',
};

/// English dictionary for the settings row.
const Map<String, String> kPermissionSettingsEn = {
  'title': 'Permission',
  'description': 'Choose the default permission mode for new sessions',
  'loading': 'Loading',
  'unavailable': 'Unavailable',
  'preset.readOnly': 'Read Only',
  'preset.workspaceWrite': 'Workspace Write',
  'preset.fullAccess': 'Full access',
  'confirm.title': 'Enable Full access?',
  'confirm.description': 'Full access lets new sessions reduce confirmation steps and perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust subsequent tasks.',
  'confirm.acknowledge': 'I understand the risks and want to continue',
  'confirm.cancel': 'Cancel',
  'confirm.enable': 'Enable Full access',
};

/// Simplified Chinese dictionary for the current-session popup gate.
const Map<String, String> kPermissionAccessZh = {
  // Built-in product labels (mirrors accessZh preset.* — the seat resolves
  // conventional values through these, like React `displayPermissionPreset`).
  'preset.readOnly': '仅可查看',
  'preset.workspaceWrite': '工作区内修改',
  'preset.fullAccess': '完全权限',
  // Flutter-surface additions: the composer gate chip's own chrome.
  'accessMode': '访问模式',
  'custom': '自定义',
  'switchFailed': '权限切换失败',
  'confirm.title': '确认启用 Full access？',
  'confirm.description': '启用 Full access 后，agent 将减少确认步骤，并且可以直接执行更多操作，包括敏感操作、文件修改或外部命令。仅建议在你信任当前任务时使用。',
  'confirm.acknowledge': '我已了解风险，并愿意继续',
  'confirm.cancel': '取消',
  'confirm.enable': '启用 Full access',
};

/// English dictionary for the current-session popup gate.
const Map<String, String> kPermissionAccessEn = {
  'preset.readOnly': 'Read Only',
  'preset.workspaceWrite': 'Workspace Write',
  'preset.fullAccess': 'Full access',
  'accessMode': 'Access mode',
  'custom': 'Custom',
  'switchFailed': 'Permission switch failed',
  'confirm.title': 'Enable Full access?',
  'confirm.description': 'Full access reduces confirmation steps and lets the agent perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust the current task.',
  'confirm.acknowledge': 'I understand the risks and want to continue',
  'confirm.cancel': 'Cancel',
  'confirm.enable': 'Enable Full access',
};

/// Machine value of the preset that requires an explicit GUI risk gate
/// (mirrors presentation.ts FULL_ACCESS_PRESET).
const String kFullAccessPreset = 'danger-full-access';

// ---------------------------------------------------------------------------
// Preset labels — mirrors `presentation.ts`
// ---------------------------------------------------------------------------

/// Locale key for a built-in permission preset label.
const Map<String, String> kPresetLabelKeys = {
  'read-only': 'preset.readOnly',
  'workspace-write': 'preset.workspaceWrite',
  kFullAccessPreset: 'preset.fullAccess',
};

/// English defaults used to recognize host-supplied conventional names.
const Map<String, String> kDefaultPresetLabels = {
  'preset.readOnly': 'Read Only',
  'preset.workspaceWrite': 'Workspace Write',
  'preset.fullAccess': 'Full access',
};

/// Converts conventional kebab-case preset names into title case, mirroring
/// `displayPresetName` (non-kebab labels pass through unchanged).
String displayPresetName(String name) {
  if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name)) return name;
  return name
      .split('-')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

/// Renders a permission preset under its product label, mirroring
/// `displayPermissionPreset`: a built-in value whose host name is still the
/// conventional default resolves through the locale dictionary; a renamed
/// (custom) preset keeps its own name verbatim.
String displayPermissionPreset(
  String value,
  String name,
  String Function(String key) t,
) {
  final key = kPresetLabelKeys[value];
  if (key != null && (name == value || name == kDefaultPresetLabels[key])) {
    return t(key);
  }
  return displayPresetName(name);
}

/// Host settings namespace the default preset is persisted under
/// (mirrors settings-store.ts PERMISSION_SETTINGS_NS).
const String kPermissionWireNamespace = 'permission';

/// Field carrying the new-session default preset.
const String kDefaultPresetField = 'defaultPreset';
