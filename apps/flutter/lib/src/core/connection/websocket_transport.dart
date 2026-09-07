import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One live event stream over the host WebSocket carrier.
///
/// Yields **narrow frames** — the `payload` of each `ServerRequest` envelope
/// (`{type:'server-request', rpcId, method, payload}` per
/// `packages/client/connection/src/websocket-downlink.ts:serverRequest`), so
/// consumers match on `frame['type'] == 'session/event'` etc. directly, like
/// the TS client's `readSse`/`openMux` generators.
/// [onOpen] fires once the socket is established, before the first frame —
/// the `stream established` signal the connection controller's readiness
/// handshake waits on.
Stream<Map<String, dynamic>> openEventStream(
  Uri uri, {
  void Function()? onOpen,
}) async* {
  final channel = WebSocketChannel.connect(uri);
  // ready throws on transport failure (handshake rejected, host down).
  await channel.ready;
  onOpen?.call();
  try {
    await for (final message in channel.stream) {
      final String data;
      if (message is String) {
        data = message;
      } else if (message is List<int>) {
        data = utf8.decode(message);
      } else {
        continue;
      }
      if (data.startsWith(':')) continue; // SSE-style comment keepalive
      final trimmed = data.startsWith('data: ') ? data.substring(6) : data;
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) continue;
        // Unwrap the ServerRequest envelope → narrow frame payload.
        // Answerable frames (approval/question requested) answer by echoing
        // the envelope rpcId, so it is stamped onto the yielded frame —
        // business code reads `frame['rpcId']`.
        final Map<String, dynamic> envelope = decoded is Map<String, dynamic>
            ? decoded
            : decoded.cast<String, dynamic>();
        final dynamic payload = envelope['payload'];
        final Map<String, dynamic> frame = payload is Map
            ? (payload is Map<String, dynamic>
                  ? payload
                  : payload.cast<String, dynamic>())
            : envelope;
        final envId = envelope['rpcId'];
        if (envId is String && !frame.containsKey('rpcId'))
          frame['rpcId'] = envId;
        yield frame;
      } catch (_) {
        // Malformed frame must not kill the stream; gap detection covers it.
      }
    }
  } finally {
    await channel.sink.close().catchError((_) {});
  }
}
