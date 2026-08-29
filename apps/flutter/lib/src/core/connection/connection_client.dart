import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../session/session_models.dart';
import '../session/host_session_policy.dart' show sessionCreatePayload;
import '../api/rpc_envelope.dart';
import 'connection_target.dart';
import 'secure_token_store.dart';
import 'websocket_transport.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

export 'connection_controller.dart';

/// Generate a UUID v4 string for `rpcId`.
///
/// The initiator mints, the responder echoes — see
/// `packages/client/AGENTS.md:rpcId is strictly bidirectional` and
/// `docs/cordis-primer.md`. No external `uuid` dependency needed for the
/// simple browser/client use; this uses `Random.secure` when available.
String newRpcId() {
  final Random rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  // Set version 4 and variant bits per RFC 4122.
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  final b = bytes;
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// Thrown when the host rejects a bearer token (401) or scope (403).
///
/// The controller maps 401 → [ConnectionState.needsReauth] (stop reconnect,
/// prompt re-pair) and 403 → `needsReauth` as well (privileged denied).
class RemoteAuthException implements Exception {
  /// HTTP status (401 for missing/expired/revoked/unknown, 403 for scope).
  final int statusCode;

  /// Short reason (never includes the raw token).
  final String message;
  RemoteAuthException(this.statusCode, this.message);
  @override
  String toString() => 'RemoteAuthException($statusCode): $message';
}

/// Typed HTTP client for host RPC.
///
/// Thin wrapper over the Typert RPC gateway exposed by the host's
/// `dsh-host-webserver` / `api-gateway`. Each unary call mints its own
/// `rpcId` (initiator-owned) and echoes it on the response; streaming calls
/// are not wrapped here (they belong in a `ConnectionController`-like pump).
///
/// Transport-agnostic: the same client works for [LocalTarget] (loopback,
/// `isTrustedApiRequest`) and [RemoteTarget] (bearer `Authorization` +
/// `wss://…?ticket=`). Only [ConnectionTarget] + [SecureTokenStore] differ.
///
/// Keep simple: pure Dart, no Cordis imports, invocable independently in
/// tests via `ProviderContainer` overrides.
///
/// Example:
///
/// ```dart
/// final client = ConnectionClient(baseUrl: 'http://localhost:8787');
/// final sessions = await client.getSessions();
/// ```
class ConnectionClient {
  /// Host base URL without trailing slash, e.g. `http://localhost:8787`.
  /// When [target] is non-null, this is derived from `target.baseUri` and
  /// the constructor's [baseUrl] is ignored (kept for backward compat).
  final String baseUrl;

  /// Optional platform-independent endpoint. When `null`, behaves exactly as
  /// before (LocalTarget/http, no bearer, no ticket). When a [RemoteTarget],
  /// every unary POST carries `Authorization: Bearer <token>` and every
  /// `events.mux/host` WebSocket is opened as `wss://…?ticket=<ws-ticket>`.
  final ConnectionTarget? target;

  /// Token store for [RemoteTarget] bearer tokens. `null` for [LocalTarget].
  final SecureTokenStore? tokenStore;

  final http.Client _http;

  /// Active WebSocket channels for event streams, tracked so [abortEventStreams]
  /// can close sockets on mobile background suspend.
  final Set<WebSocketChannel> _activeChannels = {};

  /// Close all active event-stream sockets (mux/host). Used by
  /// [FlutterConnectionController.suspend] to ensure backgrounded generations
  /// do not keep sockets alive.
  void abortEventStreams() {
    for (final ch in _activeChannels.toList()) {
      try {
        ch.sink.close();
      } catch (_) {}
    }
    _activeChannels.clear();
  }

  /// Creates a typed host RPC client.
  ///
  /// For backward compat, [baseUrl] is required. For new code, pass
  /// `target` and `tokenStore`; `baseUrl` is then derived from the target.
  ConnectionClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.target,
    this.tokenStore,
  }) : _http = httpClient ?? http.Client();

  /// Create from a [ConnectionTarget] (preferred for Phase 3).
  factory ConnectionClient.fromTarget(
    ConnectionTarget target, {
    http.Client? httpClient,
    SecureTokenStore? tokenStore,
  }) {
    return ConnectionClient(
      baseUrl: target.baseUri.toString(),
      httpClient: httpClient,
      target: target,
      tokenStore: tokenStore,
    );
  }

  /// Whether this client is remote (bearer).
  bool get isRemote => target is RemoteTarget;

  /// Release the underlying HTTP client.
  void dispose() {
    _http.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$base$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Map<String, String> _headers(String rpcId) => {
    'content-type': 'application/json',
    'x-rpc-id': rpcId,
  };

  /// Bearer token for the current [RemoteTarget], or `null` for [LocalTarget]
  /// / missing token. Never logs the raw value.
  Future<String?> _bearerToken() async {
    final t = target;
    if (t is! RemoteTarget) return null;
    final store = tokenStore;
    if (store == null) return null;
    return store.read(t.deviceId);
  }

  /// Low-level unary POST helper: POST `/api/<method>` with Typert envelope.
  ///
  /// Returns the decoded JSON map (`RpcResponse`). On 401/403 throws
  /// [RemoteAuthException] so the controller can enter `needsReauth` instead
  /// of spinning reconnect.
  Future<Map<String, dynamic>> _postTypert(
    String method,
    Map<String, dynamic> payload, {
    String? rpcId,
  }) async {
    final id = rpcId ?? newRpcId();
    final uri = _uri('/api/$method');
    final envelope = {
      'type': 'client-request',
      'rpcId': id,
      'method': method,
      'payload': payload,
    };
    final headers = _headers(id);
    final bearer = await _bearerToken();
    if (bearer != null) headers['authorization'] = 'Bearer $bearer';
    final resp = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode(envelope),
    );
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw RemoteAuthException(
        resp.statusCode,
        'POST /api/$method rejected: ${resp.statusCode}',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw http.ClientException(
        'POST /api/$method failed: ${resp.statusCode} ${resp.body}',
        uri,
      );
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw FormatException(
      'Expected JSON object from /api/$method, got $decoded',
    );
  }

  /// Backward-compat shim for legacy `/api/sessions/*` callers: delegates to Typert.
  // ignore: unused_element
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    String? rpcId,
  }) async {
    // Map legacy path to method: /api/sessions/list -> session.list etc.
    final method = _legacyPathToMethod(path);
    if (method != null) return _postTypert(method, payload, rpcId: rpcId);
    // Fallback: raw POST (used only by tests with fake server).
    final id = rpcId ?? newRpcId();
    final uri = _uri(path);
    final headers = _headers(id);
    final bearer = await _bearerToken();
    if (bearer != null) headers['authorization'] = 'Bearer $bearer';
    final resp = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode({'rpcId': id, ...payload}),
    );
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw RemoteAuthException(
        resp.statusCode,
        'POST $path rejected: ${resp.statusCode}',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw http.ClientException(
        'POST $path failed: ${resp.statusCode} ${resp.body}',
        uri,
      );
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw FormatException('Expected JSON object from $path, got $decoded');
  }

  String? _legacyPathToMethod(String path) {
    if (path == '/api/sessions/list') return 'session.list';
    if (path == '/api/sessions/history') return 'session.history';
    if (path == '/api/sessions/prompt') return 'session.prompt';
    return null;
  }

  /// List persisted sessions (updatedAt descending).
  ///
  /// Mirrors `session.list` (`SessionsApi.list`). Each call mints a fresh
  /// initiator `rpcId`.
  Future<List<SessionSummary>> getSessions() async {
    final body = await _postTypert('session.list', {});
    // Host returns `RpcResponse { rpcId, result: { ok, value: { items } } }`
    // Unwrap leniently to tolerate raw vs wrapped forms.
    final items = _extractItems(body);
    return items.map(SessionSummary.fromJson).toList();
  }

  /// Read a window of history events for [id].
  ///
  /// Mirrors `session.history` (`SessionsApi.history`). Returns the raw
  /// event window (host already pairs `event`+`view` as `HistoryEntry`).
  Future<List<HistoryEntry>> getSessionEvents(
    SessionId id, {
    int? beforeSeq,
    int? maxMessages,
  }) async {
    final res = await getSessionHistory(
      id,
      beforeSeq: beforeSeq,
      maxMessages: maxMessages,
    );
    return res.entries;
  }

  /// Full history fetch including the tail projections block.
  Future<({List<HistoryEntry> entries, SessionProjectionsBlock? projections})>
  getSessionHistory(SessionId id, {int? beforeSeq, int? maxMessages}) async {
    final payload = <String, dynamic>{
      'sessionId': id.value,
      // ignore: use_null_aware_elements
      if (beforeSeq case final v?) 'beforeSeq': v,
      // ignore: use_null_aware_elements
      if (maxMessages case final v?) 'maxMessages': v,
    };
    final body = await _postTypert('session.history', payload);
    final entries = _extractEvents(body).map(HistoryEntry.fromJson).toList();
    // Tail projections block carries the current title etc. under `projections`.
    SessionProjectionsBlock? block;
    dynamic cur = body;
    if (cur is Map && cur.containsKey('result')) cur = cur['result'];
    if (cur is Map && cur.containsKey('value')) cur = cur['value'];
    if (cur is Map && cur.containsKey('projections')) {
      final proj = cur['projections'];
      if (proj is Map) {
        try {
          block = SessionProjectionsBlock.fromJson(
            proj.cast<String, dynamic>(),
          );
        } catch (_) {}
      }
    }
    return (entries: entries, projections: block);
  }

  /// Send a message to [sessionId].
  ///
  /// Mirrors `session.prompt` (mode `queue` by default). Content is a list of
  /// `PromptContentPart` blocks: zero or more `image` parts (in draft order)
  /// followed by one optional `text` block. Callers needing image parts pass
  /// pre-serialized `images` blocks (`{type:'image', mediaType, data, name?}`)
  /// produced by `ComposerController.serializeDraftImages` — the same wire
  /// shape React's `encodeImage` emits.
  Future<void> sendMessage({
    required SessionId sessionId,
    required String content,
    String mode = 'queue',
    String? clientTimeZone,
    List<Map<String, dynamic>> images = const [],
  }) async {
    final List<Map<String, dynamic>> contentParts = <Map<String, dynamic>>[
      ...images,
      if (content.isNotEmpty) {'type': 'text', 'text': content},
    ];
    await _postTypert('session.prompt', {
      'sessionId': sessionId.value,
      'mode': mode,
      'content': contentParts,
      // ignore: use_null_aware_elements
      if (clientTimeZone case final v?) 'clientTimeZone': v,
    });
  }

  /// Create a new session (Typert `session.create`).
  Future<SessionId> createSession({String? workspaceId, String? cwd}) async {
    final body = await _postTypert(
      'session.create',
      sessionCreatePayload(workspaceId: workspaceId, cwd: cwd),
    );
    // Unwrap `result.value.sessionId`
    dynamic cur = body;
    if (cur is Map && cur.containsKey('result')) cur = cur['result'];
    if (cur is Map && cur.containsKey('value')) cur = cur['value'];
    if (cur is Map && cur['sessionId'] is String)
      return SessionId(cur['sessionId'] as String);
    throw FormatException('session.create: missing sessionId in $body');
  }

  /// `session.cancel { sessionId }` — cancel the in-flight turn; queued
  /// items resume in FIFO order after cancellation settles.
  Future<void> cancelTurn(SessionId sessionId) async {
    await _postTypert('session.cancel', {'sessionId': sessionId.value});
  }

  /// `session.updateQueue { sessionId, itemId, action }` — edit/remove/steer
  /// one pending queued occurrence. Mirrors
  /// `QueueAction` in `packages/host/apiproxy/src/api/sessions.ts`.
  Future<void> updateQueue({
    required SessionId sessionId,
    required MessageId itemId,
    required QueueAction action,
  }) async {
    await _postTypert('session.updateQueue', {
      'sessionId': sessionId.value,
      'itemId': itemId.value,
      'action': action.toJson(),
    });
  }

  /// Read one durable image attachment: `session.attachment {sessionId, attachmentId}`.
  /// Returns the raw bytes decoded from the host's base64 `data` field.
  Future<Uint8List> readAttachment(
    SessionId sessionId,
    String attachmentId,
  ) async {
    final body = await _postTypert('session.attachment', {
      'sessionId': sessionId.value,
      'attachmentId': attachmentId,
    });
    dynamic cur = body;
    if (cur is Map && cur.containsKey('result')) cur = cur['result'];
    if (cur is Map && cur.containsKey('value')) cur = cur['value'];
    if (cur is Map && cur['data'] is String) {
      final String b64 = cur['data'] as String;
      return base64Decode(b64);
    }
    throw FormatException('session.attachment: missing data in $body');
  }

  /// Respond to one answerable server-request (`approval/requested` /
  /// `question/requested`): POST `/api/respond` with the full
  /// `client-response` message echoing the request's [rpcId] — the initiator
  /// mints, the responder echoes. [ok] carries the business result slot
  /// (`value` on success, `error` on rejection). Returns the carrier receipt;
  /// a rejected receipt means the response never paired with a pending
  /// request.
  Future<RpcReceipt> respond({
    required RpcId rpcId,
    required bool ok,
    Object? value,
    Map<String, Object?>? error,
  }) async {
    final message = <String, dynamic>{
      'type': 'client-response',
      'rpcId': rpcId.toJson(),
      'result': ok
          ? {'ok': true, 'value': value}
          : {'ok': false, 'error': error},
    };
    final uri = _uri('/api/respond');
    final headers = _headers(rpcId.value);
    final bearer = await _bearerToken();
    if (bearer != null) headers['authorization'] = 'Bearer $bearer';
    final resp = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode(message),
    );
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw RemoteAuthException(
        resp.statusCode,
        'POST /api/respond rejected: ${resp.statusCode}',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw http.ClientException(
        'POST /api/respond failed: ${resp.statusCode} ${resp.body}',
        uri,
      );
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw FormatException(
        'Expected receipt object from /api/respond, got $decoded',
      );
    }
    return RpcReceipt.fromJson(Map<String, Object?>.from(decoded));
  }

  /// Helper: extract `items` array from various `RpcResponse` shapes.
  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> body) {
    // Try `body.result.value.items`, then `body.value.items`, then `body.items`.
    dynamic cur = body;
    if (cur is Map && cur.containsKey('result')) cur = cur['result'];
    if (cur is Map && cur.containsKey('value')) cur = cur['value'];
    if (cur is Map && cur.containsKey('items')) {
      final items = cur['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    }
    // No items present is treated as empty list (host may return empty `session.list`).
    if (kDebugMode) {
      debugPrint('[ConnectionClient] getSessions: no items in $body');
    }
    return const [];
  }

  /// Helper: extract `events` / `HistoryEntry[]` from various shapes.
  List<Map<String, dynamic>> _extractEvents(Map<String, dynamic> body) {
    dynamic cur = body;
    if (cur is Map && cur.containsKey('result')) cur = cur['result'];
    if (cur is Map && cur.containsKey('value')) cur = cur['value'];
    // Host `history` returns `{ events: HistoryEntry[], hasMore }`
    if (cur is Map && cur.containsKey('events')) {
      final events = cur['events'];
      if (events is List) {
        return events
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    }
    // Raw event array fallback.
    if (body['events'] is List) {
      return (body['events'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  // Settings / credentials / LLM Typert methods — mirrors
  // `packages/host/apiproxy/src/api/*` and React `ModelsSection` wire faces.
  // ---------------------------------------------------------------------------

  /// Generic Typert call: POST `/api/<method>` and unwrap the result value.
  ///
  /// Exposed for service faces (workspace.*, llm.*) that wrap thin slices of
  /// the wire contract without each re-implementing carrier plumbing.
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    final body = await _postTypert(method, payload);
    return _unwrapValue(body, method);
  }

  /// Unwrap `RpcResponse` value or throw on `result.ok == false`.
  ///
  /// Envelope-shaped bodies route through [parseRpcMessage] so RPC result and
  /// error discrimination has one authority ([rpcEnvelope]); bodies without a
  /// `result` key are legacy raw values and keep their historical tolerance.
  Map<String, dynamic> _unwrapValue(Map<String, dynamic> body, String method) {
    dynamic cur = body;
    if (cur is Map && cur.containsKey('result')) {
      final message = parseRpcMessage(Map<String, Object?>.from(body));
      if (message is! ServerResponse) {
        throw FormatException(
          'Expected server-response from $method, got ${message.typeWire}',
        );
      }
      return message.result.fold(
        ok: (value) {
          cur = value;
          if (cur is Map && cur.containsKey('value')) cur = cur['value'];
          if (cur is List) {
            // Host `commands/list` etc. return a top-level array (Typert
            // `RemoteResult<readonly T[]>`); wrap it so the typed
            // `Map<String,dynamic>` face stays uniform while preserving the
            // list for callers that expect it.
            return {'_list': cur};
          }
          if (cur is Map<String, dynamic>) return cur;
          if (cur is Map) return Map<String, dynamic>.from(cur);
          // For void responses (e.g. credentials.set returns {}), tolerate empty.
          if (cur == null) return <String, dynamic>{};
          throw FormatException(
            'Expected object value from $method, got $cur in $body',
          );
        },
        failure: (error) => throw Exception('$method: ${error.message}'),
      );
    }
    if (cur is Map && cur['ok'] == false) {
      final err = cur['error'];
      final msg = err is Map && err['message'] is String
          ? err['message'] as String
          : '$err';
      throw Exception('$method: $msg');
    }
    if (cur is Map && cur.containsKey('value')) cur = cur['value'];
    if (cur is Map<String, dynamic>) return cur;
    if (cur is Map) return cur.cast<String, dynamic>();
    // For void responses (e.g. credentials.set returns {}), tolerate empty.
    if (cur == null) return <String, dynamic>{};
    throw FormatException(
      'Expected object value from $method, got $cur in $body',
    );
  }

  /// `settings.describe` — returns `{ writable, hasDocument, namespaces }`.
  Future<Map<String, dynamic>> settingsDescribe() async {
    final body = await _postTypert('settings.describe', {});
    return _unwrapValue(body, 'settings.describe');
  }

  /// `settings.mutate` — path ops against stored section with optional revision.
  Future<Map<String, dynamic>> settingsMutate({
    required String ns,
    required List<Map<String, dynamic>> ops,
    int? expectedRevision,
  }) async {
    final payload = <String, dynamic>{
      'ns': ns,
      'ops': ops,
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
    };
    final body = await _postTypert('settings.mutate', payload);
    return _unwrapValue(body, 'settings.mutate');
  }

  /// `credentials.describe` — batched ref lookup.
  Future<Map<String, dynamic>> credentialsDescribe(List<String> refs) async {
    final body = await _postTypert('credentials.describe', {'refs': refs});
    return _unwrapValue(body, 'credentials.describe');
  }

  /// `credentials.set` — store one credential value.
  Future<void> credentialsSet({
    required String ref,
    required String value,
  }) async {
    final body = await _postTypert('credentials.set', {
      'ref': ref,
      'value': value,
    });
    _unwrapValue(body, 'credentials.set');
  }

  /// `credentials.unset` — remove one credential.
  Future<void> credentialsUnset({required String ref}) async {
    final body = await _postTypert('credentials.unset', {'ref': ref});
    _unwrapValue(body, 'credentials.unset');
  }

  /// `llm.providers` — configurable provider directory.
  Future<List<Map<String, dynamic>>> llmProviders() async {
    final body = await _postTypert('llm.providers', {});
    final value = _unwrapValue(body, 'llm.providers');
    final providers = value['providers'];
    if (providers is List) {
      return providers
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// `llm.models` — grouped model catalog.
  Future<Map<String, dynamic>> llmModels() async {
    final body = await _postTypert('llm.models', {});
    return _unwrapValue(body, 'llm.models');
  }

  /// `session.models` — per-session model directory (current + groups + failures).
  Future<Map<String, dynamic>> sessionModels({
    required String sessionId,
  }) async {
    final body = await _postTypert('session.models', {'sessionId': sessionId});
    return _unwrapValue(body, 'session.models');
  }

  /// `session.selectModel` — select provider/model/reasoning for next step.
  Future<Map<String, dynamic>> sessionSelectModel({
    required String sessionId,
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'provider': provider,
      'model': model,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    };
    final body = await _postTypert('session.selectModel', payload);
    return _unwrapValue(body, 'session.selectModel');
  }

  /// `llm.discoverModels` — interrogate a provider endpoint.
  Future<List<Map<String, dynamic>>> llmDiscoverModels({
    required String settingsNs,
    String? provider,
    String? baseURL,
    String? api,
    String? apiKey,
  }) async {
    final payload = <String, dynamic>{
      'settingsNs': settingsNs,
      if (provider != null) 'provider': provider,
      if (baseURL != null) 'baseURL': baseURL,
      if (api != null) 'api': api,
      if (apiKey != null) 'apiKey': apiKey,
    };
    final body = await _postTypert('llm.discoverModels', payload);
    final value = _unwrapValue(body, 'llm.discoverModels');
    final models = value['models'];
    if (models is List) {
      return models
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// `pluginInventory.list` — read-only Host Loader inventory.
  ///
  /// Mirrors `PluginInventoryGateway.list` (`pluginInventory.list`). Returns
  /// the raw snapshot map `{ entries: PluginInventoryEntry[] }` with typert
  /// unwrapping. Callers may cast entries via [PluginInventoryEntry.fromJson].
  Future<Map<String, dynamic>> pluginInventoryList() async {
    final body = await _postTypert('pluginInventory.list', {});
    return _unwrapValue(body, 'pluginInventory.list');
  }

  // ---------------------------------------------------------------------------
  // Workspace, Skills, Agent Presets, Host — for remaining screens
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> workspaceList() async {
    final body = await _postTypert('workspace.list', {});
    return _unwrapValue(body, 'workspace.list');
  }

  Future<Map<String, dynamic>> workspaceCreate({required String path}) async {
    final body = await _postTypert('workspace.create', {'path': path});
    return _unwrapValue(body, 'workspace.create');
  }

  /// `workspace.insertBefore { workspaceId, beforeWorkspaceId? }` — durable workspace display order.
  Future<void> workspaceInsertBefore({
    required String workspaceId,
    String? beforeWorkspaceId,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      if (beforeWorkspaceId != null) 'beforeWorkspaceId': beforeWorkspaceId,
    };
    final body = await _postTypert('workspace.insertBefore', payload);
    _unwrapValue(body, 'workspace.insertBefore');
  }

  /// `workspace.insertSessionBefore { workspaceId, sessionId, beforeSessionId? }` — durable per-workspace session order.
  Future<void> workspaceInsertSessionBefore({
    required String workspaceId,
    required String sessionId,
    String? beforeSessionId,
  }) async {
    final payload = <String, dynamic>{
      'workspaceId': workspaceId,
      'sessionId': sessionId,
      if (beforeSessionId != null) 'beforeSessionId': beforeSessionId,
    };
    final body = await _postTypert('workspace.insertSessionBefore', payload);
    _unwrapValue(body, 'workspace.insertSessionBefore');
  }

  /// `workspace.rename { workspaceId, title }`
  Future<Map<String, dynamic>> workspaceRename({
    required String workspaceId,
    required String title,
  }) async {
    final body = await _postTypert('workspace.rename', {
      'workspaceId': workspaceId,
      'title': title,
    });
    return _unwrapValue(body, 'workspace.rename');
  }

  /// `workspace.delete { workspaceId }`
  Future<void> workspaceDelete({required String workspaceId}) async {
    final body = await _postTypert('workspace.delete', {
      'workspaceId': workspaceId,
    });
    _unwrapValue(body, 'workspace.delete');
  }

  /// `session.search { query }` — ranked host search with snippet overlay.
  /// Returns `{ items: [{ sessionId, snippet }], hasMore }` bounded by `SESSION_SEARCH_RESULT_LIMIT` (20).
  Future<Map<String, dynamic>> sessionSearch({
    required String query,
    String? signal,
  }) async {
    // Host `session.search` is Typert unary, abort via signal is caller-side debounce.
    final body = await _postTypert('session.search', {'query': query});
    return _unwrapValue(body, 'session.search');
  }

  Future<Map<String, dynamic>> skillList({required String sessionId}) async {
    final body = await _postTypert('skill.list', {'sessionId': sessionId});
    return _unwrapValue(body, 'skill.list');
  }

  Future<Map<String, dynamic>> agentPresetList() async {
    final body = await _postTypert('agentPreset.list', {});
    return _unwrapValue(body, 'agentPreset.list');
  }

  Future<Map<String, dynamic>> agentPresetSelect({
    required String sessionId,
    required String agentPreset,
  }) async {
    final body = await _postTypert('agentPreset.select', {
      'sessionId': sessionId,
      'agentPreset': agentPreset,
    });
    return _unwrapValue(body, 'agentPreset.select');
  }

  Future<Map<String, dynamic>> hostDescribe() async {
    final body = await _postTypert('host.describe', {});
    return _unwrapValue(body, 'host.describe');
  }

  // ---------------------------------------------------------------------------
  // Remote pairing + ws-ticket — Phase 3
  // ---------------------------------------------------------------------------

  /// `remote.pair {hostId, deviceId, displayName, devicePublicKey, nonce, pin?}`
  /// — the only unauthenticated remote endpoint (pairing ceremony).
  Future<Map<String, dynamic>> remotePair({
    required String hostId,
    required String deviceId,
    required String displayName,
    required String devicePublicKey,
    required String nonce,
    String? pin,
  }) async {
    final body = await _postTypert('remote.pair', {
      'hostId': hostId,
      'deviceId': deviceId,
      'displayName': displayName,
      'devicePublicKey': devicePublicKey,
      'nonce': nonce,
      if (pin != null) 'pin': pin,
    });
    return _unwrapValue(body, 'remote.pair');
  }

  /// `remote.ws-ticket` — bearer `full` required, returns ticket string.
  Future<String> fetchWsTicket() async {
    final body = await _postTypert('remote.ws-ticket', {});
    final value = _unwrapValue(body, 'remote.ws-ticket');
    final ticket = value['ticket'];
    if (ticket is! String)
      throw FormatException('remote.ws-ticket: missing ticket');
    return ticket;
  }

  /// `remote.refresh` — bearer `full` required, returns new token.
  Future<String> remoteRefresh() async {
    final body = await _postTypert('remote.refresh', {});
    final value = _unwrapValue(body, 'remote.refresh');
    final token = value['deviceToken'] as String? ?? value['token'] as String?;
    if (token is! String || token.isEmpty)
      throw FormatException('remote.refresh: missing deviceToken');
    return token;
  }

  // ---------------------------------------------------------------------------
  // Event streams — mirrors `IApiClient.events.mux/host` in
  // `packages/host/apiproxy/src/fetch/client.ts:AbstractApiClient`.
  //
  // Transport is WebSocket (`ws://`/`wss://` derived from [baseUrl]); the host
  // answers plain GET with `426 Upgrade Required, upgrade: websocket`, so SSE
  // is not a viable carrier here. Each stream is lazy (no socket until
  // subscription) and calls `onOpen` once the upgrade completes before the
  // first frame — the `stream established` signal `FlutterConnectionController`
  // uses for the `host.describe + both streams` handshake. Frames are raw
  // `ServerRequest` envelopes (`{type, rpcId, method, payload}`), JSON-decoded;
  // malformed frames are skipped, not fatal.
  //
  // Rollback: `--dart-define=DSH_TRANSPORT=sse` restores the previous
  // streaming-fetch reader (kept below) for hosts serving SSE.
  // ---------------------------------------------------------------------------

  /// All-session mux stream (`/api/events.mux`).
  ///
  /// Emits a `session/subscribed` baseline per attached session, then replays
  /// pending `approval/requested` / `question/requested` and streams
  /// `session/event`, `session/queue`, `session/jobs`, etc.
  Stream<Map<String, dynamic>> eventsMux({void Function()? onOpen}) =>
      _openEvents('/api/events.mux', onOpen: onOpen);

  /// Host-level stream (`/api/events.host`).
  ///
  /// Emits `host/session-added`, `host/session-status`, `host/workspace-*`,
  /// etc.
  Stream<Map<String, dynamic>> eventsHost({void Function()? onOpen}) =>
      _openEvents('/api/events.host', onOpen: onOpen);

  static const bool _useSse =
      const String.fromEnvironment('DSH_TRANSPORT') == 'sse';

  Stream<Map<String, dynamic>> _openEvents(
    String path, {
    void Function()? onOpen,
  }) async* {
    if (baseUrl.isEmpty) {
      return;
    }
    if (isRemote) {
      // Remote: fetch a single-use ws ticket (bearer) then open wss://…?ticket=
      // Never log the ticket value.
      final String ticket;
      try {
        ticket = await fetchWsTicket();
      } catch (e) {
        // Propagate as stream error so the controller can map 401→needsReauth
        throw e;
      }
      final uri = _wsUri(path, ticket: ticket);
      yield* _trackedEventStream(uri, onOpen: onOpen);
      return;
    }
    if (_useSse) {
      yield* _readSse(path, onOpen: onOpen);
    } else {
      yield* _trackedEventStream(_wsUri(path), onOpen: onOpen);
    }
  }

  Stream<Map<String, dynamic>> _trackedEventStream(
    Uri uri, {
    void Function()? onOpen,
  }) async* {
    final channel = WebSocketChannel.connect(uri);
    _activeChannels.add(channel);
    try {
      await channel.ready;
      onOpen?.call();
      await for (final message in channel.stream) {
        final String data;
        if (message is String) {
          data = message;
        } else if (message is List<int>) {
          data = utf8.decode(message);
        } else {
          continue;
        }
        if (data.startsWith(':')) continue;
        final trimmed = data.startsWith('data: ') ? data.substring(6) : data;
        if (trimmed.isEmpty) continue;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
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
        } catch (_) {}
      }
    } finally {
      _activeChannels.remove(channel);
      try {
        await channel.sink.close();
      } catch (_) {}
    }
  }

  Uri _wsUri(String path, {String? ticket}) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final source = Uri.parse(base);
    final scheme = source.scheme == 'https' ? 'wss' : 'ws';
    var uri = source.replace(scheme: scheme, path: path);
    if (ticket != null) {
      uri = uri.replace(
        queryParameters: {...uri.queryParameters, 'ticket': ticket},
      );
    }
    return uri;
  }

  Stream<Map<String, dynamic>> _readWebSocket(
    String path, {
    void Function()? onOpen,
  }) {
    return openEventStream(_wsUri(path), onOpen: onOpen);
  }

  Stream<Map<String, dynamic>> _readSse(
    String ssePath, {
    void Function()? onOpen,
  }) async* {
    final uri = _uri(ssePath);
    final req = http.Request('GET', uri);
    req.headers['accept'] = 'text/event-stream';
    req.headers['cache-control'] = 'no-cache';
    final streamed = await _http.send(req);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw http.ClientException(
        'SSE $ssePath failed: ${streamed.statusCode}',
        uri,
      );
    }
    onOpen?.call();
    String buffer = '';
    await for (final chunk in streamed.stream.transform(const Utf8Decoder())) {
      buffer += chunk;
      int boundary;
      while ((boundary = buffer.indexOf('\n\n')) != -1) {
        final raw = buffer.substring(0, boundary);
        buffer = buffer.substring(boundary + 2);
        final data = raw
            .split('\n')
            .where((String l) => l.startsWith('data: '))
            .map((String l) => l.substring(6))
            .join();
        if (data.isEmpty) continue;
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map) continue;
          // Unwrap the ServerRequest envelope → narrow frame payload
          // (same normalization as the WebSocket transport). Answerable
          // frames (approval/question requested) answer by echoing the
          // envelope rpcId, so it is stamped onto the yielded frame —
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
          // Malformed frame must not kill the stream — gap detection covers it.
          if (kDebugMode)
            debugPrint(
              '[ConnectionClient] dropping malformed SSE frame on $ssePath',
            );
        }
      }
    }
  }
}
