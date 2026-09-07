/// Web — ensure `dsh-auth-*` cookie is minted for cross-port `5001 → 3080`.
///
/// `BrowserClient.withCredentials = true` (http_client_web.dart) will send
/// `Cookie: dsh-auth-*` automatically **iff** the browser already has it.
/// The cookie is `HttpOnly SameSite=Strict` set by `GET http://127.0.0.1:3080/?token=...`
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
Future<String?> getBrowserCookie(String baseUrl) async {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) return null;
  final authority = uri.authority;
  if (authority.isEmpty) return null;
  if (_fetchedAuthorities.contains(authority)) return 'dsh-auth';
  final token = uri.queryParameters['token'];
  if (token == null || token.isEmpty) return null;
  _fetchedAuthorities.add(authority);
  final tokenUrl = uri.replace(path: '/', queryParameters: {'token': token});
  try {
    final client = BrowserClient()..withCredentials = true;
    // `GET /?token=` → `303` + `Set-Cookie: dsh-auth-...; Path=/; HttpOnly; SameSite=Lax`
    // Browser stores it for `127.0.0.1:3080`; subsequent fetches to that authority
    // include `Cookie` automatically because `http_client_web.dart` also uses
    // `withCredentials:true` and our webserver CORS is `Allow-Credentials:true`.
    await client.get(tokenUrl);
  } catch (_) {
    // Non-fatal — the next Typert POST will still 401 and the controller will
    // retry after the cookie is eventually set. Do not block the caller.
  }
  return 'dsh-auth';
}

/// No-op on web — the browser's jar is authoritative.
void storeBrowserCookie(String authority, String setCookieHeader) {}
