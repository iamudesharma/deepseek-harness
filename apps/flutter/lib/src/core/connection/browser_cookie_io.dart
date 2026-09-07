import 'package:http/http.dart' as http;

/// In-memory jar for the browser cookie on native.
///
/// The host sets `dsh-auth-*` (`v1....; Max-Age=2592000; Path=/; HttpOnly;
/// `SameSite=Lax`) via `GET /?token=<launchToken>` → `303` + `Set-Cookie`.
/// `dart:io` has no automatic cookie jar, so we capture that first
/// `Set-Cookie` and replay `Cookie: <name>=<value>` on every subsequent
/// HTTP and WebSocket request to the same authority.

final Map<String, String> _jar = {};
final Map<String, String> _tokenForAuthority = {};
final Map<String, Future<String?>> _pending = {};

/// Extract the `name=value` prefix of a `Set-Cookie` header.
String _cookieNameValue(String setCookieHeader) {
  final at = setCookieHeader.indexOf(';');
  return at == -1 ? setCookieHeader.trim() : setCookieHeader.substring(0, at).trim();
}

/// Get the `Cookie` header for [baseUrl]'s authority, fetching it via the
/// `?token=` exchange when needed.
///
/// Lazily performs `GET http://authority/?token=...` with
/// `followRedirects = false` to capture the `303` `Set-Cookie`, caches it
/// under `authority` (`127.0.0.1:3080`), and returns `name=value`.
Future<String?> getBrowserCookie(String baseUrl) async {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) return null;
  final authority = uri.authority;
  if (authority.isEmpty) return null;
  final cached = _jar[authority];
  if (cached != null) return cached;
  if (_pending.containsKey(authority)) return _pending[authority];

  // Remember token for this authority when seen, so later ws:// calls without
  // `?token=` can still mint the cookie.
  final tokenFromUrl = uri.queryParameters['token'];
  if (tokenFromUrl != null && tokenFromUrl.isNotEmpty) {
    _tokenForAuthority[authority] = tokenFromUrl;
  }
  final token = _tokenForAuthority[authority] ?? tokenFromUrl;
  if (token == null || token.isEmpty) return null;

  final pending = _fetchAndCache(authority, token, uri);
  _pending[authority] = pending;
  try {
    return await pending;
  } finally {
    _pending.remove(authority);
  }
}

Future<String?> _fetchAndCache(String authority, String token, Uri originalUri) async {
  final effectiveTokenUrl = originalUri.replace(scheme: 'http', path: '/', queryParameters: {'token': token});
  final client = http.Client();
  try {
    final req = http.Request('GET', effectiveTokenUrl);
    req.followRedirects = false;
    final streamed = await client.send(req);
    final setCookie = streamed.headers['set-cookie'];
    if (setCookie != null && setCookie.contains('dsh-auth-')) {
      final cookie = _cookieNameValue(setCookie);
      _jar[authority] = cookie;
      return cookie;
    }
    for (final entry in streamed.headers.entries) {
      if (entry.key.toLowerCase() == 'set-cookie' && entry.value.contains('dsh-auth-')) {
        final cookie = _cookieNameValue(entry.value);
        _jar[authority] = cookie;
        return cookie;
      }
    }
  } catch (_) {
  } finally {
    client.close();
  }
  return null;
}

/// Persist a `Set-Cookie` header for [authority].
void storeBrowserCookie(String authority, String setCookieHeader) {
  if (!setCookieHeader.contains('dsh-auth-')) return;
  _jar[authority] = _cookieNameValue(setCookieHeader);
}
