/// `goal` namespace dictionaries — ported from
/// `packages/client/ui-goal/src/client/locales.ts`.
library;

/// Dictionary namespace owned by this plugin.
const String kGoalNamespace = 'goal';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kGoalZh = {
  'phase.active': '进行中的目标',
  'phase.paused': '已暂停的目标',
  'phase.blocked': '受阻的目标',
  'objective.aria': '目标内容',
  'commandInput.aria': '命令输入',
  'phase.complete': '已完成的目标',
  'action.save': '保存目标',
  'action.cancel': '取消编辑',
  'action.pause': '暂停目标',
  'action.resume': '恢复目标',
  'action.edit': '编辑目标',
  'action.clear': '清除目标',
  // Flutter-surface additions: the Dart goal screen's chrome.
  'empty.title': '未设置目标',
  'empty.hint': '使用 /goal 创建目标，即可在这里跟踪进度。',
};

/// English dictionary, checked complete against the zh key set.
const Map<String, String> kGoalEn = {
  'phase.active': 'Ongoing Goal',
  'phase.paused': 'Paused Goal',
  'phase.blocked': 'Blocked Goal',
  'objective.aria': 'Goal objective',
  'commandInput.aria': 'Command input',
  'phase.complete': 'Completed Goal',
  'action.save': 'Save goal',
  'action.cancel': 'Cancel edit',
  'action.pause': 'Pause goal',
  'action.resume': 'Resume goal',
  'action.edit': 'Edit goal',
  'action.clear': 'Clear goal',
  // Flutter-surface additions: the Dart goal screen's chrome.
  'empty.title': 'No goal set',
  'empty.hint': 'Create a goal with /goal to track progress here.',
};
