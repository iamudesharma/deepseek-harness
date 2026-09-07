/// Web stub — the browser's jar handles `dsh-auth-*` automatically via
/// `BrowserClient.withCredentials = true` and `fetch(..., credentials: 'include')`.
///
/// Native `getBrowserCookie` is never called on web; this file exists so the
/// conditional import in `connection_client.dart` has a web variant.
library;

/// On web the browser sends `Cookie: dsh-auth-*` automatically.
Future<String?> getBrowserCookie(String baseUrl) async => null;

/// No-op on web.
void storeBrowserCookie(String authority, String setCookieHeader) {}
