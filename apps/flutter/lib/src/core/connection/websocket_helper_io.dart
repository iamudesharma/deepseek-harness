import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'browser_cookie_io.dart' as browser_cookie;

/// Connect a WebSocket with the browser cookie on native.
///
/// Lazily fetches `dsh-auth-*` via `GET /?token=` when [baseUrl] contains
/// `?token=` and replays `Cookie` via `IOWebSocketChannel`'s `headers`.
/// This mirrors the HTTP path's cookie handling so `BrowserAuth.isAuthenticated`
/// passes for `ws://127.0.0.1:3080/api/remote.mux` etc.
Future<WebSocketChannel> connectWebSocket(Uri uri, String baseUrl) async {
  String? cookie;
  try {
    cookie = await browser_cookie.getBrowserCookie(baseUrl);
  } catch (_) {}
  if (cookie != null) {
    return IOWebSocketChannel.connect(uri, headers: {'Cookie': cookie});
  }
  return IOWebSocketChannel.connect(uri);
}
