/// `deliverables` namespace dictionaries — ported from
/// `packages/client/ui-deliverables/src/client/locales.ts`.
library;

/// Dictionary namespace owned by this plugin.
const String kDeliverablesNamespace = 'deliverables';

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kDeliverablesZh = {
  'produced.label': '产物',
  'produced.moreOne': '+ 1 个文件',
  'produced.more': '+ {count} 个文件',
  'produced.open': '打开 {name}',
  'produced.showInFolder': '在文件夹中显示',
  // Flutter-surface additions: the Dart deliverables screen's chrome.
  'empty.title': '暂无产物',
  'empty.hint': '本轮创建的文件会显示在这里。',
  // Flutter-surface additions: in-app file preview over workspaceFiles.
  'preview.title': '文件预览',
  'preview.close': '关闭',
  'preview.retry': '重试',
  'preview.truncated': '仅显示前 {lines} 行。',
  'preview.notFound': '文件不存在或已被移动。',
  'preview.tooLarge': '文件超出预览上限。',
  'preview.notText': '该文件不是可预览的文本。',
  'preview.denied': '无权访问该文件。',
  'preview.failed': '无法加载文件。',
};

/// English dictionary (same key set).
const Map<String, String> kDeliverablesEn = {
  'produced.label': 'Produced',
  'produced.moreOne': '+ 1 file',
  'produced.more': '+ {count} files',
  'produced.open': 'Open {name}',
  'produced.showInFolder': 'Show in folder',
  // Flutter-surface additions: the Dart deliverables screen's chrome.
  'empty.title': 'No produced files',
  'empty.hint': 'Files created this turn will appear here.',
  // Flutter-surface additions: in-app file preview over workspaceFiles.
  'preview.title': 'File preview',
  'preview.close': 'Close',
  'preview.retry': 'Retry',
  'preview.truncated': 'Showing the first {lines} lines.',
  'preview.notFound': 'The file does not exist or was moved.',
  'preview.tooLarge': 'The file exceeds the preview limit.',
  'preview.notText': 'This file is not previewable text.',
  'preview.denied': 'Access to this file is denied.',
  'preview.failed': 'Could not load the file.',
};
