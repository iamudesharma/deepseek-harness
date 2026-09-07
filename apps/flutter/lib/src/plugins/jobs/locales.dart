/// `job` namespace dictionaries — ported from
/// `packages/client/ui-jobs/src/client/locales.ts` (English copy; the zh
/// source of truth rides the React dictionaries and lands with bilingual
/// doc parity).
library;

/// Dictionary namespace owned by this plugin.
const String kJobNamespace = 'job';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kJobZh = {
  'count.live.one': '{count} 个后台任务运行中',
  'count.live.other': '{count} 个后台任务运行中',
  'count.idle.one': '{count} 个后台任务',
  'count.idle.other': '{count} 个后台任务',
  'list.aria': '后台任务',
  'status.running': '运行中',
  'status.stopping': '正在停止',
  'status.completed': '已完成',
  'status.killed': '已取消',
  'status.failed': '已失败',
  'duration.seconds': '{seconds}秒',
  'duration.minutes': '{minutes}分{seconds}秒',
  'duration.hours': '{hours}小时{minutes}分',
  'duration.title.live': '已运行 {duration}',
  'duration.title.done': '耗时 {duration}',
  // Flutter-surface additions: the Dart jobs screen's chrome.
  'header.count': '{n} 个任务',
  'badge.idle': '空闲',
  'empty.title': '暂无后台任务',
  'empty.hint': '后台任务会显示在这里。',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kJobEn = {
  'count.live.one': '{count} background job running',
  'count.live.other': '{count} background jobs running',
  'count.idle.one': '{count} background job',
  'count.idle.other': '{count} background jobs',
  'list.aria': 'Background jobs',
  'status.running': 'running',
  'status.stopping': 'stopping',
  'status.completed': 'completed',
  'status.killed': 'cancelled',
  'status.failed': 'failed',
  'duration.seconds': '{seconds}s',
  'duration.minutes': '{minutes}m {seconds}s',
  'duration.hours': '{hours}h {minutes}m',
  'duration.title.live': 'Running for {duration}',
  'duration.title.done': 'Took {duration}',
  // Flutter-surface additions: the Dart jobs screen's chrome.
  'header.count': '{n} jobs',
  'badge.idle': 'Idle',
  'empty.title': 'No jobs',
  'empty.hint': 'Background jobs will appear here.',
};
