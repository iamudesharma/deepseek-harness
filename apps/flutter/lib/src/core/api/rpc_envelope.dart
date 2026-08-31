/// Four-quadrant RPC message model mirrored from
/// `packages/host/apiproxy/src/api/rpc.ts`.
///
/// Channels (HTTP POST, WebSocket downlink, in-process SSE) are physical
/// carriers; the four logical messages below form the closed discriminated
/// union carried over any of them. The initiator mints the [RpcId]; a response
/// always echoes the matching request's id and never mints a new one.
library;

/// Message correlation id branded exactly like the TS `RpcId` brand.
///
/// Minted by the initiator: `client-request` → client mints;
/// `server-request` → host mints (answerable frames keep a stable id across
/// replay; pure pushes mint one id per push).
extension type const RpcId(String value) {
  /// JSON wire form: plain string.
  String toJson() => value;
}

/// Closed error-code union: the keys of `RpcErrorDetailsMap` in rpc.ts.
///
/// The wire body is validated by `rpcErrorSchema` (a zod discriminated union)
/// before it leaves the host, so an unrecognized [code] cannot arrive from a
/// conforming host; [RpcError.fromJson] throws on one anyway so local decoding
/// fails loud instead of inventing a default branch.
enum RpcErrorCode {
  badRequest('bad-request'),
  cancelled('cancelled'),
  sessionNotFound('session-not-found'),
  modelUnavailable('model-unavailable'),
  sessionConflict('session-conflict'),
  invalidTimeZone('invalid-time-zone'),
  workspaceAttachFailed('workspace-attach-failed'),
  workspaceNotFound('workspace-not-found'),
  workspaceInvalidPath('workspace-invalid-path'),
  workspaceNameConflict('workspace-name-conflict'),
  workspaceMoveInvalid('workspace-move-invalid'),
  directoryUnreadable('directory-unreadable'),
  directoryExists('directory-exists'),
  directoryCreateFailed('directory-create-failed'),
  directoryPickerUnavailable('directory-picker-unavailable'),
  agentPresetReadOnly('agent-preset-read-only'),
  agentPresetLocked('agent-preset-locked'),
  agentPresetConflict('agent-preset-conflict'),
  agentPresetNotFound('agent-preset-not-found'),
  agentPresetInvalid('agent-preset-invalid'),
  agentBusy('agent-busy'),
  attachmentError('attachment-error'),
  queueItemNotFound('queue-item-not-found'),
  steerUnavailable('steer-unavailable'),
  commandError('command-error'),
  unknownCommand('unknown-command'),
  settingsRejected('settings-rejected'),
  settingsConflict('settings-conflict'),
  credentialRejected('credential-rejected'),
  modelDiscoveryFailed('model-discovery-failed'),
  titleInvalid('title-invalid'),
  forkUnavailable('fork-unavailable'),
  subagentParentUnavailable('subagent-parent-unavailable'),
  subagentNotFound('subagent-not-found'),
  subagentCatalogDiagnostic('subagent-catalog-diagnostic'),
  subagentNotResumable('subagent-not-resumable'),
  subagentUnauthorized('subagent-unauthorized'),
  subagentDeliveryUnavailable('subagent-delivery-unavailable'),
  internal('internal');

  const RpcErrorCode(this.wire);

  /// Exact wire literal from `RpcErrorDetailsMap`.
  final String wire;

