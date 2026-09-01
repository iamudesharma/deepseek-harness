import 'package:web_socket_channel/web_socket_channel.dart';

/// Web stub — `HtmlWebSocketChannel` uses the browser's `WebSocket` which
/// automatically includes `Cookie: dsh-auth-*` for same-site `127.0.0.1:3080`.
Future<WebSocketChannel> connectWebSocket(Uri uri, String baseUrl) async {
  return WebSocketChannel.connect(uri);
}
