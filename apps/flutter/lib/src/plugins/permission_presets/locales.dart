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
  'confirm.title': 'Enable Full access?',
  'confirm.description': 'Full access lets new sessions reduce confirmation steps and perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust subsequent tasks.',
  'confirm.acknowledge': 'I understand the risks and want to continue',
  'confirm.cancel': 'Cancel',
  'confirm.enable': 'Enable Full access',
};

/// Simplified Chinese dictionary for the current-session popup gate.
const Map<String, String> kPermissionAccessZh = {
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

/// Host settings namespace the default preset is persisted under
/// (mirrors settings-store.ts PERMISSION_SETTINGS_NS).
const String kPermissionWireNamespace = 'permission';

/// Field carrying the new-session default preset.
const String kDefaultPresetField = 'defaultPreset';
