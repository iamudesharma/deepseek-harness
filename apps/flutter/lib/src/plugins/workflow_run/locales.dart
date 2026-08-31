/// `workflowRun` namespace dictionaries — ported from
/// `packages/client/ui-workflow-run/src/client/locales.ts`.
library;

/// Dictionary namespace owned by this plugin.
const String kWorkflowRunNamespace = 'workflowRun';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kWorkflowRunZh = {
  'run.title': '{name}',
  'run.members.one': '{count} 个成员',
  'run.members.other': '{count} 个成员',
  'run.empty': '没有启动成员',
  'phase.unassigned': '未分阶段',
  'phase.empty': '空阶段名',
  'statusCount.running': '运行中 {count}',
  'statusCount.completed': '已完成 {count}',
  'statusCount.failed': '失败 {count}',
  'statusCount.cancelled': '已取消 {count}',
  'statusCount.interrupted': '已中断 {count}',
  'member.empty': '空成员名',
  'member.open': '打开 {name}',
  'status.running': '运行中',
  'status.completed': '已完成',
  'status.failed': '失败',
  'status.cancelled': '已取消',
  'status.interrupted': '已中断',
  // Flutter-surface additions: the Dart workflows screen's chrome.
  'screen.nav': '工作流',
  'screen.empty.title': '暂无工作流',
  'screen.empty.hint': '持久化工作流运行启动后会出现在会话中。',
};

/// English dictionary (same key set).
const Map<String, String> kWorkflowRunEn = {
  'run.title': '{name}',
  'run.members.one': '{count} member',
  'run.members.other': '{count} members',
  'run.empty': 'No members started',
  'phase.unassigned': 'Unphased',
  'phase.empty': 'Empty phase name',
  'statusCount.running': 'Running {count}',
  'statusCount.completed': 'Completed {count}',
  'statusCount.failed': 'Failed {count}',
  'statusCount.cancelled': 'Cancelled {count}',
  'statusCount.interrupted': 'Interrupted {count}',
  'member.empty': 'Empty member name',
  'member.open': 'Open {name}',
  'status.running': 'Running',
  'status.completed': 'Completed',
  'status.failed': 'Failed',
  'status.cancelled': 'Cancelled',
  'status.interrupted': 'Interrupted',
  // Flutter-surface additions: the Dart workflows screen's chrome.
  'screen.nav': 'Workflows',
  'screen.empty.title': 'No workflows',
  'screen.empty.hint':
      'Durable workflow runs appear in the conversation as they start.',
};
