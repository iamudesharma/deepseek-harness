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
};

/// Interpolation helper for `message.compaction.completed`.
String formatCompactionCompleted(String template, int items, int tokens) =>
    template.replaceAll('{items}', '$items').replaceAll('{tokens}', '$tokens');
