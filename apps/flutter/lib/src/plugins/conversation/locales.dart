/// `conversation` namespace dictionaries — port of
/// `packages/client/ui-conversation/src/client/locales.ts` compaction keys
/// plus the narrow set used by the Flutter compaction seam (React's `zh` is
/// the key-set source of truth).
library;

/// Locale namespace owned by the conversation plugin (React `NS = 'conversation'`).
const String kConversationNamespace = 'conversation';

/// Simplified Chinese copy — keys mirror React `zh`.
const Map<String, String> kConversationZh = {
  'message.compaction': '上下文已压缩',
  'message.compaction.running': '正在压缩…',
  'message.compaction.completed': '已压缩 {items} 条历史记录（约 {tokens} tokens）',
  'message.compaction.expand': '点击查看压缩摘要',
  'message.compaction.unavailable': '压缩摘要不可用',
  // Settings General section's Enter-behavior row (React-cited keys).
  'settings.enter.title': '繁忙时 Enter 键行为',
  'settings.enter.description': '仅在智能体运行时生效；Cmd/Ctrl+Enter 使用另一行为',
  'settings.enter.queue': '排队发送',
  'settings.enter.steer': '插话发送',
  // Mobile attachment sheet — mirrors ImageLightbox/AttachmentRail labels.
  'attachment.takePhoto': '拍照',
  'attachment.photoLibrary': '相册',
  'attachment.chooseDocument': '选择文件',
  // Tool row titles — mirrors `tool.title.*` in ui-conversation locales.
  'tool.title.search': '搜索',
  'tool.title.read': '读取',
  'tool.title.bash': 'Bash',
  'tool.title.write': '写入',
  'tool.title.edit': '编辑',
  'tool.title.code': '代码',
  'tool.title.generic': '工具调用',
  'tool.title.inspect': '检查',
  'tool.title.runCordis': '运行 Cordis',
  'tool.title.stopCordis': '停止 Cordis',
  'tool.title.removeCordis': '移除 Cordis',
  'tool.title.pwsh': 'Pwsh',
  'tool.title.readImage': '读取图片',
  'tool.title.grep': '搜索',
  'tool.title.glob': '搜索',
  'tool.title.webSearch': '网页搜索',
  'tool.title.webFetch': '网页抓取',
  'todo.rowTitle': '更新任务清单',
  'todo.completed': '{done}/{total} 已完成',
  'message.think': '思考',
};

/// English copy — keys mirror React `en`.
const Map<String, String> kConversationEn = {
  'message.compaction': 'Context compacted',
  'message.compaction.running': 'Compacting context…',
  'message.compaction.completed':
      'Compacted {items} history items (~{tokens} tokens)',
  'message.compaction.expand': 'View compaction summary',
  'message.compaction.unavailable': 'Compaction summary unavailable',
  'settings.enter.title': 'Enter behavior while busy',
  'settings.enter.description':
      'Busy only; Cmd/Ctrl+Enter uses the other behavior',
  'settings.enter.queue': 'Queue',
  'settings.enter.steer': 'Steer',
  // Mobile attachment sheet.
  'attachment.takePhoto': 'Take photo',
  'attachment.photoLibrary': 'Photo library',
  'attachment.chooseDocument': 'Choose document',
  // Tool row titles — mirrors `tool.title.*` in ui-conversation locales.
  'tool.title.search': 'Search',
  'tool.title.read': 'Read',
  'tool.title.bash': 'Bash',
  'tool.title.write': 'Write',
  'tool.title.edit': 'Edit',
  'tool.title.code': 'Code',
  'tool.title.generic': 'Tool call',
  'tool.title.inspect': 'Inspect',
  'tool.title.runCordis': 'Run Cordis',
  'tool.title.stopCordis': 'Stop Cordis',
  'tool.title.removeCordis': 'Remove Cordis',
  'tool.title.pwsh': 'Pwsh',
  'tool.title.readImage': 'Read image',
  'tool.title.grep': 'Search',
  'tool.title.glob': 'Search',
  'tool.title.webSearch': 'Web search',
  'tool.title.webFetch': 'Web fetch',
  'todo.rowTitle': 'Update to-do list',
  'todo.completed': '{done}/{total} completed',
  'message.think': 'Think',
};

/// Interpolation helper for `message.compaction.completed`.
String formatCompactionCompleted(String template, int items, int tokens) =>
    template.replaceAll('{items}', '$items').replaceAll('{tokens}', '$tokens');
