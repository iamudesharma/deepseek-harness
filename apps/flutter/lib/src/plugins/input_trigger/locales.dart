/// `slash.menu` namespace dictionaries — key-identical port of the menu
/// surface keys in
/// `packages/client/ui-input-trigger/src/client/locales.ts` (group titles
/// keyed by source name, the pending row, drill/crumb affordances, and the
/// listbox/header aria labels). Like React, an unregistered source name
/// misses the dictionary and renders its raw name (the lookup chain returns
/// the key).
library;

/// Dictionary namespace owned by this plugin.
const String kSlashMenuNamespace = 'slash.menu';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kSlashMenuZh = {
  'command': '指令',
  'skill': '技能',
  'subagent': '子智能体',
  'loading': '正在加载…',
  'drill.aria': '进入目录',
  'drill.hint': '进入目录',
  'drill.key': 'Tab',
  'crumbs.aria': '目录导航',
  'suggestions.aria': '触发候选建议',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kSlashMenuEn = {
  'command': 'Commands',
  'skill': 'Skills',
  'subagent': 'Subagents',
  'loading': 'Loading…',
  'drill.aria': 'Browse folder',
  'drill.hint': 'Browse folder',
  'drill.key': 'Tab',
  'crumbs.aria': 'Folder navigation',
  'suggestions.aria': 'Trigger suggestions',
};
