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
};
