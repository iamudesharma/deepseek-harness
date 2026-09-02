/// Browser cookie jar abstraction for native ↔ web.
///
/// Web stores the `dsh-auth-*` cookie in the browser's jar and sends it
/// automatically via `BrowserClient.withCredentials = true` + `fetch`/
// Connection: keep-alive. Native `dart:io` has no automatic jar, so the `io`
/// variant performs the `?token=` → `Set-Cookie` exchange and replays the
/// `Cookie` header on every `/api/*` and `ws://` request.
library;

/// Get the `Cookie` header value for [baseUrl]'s authority, or `null` when none.
///
/// On web this always returns `null` — the browser handles `dsh-auth-*`
/// automatically.
/// On native this lazily performs the `GET /?token=` exchange when
/// `baseUrl` contains `?token=` and caches the `dsh-auth-*` cookie for the
/// authority (`127.0.0.1:3080` etc.).
Future<String?> getBrowserCookie(String baseUrl) async => null;

/// Persist a `Set-Cookie` header value for [authority].
///
/// No-op on web. On native, extracts the `name=value` prefix before `;`
/// and caches it keyed by authority.
void storeBrowserCookie(String authority, String setCookieHeader) {}
