/// `workspace` namespace dictionaries — full-key port of
/// `packages/client/ui-workspace/src/client/locales.ts` (the browsing region:
/// section headers, view options, search chrome, tree rows, dialogs, and the
/// pick/add flow) plus Flutter-surface keys the Dart shell renders:
/// the `group.today`…`group.older` recency buckets (React renders recency
/// through the `time.*` hover keys) and `toggle.open`/`toggle.collapse`,
/// which React files under its separate `sidebar` namespace. The Dart shell
/// keeps one namespace here so every string stays plugin-registered.
library;

import '../../core/services/runtime_services.dart' show Translate;
import '../../utils/workspace_labels.dart' show RelativeTime, relativeTime;

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kWorkspaceZh = {
  'group.ungrouped': '未分组',
  // Flutter-surface additions (no React counterpart): sidebar recency buckets.
  'group.today': '今天',
  'group.yesterday': '昨天',
  'group.lastWeek': '前 7 天',
  'group.older': '更早',
  'session.new': '新会话',
  // Sidebar-chrome variants (React files them under `sidebar`; see header).
  'session.new.label': '新建会话',
  'session.blank': '空白会话',
  'toggle.open': '打开侧边栏',
  'toggle.collapse': '收起侧边栏',
  'section.workspaces': '工作区',
  'section.sessions': '会话',
  'viewOptions.label': '视图选项',
  'groupBy.label': '分组方式',
  'groupBy.workspace': '按工作区',
  'groupBy.flat': '单列表',
  'orderBy.label': '排序方式',
  'orderBy.manual': '手动排序',
  'orderBy.updated': '最近更新',
  'empty.none': '暂无会话',
  'empty.noneHint': '新建一个会话开始使用。',
  'empty.noMatches': '无匹配结果',
  'empty.noMatchesHint': '未找到匹配的会话。',
  'workspace.add': '添加工作区',
  'search.sessions.aria': '搜索会话',
  'search.placeholder': '搜索会话…',
  'search.clear': '清除搜索',
  'search.results.aria': '搜索结果',
  'search.pending': '正在搜索会话历史…',
  'search.unavailable': '内容搜索暂不可用，仅显示名称匹配。',
  'search.noMatches': '无匹配会话',
  'search.hasMore': '仅显示前 {n} 条结果，请缩小搜索范围。',
  'menu.addWorkspace': '添加工作区…',
  'picker.loading': '正在加载工作区…',
  'conflict.named': '已存在名为“{name}”的工作区。',
  'folderError.title': '无法打开文件夹',
  'folderError.retry': '重新选择',
  'rename': '重命名',
  'rename.workspace.title': '重命名工作区',
  'rename.session.title': '重命名会话',
  'field.workspaceName': '工作区名称',
  'field.sessionName': '会话名称',
  'delete.workspace': '删除工作区',
  'delete.desc': '将把“{name}”从工作区列表中移除。文件夹与会话记录会保留，其会话将显示在“未分组”下。',
  'delete.pending': '正在删除工作区…',
  'menu.fork': '分叉会话',
  'menu.archiveSession': '归档会话',
  'sessions.expand': '展开其余 {n} 个会话',
  'sessions.collapse': '收起',
  'sessions.count.one': '{n} 个会话',
  'sessions.count.other': '{n} 个会话',
  'actions.workspace.aria': '工作区“{name}”的操作',
  'actions.session.aria': '会话“{name}”的操作',
  'actions.newSession.aria': '在“{name}”中新建会话',
  'status.running': '进行中',
  'status.subagentsRunning.one': '{n} 个子代理运行中',
  'status.subagentsRunning.other': '{n} 个子代理运行中',
  'status.idle': '空闲',
  'status.waitingApproval': '等待审批',
  'status.planReview': '计划待审',
  'status.waitingAnswer': '等待回答',
  'status.completed': '已完成',
  'hover.created': '创建于 {time}',
  'hover.copied': '已复制',
  'date.ymd': '{y}年{m}月{d}日',
  'time.now': '刚刚',
  'time.minutes': '{n}分钟',
  'time.hours': '{n}小时',
  'time.days': '{n}天',
  'time.months': '{n}个月',
  'time.years': '{n}年',
  'time.ago': '{t}前',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kWorkspaceEn = {
  'group.ungrouped': 'Ungrouped',
  'group.today': 'Today',
  'group.yesterday': 'Yesterday',
  'group.lastWeek': 'Previous 7 Days',
  'group.older': 'Older',
  'session.new': 'New Session',
  // Sidebar-chrome variants (React files them under `sidebar`; see header).
  'session.new.label': 'New session',
  'session.blank': 'Blank session',
  'toggle.open': 'Open sidebar',
  'toggle.collapse': 'Collapse sidebar',
  'section.workspaces': 'Workspaces',
  'section.sessions': 'Sessions',
  'viewOptions.label': 'View options',
  'groupBy.label': 'Group by',
  'groupBy.workspace': 'WorkSpace',
  'groupBy.flat': 'In one list',
  'orderBy.label': 'Order by',
  'orderBy.manual': 'Manual',
  'orderBy.updated': 'Last updated',
  'empty.none': 'No sessions yet',
  'empty.noneHint': 'Create a new session to get started.',
  'empty.noMatches': 'No matches',
  'empty.noMatchesHint': 'No matching sessions found.',
  'workspace.add': 'Add workspace',
  'search.sessions.aria': 'Search sessions',
  'search.placeholder': 'Search sessions...',
  'search.clear': 'Clear search',
  'search.results.aria': 'Search results',
  'search.pending': 'Searching session history…',
  'search.unavailable':
      'Content search is temporarily unavailable. Showing name matches.',
  'search.noMatches': 'No matching sessions',
  'search.hasMore': 'Showing the first {n} results. Narrow your search.',
  'menu.addWorkspace': 'Add workspace…',
  'picker.loading': 'Loading workspaces…',
  'conflict.named': 'A workspace named “{name}” already exists.',
  'folderError.title': 'Couldn’t open folder',
  'folderError.retry': 'Choose again',
  'rename': 'Rename',
  'rename.workspace.title': 'Rename workspace',
  'rename.session.title': 'Rename session',
  'field.workspaceName': 'Workspace name',
  'field.sessionName': 'Session name',
  'delete.workspace': 'Delete workspace',
  'delete.desc': 'This removes “{name}” from the workspace list. The folder and session logs will be kept. Its sessions will appear under Ungrouped.',
  'delete.pending': 'Deleting workspace…',
  'menu.fork': 'Fork session',
  'menu.archiveSession': 'Archive session',
  'sessions.expand': 'Show {n} more sessions',
  'sessions.collapse': 'Show less',
  'sessions.count.one': '{n} session',
  'sessions.count.other': '{n} sessions',
  'actions.workspace.aria': 'Workspace actions for {name}',
  'actions.session.aria': 'Session actions for {name}',
  'actions.newSession.aria': 'New session in {name}',
  'status.running': 'Running',
  'status.subagentsRunning.one': '{n} subagent running',
  'status.subagentsRunning.other': '{n} subagents running',
  'status.idle': 'Idle',
  'status.waitingApproval': 'Waiting for approval',
  'status.planReview': 'Plan awaiting review',
  'status.waitingAnswer': 'Waiting for answer',
  'status.completed': 'Completed',
  'hover.created': 'Created {time}',
  'hover.copied': 'Copied',
  'date.ymd': '{y}-{m}-{d}',
  'time.now': 'now',
  'time.minutes': '{n}min',
  'time.hours': '{n}h',
  'time.days': '{n}d',
  'time.months': '{n}mo',
  'time.years': '{n}y',
  'time.ago': '{t} ago',
};

/// Locale namespace owned by this plugin.
const String kWorkspaceNamespace = 'workspace';

/// `{n}` interpolation helper for the count/expand templates.
String formatWorkspaceCount(String template, int n) =>
    template.replaceAll('{n}', '$n');

/// `{name}` interpolation helper for the action-aria/delete templates.
String formatWorkspaceNamed(String template, String name) =>
    template.replaceAll('{name}', name);

/// Localized compact row time ("刚刚"/"5分钟"/"3小时"…) — the dictionary
/// composition of [relativeTime] buckets (mirrors `tree.ts:relativeTime` +
/// the `time.*` keys).
String workspaceTimeLabel(int updatedAt, int now, Translate t) {
  final RelativeTime r = relativeTime(updatedAt, now);
  if (r.unit == 'now') return t('time.now');
  return formatWorkspaceCount(t('time.${r.unit}'), r.n);
}

/// Localized hover time — distance wrapped in the `time.ago` template,
/// `time.now` stays bare (mirrors `Rows.tsx:hoverTimeLabel`).
String workspaceHoverTimeLabel(int updatedAt, int now, Translate t) {
  final RelativeTime r = relativeTime(updatedAt, now);
  if (r.unit == 'now') return t('time.now');
  return t('time.ago')
      .replaceAll('{t}', formatWorkspaceCount(t('time.${r.unit}'), r.n));
}

/// Localized creation stamp — `date.ymd` wrapped in `hover.created`
/// (mirrors `Rows.tsx:createdLabel`).
String workspaceCreatedLabel(int createdAtMillis, Translate t) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  final String date = t('date.ymd')
      .replaceAll('{y}', '${d.year}')
      .replaceAll('{m}', '${d.month}')
      .replaceAll('{d}', '${d.day}');
  return t('hover.created').replaceAll('{time}', date);
}
