/// Web — ensure `dsh-auth-*` cookie is minted for cross-port `5001 → 3080`.
///
/// `BrowserClient.withCredentials = true` (http_client_web.dart) will send
/// `Cookie: dsh-auth-*` automatically **iff** the browser already has it.
/// The cookie is `HttpOnly SameSite=Lax` set by `GET http://127.0.0.1:3080/?token=...`
/// → `303` + `Set-Cookie`. React gets it because it is served from `3080`
/// same-origin. Flutter Web at `5001` is **cross-origin** (different port)
/// and never hits `GET /?token=` on its own, so every `/api/*` is `401`.
///
/// This `getBrowserCookie` is called by `connection_client.dart:_headersWithAuth`
/// before every Typert POST. When `baseUrl` carries `?token=` (start.sh now
/// passes `DSH_HOST_URL=http://127.0.0.1:3080?token=...` via
/// `--dart-define`), we lazily `GET` the token URL with `withCredentials:true`
/// so the browser stores `Set-Cookie` for the `127.0.0.1:3080` authority.
/// Subsequent `POST /api/*` then sends `Cookie` automatically. The returned
/// `String` is unused on web (the browser sends the cookie), but we return a
/// non-null sentinel so callers know the exchange was attempted.
library;

import 'package:http/browser_client.dart';

final Set<String> _fetchedAuthorities = {};

/// Ensure `dsh-auth-*` cookie for [baseUrl]'s authority when `?token=` present.
///
/// Idempotent per authority; first call does `GET http://authority/?token=`
/// with `withCredentials:true` to let the browser store `Set-Cookie`.
/// Always returns `null` on web — the browser's jar is authoritative and
/// `Cookie` is a forbidden header JavaScript cannot set. Callers must still
/// await this before the first Typert POST / WebSocket so the mint races
/// nothing. Only authorities with a successful mint are cached; failures
/// stay uncached so the next call retries (otherwise every `/api/*` would
/// `401` forever after one failed mint).
Future<String?> getBrowserCookie(String baseUrl) async {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) return null;
  final authority = uri.authority;
  if (authority.isEmpty) return null;
  if (_fetchedAuthorities.contains(authority)) return null;
  final token = uri.queryParameters['token'];
  if (token == null || token.isEmpty) return null;
  final tokenUrl = uri.replace(path: '/', queryParameters: {'token': token});
  final client = BrowserClient()..withCredentials = true;
  try {
    // `GET /?token=` → `303` + `Set-Cookie: dsh-auth-...; Path=/; HttpOnly; SameSite=Lax`
    // Browser stores it for `127.0.0.1:3080`; subsequent fetches to that authority
    // include `Cookie` automatically because `http_client_web.dart` also uses
    // `withCredentials:true` and our webserver CORS is `Allow-Credentials:true`.
    // `BrowserClient` follows the `303` to `GET /`, which serves `200` once the
    // cookie lands, so a 2xx/3xx here means the mint succeeded.
    final response = await client.get(tokenUrl);
    if (response.statusCode >= 200 && response.statusCode < 400) {
      _fetchedAuthorities.add(authority);
    }
    // A non-2xx/3xx (e.g. `401` after the launch token rotated under a live
    // client on backend restart) stays uncached so the next call retries the
    // mint instead of 401ing every `/api/*` until a full page reload.
  } catch (_) {
    // Non-fatal — the next Typert POST will still 401 and the controller will
    // retry after the cookie is eventually set. Do not cache failures so the
    // next call retries the mint. Do not block the caller.
  } finally {
    client.close();
  }
  return null;
}

/// Forget the cached mint for [baseUrl]'s authority.
///
/// The browser's jar keeps whatever cookie it holds; this only clears the
/// "mint already attempted" latch so the next call retries `GET /?token=`.
/// Called after a 401/403, which may mean the launch token rotated (backend
/// restart) and the minted cookie no longer authenticates.
void evictBrowserCookieMint(String baseUrl) {
  final authority = Uri.tryParse(baseUrl)?.authority;
  if (authority != null && authority.isNotEmpty) {
    _fetchedAuthorities.remove(authority);
  }
}

/// No-op on web — the browser's jar is authoritative.
void storeBrowserCookie(String authority, String setCookieHeader) {}