  /// Parses a wire literal; returns null for codes outside the closed set.
  static RpcErrorCode? tryParse(String wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// Business failure branch: `code` discriminates, `details` is required on the
/// wire (`internal` uses an explicit empty object). Per-code typed details are
/// introduced by each domain workstream; this level carries the decoded map.
class RpcError {
  /// Creates an error from already-decoded parts.
  const RpcError({
    required this.code,
    required this.message,
    required this.details,
  });

  /// Discriminant selecting the details vocabulary.
  final RpcErrorCode code;

  /// Human-readable seam text; shown to the user as-is.
  final String message;

  /// Decoded `details` object keyed per the owning row of `RpcErrorDetailsMap`.
  final Map<String, Object?> details;

  /// Decodes the wire body `{code, message, details}`.
  ///
  /// Throws [ArgumentError] when the shape is malformed or [code] is outside
  /// the closed set (mirrors `rpcErrorSchema` rejecting such bodies upstream).
  factory RpcError.fromJson(Map<String, Object?> json) {
    final codeWire = json['code'];
    final message = json['message'];
    if (codeWire is! String) {
      throw ArgumentError.value(codeWire, 'code', 'must be a string');
    }
    if (message is! String) {
      throw ArgumentError.value(message, 'message', 'must be a string');
    }
    final detailsValue = json['details'];
    if (detailsValue is! Map) {
      throw ArgumentError.value(detailsValue, 'details', 'must be an object');
    }
    final code = RpcErrorCode.tryParse(codeWire);
    if (code == null) {
      throw ArgumentError.value(
        codeWire,
        'code',
        'not part of the closed error-code union',
      );
    }
    return RpcError(
      code: code,
      message: message,
      details: Map<String, Object?>.from(detailsValue),
    );
  }

  /// Wire form.
  Map<String, Object?> toJson() => {
    'code': code.wire,
    'message': message,
    'details': details,
  };
}

/// Business success/failure result: the result slot of any unary response.
/// Methods never throw business errors — they return the failure branch.
sealed class RpcResult<T> {
  const RpcResult();

  /// Pattern-match hook: applies [ok] or [failure] exhaustively.
  R fold<R>({
    required R Function(T value) ok,
    required R Function(RpcError error) failure,
  }) => switch (this) {
    RpcSuccess<T>(:final value) => ok(value),
    RpcFailure<T>(:final error) => failure(error),
  };
}

/// `{ ok: true, value }` branch.
class RpcSuccess<T> extends RpcResult<T> {
  /// Wraps the business value.
  const RpcSuccess(this.value);

  /// The business payload.
  final T value;
}

/// `{ ok: false, error }` branch.
class RpcFailure<T> extends RpcResult<T> {
  /// The business error.
  const RpcFailure(this.error);

  /// The business error.
  final RpcError error;
}

/// Folds a transport exception into the failure branch with the catch-all
/// `internal` code — mirrors `transportError()` in rpc.ts so every carrier
/// consumer folds identically.
RpcResult<T> transportError<T>(Object error) => RpcFailure<T>(
  RpcError(
    code: RpcErrorCode.internal,
    message: error.toString(),
    details: const {},
  ),
);

/// Narrow signature form, request side: rpcId rides beside the business
/// payload, never inside it; the type tag and method are filled by the carrier.
class RpcRequest<P> {
  /// Creates a request.
  const RpcRequest({required this.rpcId, required this.payload});

  /// Correlation id minted by the initiator.
  final RpcId rpcId;

  /// Business payload.
  final P payload;
}

/// Narrow signature form, response side: rpcId echoes the matching request.
class RpcResponse<T> {
  /// Creates a response.
  const RpcResponse({required this.rpcId, required this.result});

  /// Echoed correlation id.
  final RpcId rpcId;

  /// Business result.
  final RpcResult<T> result;
}

// ---- Wire full forms ----

/// Authoritative wire union; narrow via Dart switch exhaustiveness.
sealed class RpcMessage {
  const RpcMessage();

  /// The discriminant literal carried in the wire `type` field.
  String get typeWire;

  /// The correlation id this message carries.
  RpcId get rpcId;
}

/// Call initiated by the client (wire carrier: POST `/api/<method>` body).
class ClientRequest implements RpcMessage {
  /// Creates the wire form.
  const ClientRequest({
    required this.rpcId,
    required this.method,
    required this.payload,
  });

  @override
  String get typeWire => 'client-request';

  @override
  final RpcId rpcId;

  /// RPC method name from the api method map.
  final String method;

  /// Business payload.
  final Object? payload;
}

/// Response to a [ClientRequest] (carrier: that POST's HTTP body); rpcId echoed.
class ServerResponse implements RpcMessage {
  /// Creates the wire form.
  const ServerResponse({required this.rpcId, required this.result});

  @override
  String get typeWire => 'server-response';

  @override
  final RpcId rpcId;

  /// Business result.
  final RpcResult<Object?> result;
}

/// Message initiated by the server (carrier: downstream stream frame).
/// Answerable interactions (approval/question requested) reuse a stable rpcId
/// across replay; pure pushes carry an id identifying that single push.
/// Whether a response is expected is determined statically by method.
class ServerRequest implements RpcMessage {
  /// Creates the wire form.
  const ServerRequest({
    required this.rpcId,
    required this.method,
    required this.payload,
  });

  @override
  String get typeWire => 'server-request';

  @override
  final RpcId rpcId;

  /// RPC method name.
  final String method;

  /// Business payload.
  final Object? payload;
}

/// Response to a [ServerRequest] (carrier: POST `/api/respond`); rpcId echoed,
/// never minted anew.
class ClientResponse implements RpcMessage {
  /// Creates the wire form.
  const ClientResponse({required this.rpcId, required this.result});

  @override
  String get typeWire => 'client-response';

  @override
  final RpcId rpcId;

  /// Business result.
  final RpcResult<Object?> result;
}

/// Decodes one wire message from `{type, ...}`.
///
/// Throws [ArgumentError] on an unknown `type` literal or malformed member:
/// the host validates outbound messages (`*.schema.ts`), so an unrecognized
/// tag means a broken peer rather than a variant this layer may drop.
RpcMessage parseRpcMessage(Map<String, Object?> json) {
  final type = json['type'];
  if (type is! String)
    throw ArgumentError.value(type, 'type', 'must be a string');
  switch (type) {
    case 'client-request':
      return ClientRequest(
        rpcId: _requireRpcId(json),
        method: _requireString(json, 'method'),
        payload: json['payload'],
      );
    case 'server-request':
      return ServerRequest(
        rpcId: _requireRpcId(json),
        method: _requireString(json, 'method'),
        payload: json['payload'],
      );
    case 'server-response':
      return ServerResponse(
        rpcId: _requireRpcId(json),
        result: _requireResult(json),
      );
    case 'client-response':
      return ClientResponse(
        rpcId: _requireRpcId(json),
        result: _requireResult(json),
      );
    default:
      throw ArgumentError.value(
        type,
        'type',
        'unknown RPC message discriminant',
      );
  }
}

RpcId _requireRpcId(Map<String, Object?> json) =>
    RpcId(_requireString(json, 'rpcId'));

RpcResult<Object?> _requireResult(Map<String, Object?> json) {
  final result = json['result'];
  if (result is! Map) {
    throw ArgumentError.value(result, 'result', 'must be an object');
  }
  final error = result['error'];
  if (result['ok'] == true) return RpcSuccess<Object?>(result['value']);
  if (error is! Map) {
    throw ArgumentError.value(
      error,
      'error',
      'must be an object when ok is false',
    );
  }
  return RpcFailure<Object?>(
    RpcError.fromJson(Map<String, Object?>.from(error)),
  );
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String)
    throw ArgumentError.value(value, key, 'must be a string');
  return value;
}

/// Transport-level method failure — mirrors `RemoteMethodException` expected by
/// workspace/directory services (code + details from the failure branch).
class RemoteMethodException implements Exception {
  RemoteMethodException({required this.code, required this.message, required this.details});
  final RpcErrorCode code;
  final String message;
  final Map<String, Object?> details;
  @override
  String toString() => 'RemoteMethodException($code: $message)';
}

/// Carrier receipt for a [ClientResponse] (`rpcReceiptSchema`): the host
/// either accepted the echoed-rpcId response or names why it could not pair
/// it (`not-pending` = no matching server-request; `bad-response` = malformed
/// body).
sealed class RpcReceipt {
  const RpcReceipt();

  /// Decodes one wire receipt.
  static RpcReceipt fromJson(Map<String, Object?> json) {
    if (json['accepted'] == true) return const RpcReceiptAccepted();
    final reason = json['reason'];
    if (reason == 'not-pending' || reason == 'bad-response') {
      return RpcReceiptRejected(reason as String);
    }
    throw ArgumentError.value(reason, 'reason', 'unknown receipt reason');
  }
}

/// `{ accepted: true }`.
class RpcReceiptAccepted extends RpcReceipt {
  const RpcReceiptAccepted();
}

/// `{ accepted: false, reason }`.
class RpcReceiptRejected extends RpcReceipt {
  /// Creates a rejection.
  const RpcReceiptRejected(this.reason);

  /// `'not-pending' | 'bad-response'`.
  final String reason;
}
