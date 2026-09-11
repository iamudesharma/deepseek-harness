/// `open-in-app` namespace dictionaries — key-identical port of the React
/// package's `locales.ts` (zh is the source of truth; en mirrors every key).
/// Product names ride verbatim in both dictionaries.
library;

/// Dictionary namespace owned by this plugin.
const String kOpenInAppNamespace = 'open-in-app';

/// Application product names shared verbatim by both dictionaries.
const Map<String, String> kOpenInAppProductNames = {
  'app.cursor': 'Cursor',
  'app.vscode': 'VS Code',
  'app.vscodeinsiders': 'VS Code Insiders',
  'app.windsurf': 'Windsurf',
  'app.zed': 'Zed',
  'app.sublimetext': 'Sublime Text',
  'app.xcode': 'Xcode',
  'app.androidstudio': 'Android Studio',
  'app.intellij': 'IntelliJ IDEA',
  'app.pycharm': 'PyCharm',
  'app.webstorm': 'WebStorm',
  'app.phpstorm': 'PhpStorm',
  'app.goland': 'GoLand',
  'app.rider': 'Rider',
  'app.rustrover': 'RustRover',
  'app.fork': 'Fork',
  'app.sourcetree': 'Sourcetree',
  'app.github': 'GitHub Desktop',
  'app.tower': 'Tower',
  'app.gitkraken': 'GitKraken',
  'app.smartgit': 'SmartGit',
  'app.sublimemerge': 'Sublime Merge',
  'app.ghostty': 'Ghostty',
  'app.warp': 'Warp',
  'app.iterm': 'iTerm2',
  'app.kitty': 'kitty',
  'app.windowsterminal': 'Windows Terminal',
  'app.gitbash': 'Git Bash',
  'app.gnometerminal': 'GNOME Terminal',
  'app.konsole': 'Konsole',
};

/// Simplified Chinese dictionary (the key-set source of truth).
const Map<String, String> kOpenInAppZh = {
  'open.title': '在 {app} 中打开工作目录',
  'open.tooltip': '在本地打开',
  'open.error': '打开失败',
  'menu.toggle': '选择打开方式',
  'menu.aria': '打开方式',
  ...kOpenInAppProductNames,
  'app.finder': '访达',
  'app.explorer': '文件资源管理器',
  'app.filemanager': '文件管理器',
  'app.terminal': '终端',
};

/// English dictionary, key-identical to the Chinese source of truth.
const Map<String, String> kOpenInAppEn = {
  'open.title': 'Open workspace in {app}',
  'open.tooltip': 'Open locally',
  'open.error': 'Failed to open',
  'menu.toggle': 'Choose an app to open in',
  'menu.aria': 'Open in',
  ...kOpenInAppProductNames,
  'app.finder': 'Finder',
  'app.explorer': 'File Explorer',
  'app.filemanager': 'Files',
  'app.terminal': 'Terminal',
};
