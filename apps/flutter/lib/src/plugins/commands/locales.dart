/// `session-log-download` namespace dictionaries — port of
/// `packages/session-query/session-log-export/src/client/locales.ts`
/// (`NS = 'session-log-download'`). Only the header-action copy ships here;
/// the download dialog stays host-side (React `SessionLogDownloadDialog`).
library;

/// Locale namespace owned by the session-log export action.
const String kSessionLogDownloadNamespace = 'session-log-download';

/// Simplified Chinese copy — keys mirror React `zh`.
const Map<String, String> kSessionLogDownloadZh = {
  'header.action': 'Session 日志',
};

/// English copy — keys mirror React `en`.
const Map<String, String> kSessionLogDownloadEn = {
  'header.action': 'Session log',
};
