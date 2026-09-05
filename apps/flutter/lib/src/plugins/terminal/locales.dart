/// `terminal` namespace dictionaries for the console terminal panel.
///
/// The console surface is Flutter-new (no React reference); the zh
/// dictionary is the key-set source of truth and en stays key-identical.
library;

/// Dictionary namespace owned by this plugin.
const String kTerminalNamespace = 'terminal';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kTerminalZh = {
  'list.aria': '终端',
  'action.label': '终端',
  'action.tooltip': '打开控制台终端',
  'empty.title': '暂无终端会话',
  'empty.hint': '新建一个会话，在宿主上打开控制台 shell。',
  'new.action': '新建会话',
  'new.name.hint': '会话名称（可选）',
  'tab.untitled': '未命名',
  'status.running': '运行中',
  'status.exited': '已退出',
  'status.exited.code': '已退出（{code}）',
  'error.open': '打开失败：{message}',
  'error.send': '发送失败：{message}',
  'error.unavailable': '宿主未挂载终端后端。',
  'toolbar.refresh': '读取输出',
  'toolbar.interrupt': '发送 Ctrl+C',
  'toolbar.interrupt.tooltip': '向前台进程组发送 SIGINT',
  'toolbar.close': '关闭会话',
  'close.confirm': '关闭此终端会话？',
  'close.cancel': '取消',
  'close.confirm.action': '关闭',
  'closed.note': '会话已结束。',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kTerminalEn = {
  'list.aria': 'Terminal',
  'action.label': 'Terminal',
  'action.tooltip': 'Open the console terminal',
  'empty.title': 'No terminal sessions',
  'empty.hint': 'Start a session to open a console shell on the host.',
  'new.action': 'New session',
  'new.name.hint': 'Session name (optional)',
  'tab.untitled': 'untitled',
  'status.running': 'running',
  'status.exited': 'exited',
  'status.exited.code': 'exited ({code})',
  'error.open': 'Open failed: {message}',
  'error.send': 'Send failed: {message}',
  'error.unavailable': 'No terminal backend is mounted on the host.',
  'toolbar.refresh': 'Read output',
  'toolbar.interrupt': 'Send Ctrl+C',
  'toolbar.interrupt.tooltip': 'Deliver SIGINT to the foreground process group',
  'toolbar.close': 'Close session',
  'close.confirm': 'Close this terminal session?',
  'close.cancel': 'Cancel',
  'close.confirm.action': 'Close',
  'closed.note': 'Session ended.',
};
