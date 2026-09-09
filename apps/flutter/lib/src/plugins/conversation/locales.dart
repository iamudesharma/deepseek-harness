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
  // Transcript display row — mirrors `settings.transcript.*` in ui-chat
  // locales (React `NS = 'chat'`).
  'settings.transcript.title': '对话显示',
  'settings.transcript.description': '控制已完成轮次的过程内容',
  'settings.transcript.normal': 'Normal',
  'settings.transcript.compact': 'Compact',
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
  // Blank-session hero — mirrors `hero.*` in ui-conversation locales
  // (React `NS = 'conversation'`, `EmptyHero.tsx`).
  'hero.headline': '探索未至之境',
  'hero.preview': '预览版',
  'hero.chooseWorkspace': '选择工作区',
  // Hero composer placeholder with a workspace — mirrors
  // `placeholder.hero` in ui-conversation locales.
  'placeholder.hero': '描述你想要构建的内容… / 调用指令 @ 文件或对话',
  // Hero composer placeholder with no workspace (composer inert) — mirrors
  // `placeholder.workspace` in ui-conversation locales.
  'placeholder.workspace': '选择一个工作区开始',
  // Queue dock — mirrors `queue.*` in ui-conversation locales
  // (React `NS = 'conversation'`).
  'queue.count': '{n} 条排队消息',
  'queue.sending': '发送中…',
  'queue.image': '排队消息图片',
  'queue.file': '排队文件 {name}',
  'queue.edit': '编辑排队消息',
  'queue.edit.unsupported': '包含非文本内容，暂不支持编辑',
  'queue.save': '保存排队消息',
  'queue.cancelEdit': '取消编辑',
  'queue.remove': '删除排队消息',
  'queue.steer': '插话发送',
  'queue.steer.unavailable': '仅运行中可插话发送',
  'queue.editFailed': '编辑失败：这条消息可能已经开始发送。',
  'queue.removeFailed': '删除失败：这条消息可能已经开始发送。',
  'queue.steerFailed': '插话发送失败，请重试。',
  // Composer primary disc labels — mirrors `input.stop` / `input.send` in
  // ui-conversation locales (React `NS = 'conversation'`).
  'input.stop': '停止生成',
  'input.send': '发送消息',
  // Session header breadcrumb nav landmark.
  'session.hierarchy': '会话层级',
  // Todo dock panel — mirrors `todo.title` + `todo.progress.*` in
  // ui-conversation locales (React `NS = 'conversation'`).
  'todo.title': '任务',
  'todo.progress.done': '{done} 已完成',
  'todo.progress.active': '{active} 进行中',
  'todo.progress.pending': '{pending} 待处理',
  // Context-occupancy meter — mirrors `context.*` in ui-conversation
  // locales (React `NS = 'conversation'`).
  'context.aria': '上下文已用 {percent}',
  'context.used': '上下文已用',
  'context.system': '系统提示词',
  'context.tools': '工具',
  'context.messages': '对话消息',
  // Composer "+" command-menu trigger — mirrors `input.commands` in
  // ui-conversation locales (React `+` button tooltip/aria-label).
  'input.commands': '指令', 'todo.completed': '{done}/{total} 已完成',
  'message.think': '思考',
  'row.running': '运行中',
  'message.turnProcess.toolCalls.one': '{count} 次工具调用',
  'message.turnProcess.toolCalls.other': '{count} 次工具调用',
  'message.turnProcess.messages.one': '{count} 条消息',
  'message.turnProcess.messages.other': '{count} 条消息',
  'message.turnProcess.subagents.one': '{count} 个 subagent',
  'message.turnProcess.subagents.other': '{count} 个 subagent',
  'message.turnProcess.thoughtForAWhile': '已思考',
  'message.turnProcess.separator': ' · ',
  // Session stats line below the composer — mirrors `stats.*` in ui-chat
  // locales (React `NS = 'chat'`); templates take final display strings.
  'stats.counts': '{turns} 轮 · {steps} 步',
  'stats.llm': 'LLM {duration}',
  'stats.toolCall': '工具调用 {duration}',
  'stats.ttftAverage': '首 token 平均 {duration}',
  'stats.tokensPerSecond': '{throughput} tok/s',
  'stats.cacheHit': '缓存命中 {percent}%',
  'stats.tokens': '输入 {input} tok · 输出 {output} tok',
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
  // Transcript display row — mirrors `settings.transcript.*` in ui-chat
  // locales (React `NS = 'chat'`).
  'settings.transcript.title': 'Conversation display',
  'settings.transcript.description': 'Controls process content in completed turns',
  'settings.transcript.normal': 'Normal',
  'settings.transcript.compact': 'Compact',
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
  // Blank-session hero — mirrors `hero.*` in ui-conversation locales
  // (React `NS = 'conversation'`, `EmptyHero.tsx`).
  'hero.headline': 'Into the Unknown',
  'hero.preview': 'Preview',
  'hero.chooseWorkspace': 'Choose workspace',
  // Hero composer placeholder with a workspace — mirrors
  // `placeholder.hero` in ui-conversation locales.
  'placeholder.hero': 'Describe what you want to build... / commands, @ files or sessions',
  // Hero composer placeholder with no workspace (composer inert) — mirrors
  // `placeholder.workspace` in ui-conversation locales.
  'placeholder.workspace': 'Choose a workspace to start',
  // Queue dock — mirrors `queue.*` in ui-conversation locales
  // (React `NS = 'conversation'`).
  'queue.count': '{n} queued messages',
  'queue.sending': 'Sending…',
  'queue.image': 'Queued message image',
  'queue.file': 'Queued file {name}',
  'queue.edit': 'Edit queued message',
  'queue.edit.unsupported': 'Contains non-text content; editing is not supported yet',
  'queue.save': 'Save queued message',
  'queue.cancelEdit': 'Cancel editing',
  'queue.remove': 'Remove queued message',
  'queue.steer': 'Steer queued message',
  'queue.steer.unavailable': 'Steering is available only while the agent is running',
  'queue.editFailed': 'Edit failed: this message may have already started sending.',
  'queue.removeFailed': 'Removal failed: this message may have already started sending.',
  'queue.steerFailed': 'Steering failed. Try again.',
  // Composer primary disc labels — mirrors `input.stop` / `input.send` in
  // ui-conversation locales (React `NS = 'conversation'`).
  'input.stop': 'Stop generating',
  'input.send': 'Send message',
  // Session header breadcrumb nav landmark.
  'session.hierarchy': 'Session hierarchy',
  // Todo dock panel — mirrors `todo.title` + `todo.progress.*` in
  // ui-conversation locales (React `NS = 'conversation'`).
  'todo.title': 'To-dos',
  'todo.progress.done': '{done} completed',
  'todo.progress.active': '{active} in progress',
  'todo.progress.pending': '{pending} pending',
  // Context-occupancy meter — mirrors `context.*` in ui-conversation
  // locales (React `NS = 'conversation'`).
  'context.aria': '{percent} of context used',
  'context.used': 'of context used',
  'context.system': 'System prompt',
  'context.tools': 'Tools',
  'context.messages': 'Messages',
  // Composer "+" command-menu trigger — mirrors `input.commands` in
  // ui-conversation locales (React `+` button tooltip/aria-label).
  'input.commands': 'Commands',
  'todo.completed': '{done}/{total} completed',
  'message.think': 'Think',
  'row.running': 'Running',
  'message.turnProcess.toolCalls.one': '{count} tool call',
  'message.turnProcess.toolCalls.other': '{count} tool calls',
  'message.turnProcess.messages.one': '{count} message',
  'message.turnProcess.messages.other': '{count} messages',
  'message.turnProcess.subagents.one': '{count} subagent',
  'message.turnProcess.subagents.other': '{count} subagents',
  'message.turnProcess.thoughtForAWhile': 'Thought for a while',
  'message.turnProcess.separator': ' · ',
  // Session stats line below the composer — mirrors `stats.*` in ui-chat
  // locales (React `NS = 'chat'`); templates take final display strings.
  'stats.counts': '{turns} turns · {steps} steps',
  'stats.llm': 'LLM {duration}',
  'stats.toolCall': 'Tool call {duration}',
  'stats.ttftAverage': 'TTFT avg {duration}',
  'stats.tokensPerSecond': '{throughput} tok/s',
  'stats.cacheHit': 'Cache hit {percent}%',
  'stats.tokens': 'Input {input} tok · Output {output} tok',
};

