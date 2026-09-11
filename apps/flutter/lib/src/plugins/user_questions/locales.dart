/// `question` namespace dictionaries — key-identical port of
/// `packages/client/ui-user-questions/src/client/locales.ts`, plus the
/// Flutter-surface tool-approval keys the Dart approval card renders
/// (React's approval panel copy lives in ui-conversation's `access.*` keys;
/// the standalone reject/allow actions have no counterpart there).
library;

/// Dictionary namespace owned by this plugin.
const String kQuestionNamespace = 'question';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kQuestionZh = {
  'error.incomplete': '请先完成这道问题。',
  'error.unanswered': '请选择一个选项或填写自定义答案。',
  'nav.prev': '上一题',
  'nav.next': '下一题',
  'nav.minimize': '收起问题卡片',
  'nav.maximize': '展开问题卡片',
  'nav.cancel': '放弃整组问题',
  'option.recommended': '推荐',
  'custom.placeholder': '输入你的答案',
  'action.skip': '跳过本题',
  'action.next': '下一题',
  'plan.header': '计划待审',
  'plan.approve': '确认执行',
  'plan.decline': '拒绝',
  'plan.discuss': '去聊天里说',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kQuestionEn = {
  'error.incomplete': 'Please complete this question first.',
  'error.unanswered': 'Please select an option or enter a custom answer.',
  'nav.prev': 'Previous question',
  'nav.next': 'Next question',
  'nav.minimize': 'Collapse the question card',
  'nav.maximize': 'Expand the question card',
  'nav.cancel': 'Dismiss all questions',
  'option.recommended': 'Recommended',
  'custom.placeholder': 'Type your answer',
  'action.skip': 'Skip this question',
  'action.next': 'Next',
  'plan.header': 'Plan review',
  'plan.approve': 'Approve',
  'plan.decline': 'Refuse',
  'plan.discuss': 'Chat about it',
};

/// Dictionary namespace for the approval takeover — port of the `approval`
/// namespace in `packages/client/ui-approval/src/client/locales.ts`.
const String kApprovalNamespace = 'approval';

/// Simplified Chinese dictionary (the key-set source of truth, verbatim port).
const Map<String, String> kApprovalZh = {
  'waiting': '等待审批',
  'detail.aria': '审批详情',
  'escalation': '工具 {toolName} 请求越权执行',
  'reject': '拒绝',
  'allowOnce': '允许一次',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kApprovalEn = {
  'waiting': 'Waiting for approval',
  'detail.aria': 'Approval details',
  'escalation': 'Tool {toolName} requests privileged execution',
  'reject': 'Reject',
  'allowOnce': 'Allow once',
};
