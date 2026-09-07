/// `skill` namespace dictionaries — key-identical port of the React package's
/// `locales.ts` for the dedicated skill tool row.
library;

/// Dictionary namespace owned by this plugin.
const String kSkillNamespace = 'skill';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kSkillZh = {
  'row.running': '正在加载 skill',
  'row.failed': 'skill 加载失败',
  'row.stopped': 'skill 加载已中止',
  'row.instructions': '说明',
  'menu.userOnly': '仅用户',
  // Flutter-surface additions: the Dart skill screen's chrome.
  'screen.nav': 'Skills',
  'refresh': '刷新',
  'search.hint': '搜索 skills…',
  'loading': '正在加载 skills…',
  'loadFailed': '无法加载 skills',
  'empty.title': '未选择会话',
  'empty.hint': '选择一个会话以查看其 skill 目录。',
  'noMatches': '无匹配 skills',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kSkillEn = {
  'row.running': 'Loading skill',
  'row.failed': 'Skill load failed',
  'row.stopped': 'Skill load stopped',
  'row.instructions': 'Instructions',
  'menu.userOnly': 'user-only',
  // Flutter-surface additions: the Dart skill screen's chrome.
  'screen.nav': 'Skills',
  'refresh': 'Refresh',
  'search.hint': 'Search skills…',
  'loading': 'Loading skills…',
  'loadFailed': 'Failed to load skills',
  'empty.title': 'No session selected',
  'empty.hint': 'Select a session to view its skill catalog.',
  'noMatches': 'No matching skills',
};
