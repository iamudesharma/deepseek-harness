/// Flutter port of `RemoteStreamMuxClient` + `$events` generation source
/// (`packages/api/gateway/src/client/stream-client.ts` + `remote-events.ts`).
///
/// Single physical `WSS /api/remote.mux` multiplex carrying all Typert logical
/// streams (`$events`, `session/follow`, `session/control`, `workspace/follow`)
/// as JSON text frames `{type:'open'|'cancel', streamId, endpoint, payload}`
/// ↑ and `{type:'item'|'error'|'end', streamId, ...}` ↓.
///
/// Browser `WebSocket.ping` heartbeat is handled by the platform; Flutter
/// `WebSocketChannel` does not expose it, but the host's 30s ping keeps the
/// socket alive (host `stream-server.ts:70`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'connection_target.dart';
import 'secure_token_store.dart';

/// Failure from the host's `error` frame (business/gateway logical failure).
class RemoteStreamError implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic> details;
  RemoteStreamError(this.code, this.message, this.details);
  @override
  String toString() => 'RemoteStreamError($code): $message';
}

/// Carrier failure (physical WS loss, invalid frame, closed before open).
class RemoteStreamCarrierError implements Exception {
  final String message;
  final Object? cause;
  RemoteStreamCarrierError(this.message, {this.cause});
  @override
  String toString() => 'RemoteStreamCarrierError: $message';
}

/// Downlink frame for `$events` logical stream.
sealed class RemoteEventDownlinkFrame {
  const RemoteEventDownlinkFrame();
}

class RemoteEventReadyFrame extends RemoteEventDownlinkFrame {
  final String clientId;
  final Map<String, dynamic> host;
  const RemoteEventReadyFrame(this.clientId, this.host);
}

class RemoteEventEmitFrame extends RemoteEventDownlinkFrame {
  final String event;
  final List<dynamic> args;
  const RemoteEventEmitFrame(this.event, this.args);
}

class RemoteEventWaterfallFrame extends RemoteEventDownlinkFrame {
  final String event;
  final String eventId;
  final String agentId;
  final Map<String, dynamic> request;
  const RemoteEventWaterfallFrame(this.event, this.eventId, this.agentId, this.request);
}

class RemoteEventCancelFrame extends RemoteEventDownlinkFrame {
  final String eventId;
  const RemoteEventCancelFrame(this.eventId);
}

String _newStreamId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  final b = bytes;
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// Single physical multiplex over `WSS /api/remote.mux`.
///
/// Mirrors `RemoteStreamMuxClient` (`stream-client.ts:54-294`): maintains one
/// `WebSocketChannel`, multiplexes `Map<streamId, StreamController>`, handles
/// `open`/`cancel` upstream and `item`/`error`/`end` downlink, with exponential
/// backoff reconnect (500→10s) and `waitForSocket` gating.
class RemoteMuxClient {
  RemoteMuxClient({
    required this.baseUrl,
    this.target,
    this.tokenStore,
    required this.httpFetch, // for $events/result POST via ConnectionClient
  });

  final String baseUrl;
  final ConnectionTarget? target;
  final SecureTokenStore? tokenStore;
  final Future<Map<String, dynamic>> Function(String method, Map<String, dynamic> payload) httpFetch;

  WebSocketChannel? _channel;
  final Map<String, StreamController<Map<String, dynamic>>> _streams = {};
  final Set<Completer<WebSocketChannel>> _waiters = {};
  bool _disposed = false;
  bool _running = false;
  Future<void>? _keepAlive;
  final Random _rng = Random();

  bool get _isRemote => target is RemoteTarget;

