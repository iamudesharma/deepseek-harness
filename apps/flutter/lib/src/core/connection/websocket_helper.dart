import 'package:web_socket_channel/web_socket_channel.dart';

/// Connect a WebSocket channel for [uri], including the browser `dsh-auth-*`
/// cookie on native when [baseUrl] carries `?token=`.
///
/// On web the browser's `WebSocket` automatically includes the cookie and
/// `headers` are ignored. On native the `io` variant fetches the cookie via
/// `browser_cookie` and passes `Cookie: ...` to `IOWebSocketChannel`.
Future<WebSocketChannel> connectWebSocket(Uri uri, String baseUrl) async {
  return WebSocketChannel.connect(uri);
}