/// Interpolation helper for `message.compaction.completed`.
String formatCompactionCompleted(String template, int items, int tokens) =>
    template.replaceAll('{items}', '$items').replaceAll('{tokens}', '$tokens');

/// Builds the turn-process group label exactly like React
/// `TurnProcessNodeView` (`{N tool call(s)} · {M message(s)} ·
/// {K subagent(s)}`, non-zero counts only, else the fallback line).
/// Counts come from the ledger's `TurnProcessNode`; [t] resolves a locale
/// key and `{count}` is substituted by the caller side.
String formatTurnProcessLabel({
  required int toolCallCount,
  required int messageCount,
  required int subagentCount,
  required String Function(String key) t,
}) {
  final parts = <String>[];
  if (toolCallCount > 0) {
    parts.add(
      t(
        toolCallCount == 1
            ? 'message.turnProcess.toolCalls.one'
            : 'message.turnProcess.toolCalls.other',
      ).replaceAll('{count}', '$toolCallCount'),
    );
  }
  if (messageCount > 0) {
    parts.add(
      t(
        messageCount == 1
            ? 'message.turnProcess.messages.one'
            : 'message.turnProcess.messages.other',
      ).replaceAll('{count}', '$messageCount'),
    );
  }
  if (subagentCount > 0) {
    parts.add(
      t(
        subagentCount == 1
            ? 'message.turnProcess.subagents.one'
            : 'message.turnProcess.subagents.other',
      ).replaceAll('{count}', '$subagentCount'),
    );
  }
  if (parts.isEmpty) return t('message.turnProcess.thoughtForAWhile');
  return parts.join(t('message.turnProcess.separator'));
}