  Uri _muxUri({String? ticket}) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final source = Uri.parse(base);
    final scheme = source.scheme == 'https' ? 'wss' : 'ws';
    var uri = source.replace(scheme: scheme, path: '/api/remote.mux');
    if (ticket != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, 'ticket': ticket});
    }
    return uri;
  }

  Future<String?> _bearerToken() async {
    final t = target;
    if (t is! RemoteTarget) return null;
    final store = tokenStore;
    if (store == null) return null;
    return store.read(t.deviceId);
  }

  Future<String> _fetchWsTicket() async {
    // Use httpFetch to call remote/ws-ticket via ConnectionClient
    final value = await httpFetch('remote/ws-ticket', {});
    final ticket = value['ticket'];
    if (ticket is! String) throw FormatException('remote/ws-ticket: missing ticket');
    return ticket;
  }

  void start() {
    if (_running || _disposed) return;
    _running = true;
    _keepAlive = _maintain(null);
  }

  Future<void> close() async {
    _disposed = true;
    _running = false;
    for (final c in _waiters) {
      if (!c.isCompleted) c.completeError(RemoteStreamCarrierError('disposed'));
    }
    _waiters.clear();
    for (final ctrl in _streams.values) {
      await ctrl.close();
    }
    _streams.clear();
    try {
      await _channel?.sink.close(1000, 'disposed');
    } catch (_) {}
    _channel = null;
    await _keepAlive;
  }

  Future<void> _maintain(Object? previousFailure) async {
    if (!_running || _disposed) return;
    var attempt = previousFailure == null ? 1 : 2;
    while (_running && !_disposed) {
      final ac = Completer<void>();
      try {
        await _reconnect(attempt);
        return;
      } catch (e) {
        if (!_running || _disposed) return;
        attempt++;
        final delay = _backoffDelay(attempt);
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
  }

  int _backoffDelay(int attempt) {
    const base = 500;
    const max = 10000;
    final cap = min(max, base * (1 << (attempt - 1)));
    return cap ~/ 2 + _rng.nextInt(cap ~/ 2 + 1);
  }

  Future<void> _reconnect(int attempt) async {
    final uri;
    if (_isRemote) {
      final ticket = await _fetchWsTicket();
      uri = _muxUri(ticket: ticket);
    } else {
      uri = _muxUri();
    }
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    if (_disposed || !_running) {
      await channel.sink.close();
      throw RemoteStreamCarrierError('disposed before open');
    }
    _channel = channel;
    for (final waiter in _waiters.toList()) {
      if (!waiter.isCompleted) waiter.complete(channel);
    }
    _waiters.clear();
    // Listen for messages
    channel.stream.listen(
      (data) => _onMessage(data),
      onError: (e) => _onLost(channel, RemoteStreamCarrierError('socket error', cause: e)),
      onDone: () => _onLost(channel, RemoteStreamCarrierError('socket closed')),
    );
  }

  void _onLost(WebSocketChannel channel, RemoteStreamCarrierError error) {
    if (_channel != channel) return;
    _channel = null;
    for (final ctrl in _streams.values) {
      ctrl.addError(error);
    }
    _streams.clear();
    if (_running && !_disposed) {
      _keepAlive = _maintain(error);
    }
  }

  void _onMessage(dynamic data) {
    final String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data);
    } else {
      return;
    }
    if (text.isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw FormatException('invalid frame');
      final map = decoded.cast<String, dynamic>();
      final type = map['type'] as String?;
      final streamId = map['streamId'] as String?;
      if (type == null || streamId == null) throw FormatException('missing type/streamId');
      final ctrl = _streams[streamId];
      if (ctrl == null) return;
      if (type == 'item') {
        final value = map['value'];
        ctrl.add(value is Map ? value.cast<String, dynamic>() : {'value': value});
      } else if (type == 'error') {
        final err = map['error'] as Map?;
        final code = err?['code'] as String? ?? 'internal';
        final message = err?['message'] as String? ?? 'stream error';
        final details = err?['details'] is Map ? (err!['details'] as Map).cast<String, dynamic>() : <String, dynamic>{};
        ctrl.addError(RemoteStreamError(code, message, details));
      } else if (type == 'end') {
        ctrl.close();
        _streams.remove(streamId);
      }
    } catch (e) {
      // Invalid frame is carrier failure
      for (final ctrl in _streams.values) {
        ctrl.addError(RemoteStreamCarrierError('invalid frame', cause: e));
      }
      _streams.clear();
      final ch = _channel;
      if (ch != null) {
        _onLost(ch, RemoteStreamCarrierError('invalid frame', cause: e));
        try { ch.sink.close(4002); } catch (_) {}
      }
    }
  }

  Future<WebSocketChannel> _waitForSocket() async {
    final ch = _channel;
    if (ch != null) return ch;
    final completer = Completer<WebSocketChannel>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Open a logical stream over the multiplex.
  ///
  /// `endpoint` is `<namespace>/<method>` or `$events`, `payload` is `{args:{...}}`.
  Stream<Map<String, dynamic>> open(String endpoint, Map<String, dynamic> payload) async* {
    final streamId = _newStreamId();
    final ctrl = StreamController<Map<String, dynamic>>.broadcast();
    _streams[streamId] = ctrl;
    try {
      final channel = await _waitForSocket();
      final openMsg = jsonEncode({
        'type': 'open',
        'streamId': streamId,
        'endpoint': endpoint,
        'payload': payload,
      });
      channel.sink.add(openMsg);
      await for (final value in ctrl.stream) {
        yield value;
      }
    } finally {
      _streams.remove(streamId);
      await ctrl.close();
      final ch = _channel;
      if (ch != null) {
        try {
          ch.sink.add(jsonEncode({'type': 'cancel', 'streamId': streamId}));
        } catch (_) {}
      }
    }
  }

  /// Open `$events` and handle `ready` handshake.
  ///
  /// Returns `clientId` and `host` from ready, then yields downlink frames.
  Stream<RemoteEventDownlinkFrame> openEvents() async* {
    await for (final raw in open(r'$events', {'args': {}})) {
      final type = raw['type'] as String?;
      if (type == 'ready') {
        final clientId = raw['clientId'] as String?;
        final host = raw['host'] as Map?;
        if (clientId is! String || host is! Map) throw FormatException('invalid ready frame');
        yield RemoteEventReadyFrame(clientId, host.cast<String, dynamic>());
      } else if (type == 'emit') {
        final event = raw['event'] as String?;
        final args = raw['args'] as List?;
        if (event is String && args is List) yield RemoteEventEmitFrame(event, args);
      } else if (type == 'waterfall') {
        final event = raw['event'] as String?;
        final eventId = raw['eventId'] as String?;
        final agentId = raw['agentId'] as String?;
        final request = raw['request'] as Map?;
        if (event is String && eventId is String && agentId is String && request is Map) {
          yield RemoteEventWaterfallFrame(event, eventId, agentId, request.cast<String, dynamic>());
        }
      } else if (type == 'cancel') {
        final eventId = raw['eventId'] as String?;
        if (eventId is String) yield RemoteEventCancelFrame(eventId);
      }
    }
  }

  /// Send `$events/result` via HTTP unary (Typert).
  Future<void> sendResult(String clientId, String eventId, Map<String, dynamic> outcome) async {
    await httpFetch(r'$events/result', {
      'clientId': clientId,
      'eventId': eventId,
      'outcome': outcome,
    });
  }

  /// Open `session/follow` over the same mux.
  ///
  /// Payload is `{args:{request:{address,maxMessages?}}}` matching the
  /// Typert `session/follow` contract (`SessionFollowRequest`). The `request`
  /// wrapper is required — the `1<<30` probe removal exposed that a missing
  /// wrapper yielded no snapshot and an empty conversation with no HTTP
  /// fallback (initial history is `session/follow`, not `session/page`).
  Stream<Map<String, dynamic>> openSessionFollow(String sessionId, {int? maxMessages}) {
    return open('session/follow', {
      'args': {
        'request': {
          'address': {'kind': 'session', 'sessionId': sessionId},
          if (maxMessages != null) 'maxMessages': maxMessages,
        },
      },
    });
  }

  /// Open `session/control` baseline + increments.
  Stream<Map<String, dynamic>> openSessionControl() {
    return open('session/control', {'args': {}});
  }

  /// Open `workspace/follow` baseline + increments.
  Stream<Map<String, dynamic>> openWorkspaceFollow() {
    return open('workspace/follow', {'args': {}});
  }
}
