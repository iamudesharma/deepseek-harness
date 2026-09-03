/// `feedback` namespace dictionaries — port of
/// `packages/client/ui-message-feedback/src/client/locales.ts` (React's `zh`
/// is the key-set source of truth) plus the standalone screen chrome keys.
/// React mounts these controls in the assistant message actions row; the
/// Flutter standalone screen listing one session's recorded rows has no React
/// counterpart, so the `screen.*` keys are Flutter-owned additions until the
/// `conversation.chat.assistant-actions` hole lands.
library;

/// Locale namespace owned by the message feedback plugin (React `NS = 'feedback'`).
const String kMessageFeedbackNamespace = 'feedback';

/// Simplified Chinese copy — `action.*` / `note.*` / `error.*` mirror React `zh`.
const Map<String, String> kMessageFeedbackZh = {
  'action.like': '好的回答',
  'action.likeActive': '取消标记',
  'action.dislike': '有问题的回答',
  'action.dislikeActive': '取消标记',
  'note.open': '补充说明',
  'note.dialog': '反馈',
  'note.placeholder': '这条回答哪里好，或哪里有问题？（可选）',
  'note.save': '保存',
  'note.cancel': '取消',
  'note.aria': '反馈说明',
  'error.conflict': '这条反馈已在别处改动，已显示最新状态',
  'error.load': '反馈状态加载失败',
  'error.generic': '反馈保存失败',
  'screen.title': '消息反馈',
  'screen.empty.title': '暂无反馈',
  'screen.empty.hint': '赞同或反对消息即可留下反馈。',
};

/// English copy — `action.*` / `note.*` / `error.*` mirror React `en`.
const Map<String, String> kMessageFeedbackEn = {
  'action.like': 'Good response',
  'action.likeActive': 'Remove rating',
  'action.dislike': 'Bad response',
  'action.dislikeActive': 'Remove rating',
  'note.open': 'Add a note',
  'note.dialog': 'Feedback',
  'note.placeholder': 'What was good, or what went wrong? (optional)',
  'note.save': 'Save',
  'note.cancel': 'Cancel',
  'note.aria': 'Feedback note',
  'error.conflict': 'This feedback changed elsewhere; the latest state is shown',
  'error.load': 'Could not load feedback',
  'error.generic': 'Could not save feedback',
  'screen.title': 'Message Feedback',
  'screen.empty.title': 'No feedback yet',
  'screen.empty.hint': 'Like or dislike messages to leave feedback.',
};
