import 'package:web_socket_channel/web_socket_channel.dart';

import 'browser_cookie.dart'
    if (dart.library.io) 'browser_cookie_io.dart'
    if (dart.library.js_interop) 'browser_cookie_web.dart'
    as browser_cookie;

/// Web stub — `HtmlWebSocketChannel` uses the browser's `WebSocket` which
/// automatically includes `Cookie: dsh-auth-*` for same-site `127.0.0.1:3080`.
/// Await the `GET /?token=` → `Set-Cookie` mint first so the first upgrade
/// does not race it (otherwise `requestRejection` answers `401` and the
/// controller spins `GEN timeout`).
Future<WebSocketChannel> connectWebSocket(Uri uri, String baseUrl) async {
  try {
    await browser_cookie.getBrowserCookie(baseUrl);
  } catch (_) {}
  return WebSocketChannel.connect(uri);
}
