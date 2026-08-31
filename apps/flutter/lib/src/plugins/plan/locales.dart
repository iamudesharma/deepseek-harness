/// `plan` namespace dictionaries — key-identical port of the React package's
/// `locales.ts` (the composer plan chip's copy; the chip wordmark stays
/// 'Plan' in every locale by design).
library;

/// Dictionary namespace owned by this plugin.
const String kPlanNamespace = 'plan';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kPlanZh = {
  'chip.on.aria': 'plan mode 已开启，按下关闭',
  'chip.on.title': 'plan mode 已开启 — 点击关闭（/plan off）',
  'chip.off.aria': 'plan mode 已关闭，按下开启',
  'chip.off.title': 'plan mode 已关闭 — 点击开启（/plan）',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kPlanEn = {
  'chip.on.aria': 'Plan mode on, press to turn off',
  'chip.on.title': 'Plan mode on — click to turn off (/plan off)',
  'chip.off.aria': 'Plan mode off, press to turn on',
  'chip.off.title': 'Plan mode off — click to turn on (/plan)',
};

/// Flutter-surface additions (no React counterpart): the Dart plan screen's
/// chrome; React ships only the composer chip copy above.
const Map<String, String> kPlanScreenZh = {
  'screen.nav': '计划模式',
  'off.title': '计划模式未开启',
  'off.hint': '开启计划模式，让智能体先做只读规划。',
  'enter': '进入计划模式',
};

/// English copy (same key set).
const Map<String, String> kPlanScreenEn = {
  'screen.nav': 'Plan Mode',
  'off.title': 'Plan mode off',
  'off.hint': 'Enter plan mode to scope the agent to read-only planning.',
  'enter': 'Enter plan mode',
};
