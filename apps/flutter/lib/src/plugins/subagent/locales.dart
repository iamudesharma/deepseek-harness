/// `subagent` namespace dictionaries — key-identical port of the React
/// package's `locales.ts` (zh is the source of truth; en mirrors every key).
library;

/// Dictionary namespace owned by this plugin.
const String kSubagentNamespace = 'subagent';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kSubagentZh = {
  'diagnostic.corrupt': '会话记录损坏',
  'diagnostic.unsupported': '子代理记录版本不受支持',
  'diagnostic.unavailable': '会话记录暂不可用',
  'duration.seconds': '{seconds}秒',
  'duration.minutes': '{minutes}分{seconds}秒',
  'duration.hours': '{hours}小时{minutes}分{seconds}秒',
  'duration.days': '{days}天',
  'duration.daysHours': '{days}天{hours}小时',
  'loading.label': '正在加载子代理…',
  'load.error': '无法加载子代理',
  'retry': '重试',
  'mode.oneShot': '一次性',
  'mode.continuable': '可继续',
  'activity.running': '正在运行',
  'activity.inactive': '当前未运行',
  'count.total.one': '{count} 个子代理',
  'count.total.other': '{count} 个子代理',
  'count.running.one': '{count} 个子代理，正在运行',
  'count.running.other': '{count} 个子代理，正在运行',
  'tree.aria': '子代理会话',
  'readonly.oneShot.title': '一次性子代理记录',
  'readonly.title': '此子代理暂时只读',
  'readonly.oneShot.body': '一次性任务不支持后续消息，可在这里查看完整执行记录。',
  'readonly.body': '父会话当前不在线，重新打开父会话后即可继续发送消息。',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kSubagentEn = {
  'diagnostic.corrupt': 'corrupted session record',
  'diagnostic.unsupported': 'unsupported subagent record version',
  'diagnostic.unavailable': 'session record temporarily unavailable',
  'duration.seconds': '{seconds}s',
  'duration.minutes': '{minutes}m {seconds}s',
  'duration.hours': '{hours}h {minutes}m {seconds}s',
  'duration.days': '{days}d',
  'duration.daysHours': '{days}d {hours}h',
  'loading.label': 'Loading subagents…',
  'load.error': 'Unable to load subagents',
  'retry': 'Retry',
  'mode.oneShot': 'one-shot',
  'mode.continuable': 'continuable',
  'activity.running': 'running',
  'activity.inactive': 'not running',
  'count.total.one': '{count} subagent',
  'count.total.other': '{count} subagents',
  'count.running.one': '{count} subagent running',
  'count.running.other': '{count} subagents running',
  'tree.aria': 'Subagent sessions',
  'readonly.oneShot.title': 'One-shot subagent record',
  'readonly.title': 'This subagent is read-only for now',
  'readonly.oneShot.body': 'One-shot tasks do not accept follow-ups; review the full execution record here.',
  'readonly.body':
      'The parent session is offline; reopen it to continue sending messages.',
};
