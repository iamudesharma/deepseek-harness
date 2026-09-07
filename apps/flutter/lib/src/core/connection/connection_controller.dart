/// Connection lifecycle controller: generation loop, strict handshake,
/// backoff, and Riverpod wiring. Mirrors `ConnectionController` in
/// `packages/client/connection/src/client/connection.ts`; owns the
/// reconnect-generation semantics tracked by [runtime.reconnect-generations]
/// in migration/migration-tracker.json.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_client.dart';
import 'connection_target.dart';
import 'connection_target_provider.dart';
import 'remote_mux_client.dart';
import 'secure_token_store.dart';

/// Coarse connection state for UI, mirroring `ConnectionState` in
/// `packages/client/connection/src/client/connection.ts` plus Flutter-native
/// disconnected/idle states.
///
/// Web has only `'connected' | 'reconnecting'`; Flutter adds `disconnected`
/// and `connecting` so a fresh cold start and a torn-down client have a
/// distinct value before the first handshake. Phase 3 adds `needsReauth` for
/// bearer expiry/revocation/host-mismatch (stop backoff, prompt re-pair).
enum ConnectionState {
  /// No connection attempt has started.
  idle,

  /// Handshake in progress (`host.describe` + stream open).
  connecting,

  /// Connected after handshake (both streams open + describe succeeded).
  connected,

  /// Connection lost; backoff/retry loop is active.
  reconnecting,

  /// Explicitly disconnected (client stopped or never started).
  disconnected,

  /// Bearer token expired/revoked/unknown, hostId mismatched, or 401/403
  /// from the host — stop reconnect, prompt re-pair.
  needsReauth,
}

/// Backoff tuning for [FlutterConnectionController], mirroring
/// `ConnectionConfig` in `packages/client/connection/src/client/connection.ts`.
///
/// All fields have production defaults; tests override via constructor.
class ConnectionConfig {
  /// First-retry backoff cap in ms (jittered: cap/2..cap).
  final int backoffBaseMs;

  /// Exponential factor per consecutive failure.
  final int backoffFactor;

  /// Upper bound cap in ms.
  final int backoffMaxMs;

  /// Cap on waiting for both streams' onOpen before proceeding as connected.
  final int streamOpenTimeoutMs;
  const ConnectionConfig({
    this.backoffBaseMs = 500,
    this.backoffFactor = 2,
    this.backoffMaxMs = 10000,
    this.streamOpenTimeoutMs = 3000,
  });
}

/// Dart port of `ConnectionController` in
/// `packages/client/connection/src/client/connection.ts`.
///
/// Opens both SSE streams plus a `host.describe` handshake, emits
/// `connected` only after all three succeed, and reconnects with exponential
/// backoff on any generation failure. State is deduplicated via `onStateChange`.
///
/// Usage:
/// ```dart
/// final ctrl = FlutterConnectionController(client,
///   onMuxEnvelope: (env) => manager.onMux(env),
///   onHostEnvelope: (env) => manager.onHost(env),
///   onConnected: (desc) => manager.resync(),
///   onStateChange: (s) => ref.read(connectionStateProvider.notifier).setStateSafe(s),
/// );
/// ctrl.start(); // idempotent
/// // ...
/// ctrl.stop();
/// ```
class FlutterConnectionController {
  final ConnectionClient _client;
  void Function(Map<String, dynamic> envelope)? onMuxEnvelope;
  void Function(Map<String, dynamic> envelope)? onHostEnvelope;
  void Function(Map<String, dynamic> description)? onConnected;
  final void Function(ConnectionState state)? onStateChange;
  final ConnectionConfig _config;

  int _generation = 0;
  int _attempt = 0;
  bool _running = false;
  ConnectionState? _lastState;

  /// Active stream subscriptions for the current generation, cancelled on
  /// suspend/stop so background'd generations close their sockets and the
  /// subsequent generation's handshake does not race with stale frames.
  final Set<StreamSubscription<Map<String, dynamic>>> _activeSubs = {};

  /// Backoff delay completer, completed early on network recovery or
  /// suspend so the loop does not sleep through a background interval.
  Completer<void>? _backoffCompleter;

  /// Whether the controller was suspended for a mobile background transition.
  /// Distinguishes an explicit [stop] (no auto-resume) from a lifecycle
  /// suspend (resume creates a fresh generation).
  bool _suspended = false;

  /// One refresh attempt per auth failure is allowed before entering
  /// [ConnectionState.needsReauth], preventing an infinite 401 loop.
  bool _refreshAttemptedForCurrentFailure = false;

  /// Last auth error from a pump, set when a mux/host stream fails with
  /// 401/403. Checked by [_loop] after `await Future.any` to ensure pump
  /// auth failures are not lost when the outer `host.describe` also fails.
  Object? _pumpAuthError;

  /// Current connection generation (diagnostics/tests): increments once per
  /// connect attempt cycle, mirroring `ConnectionController.generation`.
  int get generation => _generation;

  /// Consecutive failed attempts since the last successful handshake
  /// (diagnostics/tests); resets to 0 on each `connected`.
  int get currentAttempt => _attempt;

  FlutterConnectionController(
    this._client, {
    this.onMuxEnvelope,
    this.onHostEnvelope,
    this.onConnected,
    this.onStateChange,
    ConnectionConfig config = const ConnectionConfig(),
  }) : _config = config;

  /// Idempotent: begin connect/pump/reconnect loop.
  void start() {
    if (_running) return;
    _running = true;
    _suspended = false;
    _refreshAttemptedForCurrentFailure = false;
    unawaited(_loop());
  }

  /// Stop loop; next iteration will not schedule reconnect.
  void stop() {
    _running = false;
    _suspended = false;
    _cancelActiveSubs();
    try {
      _client.abortEventStreams();
    } catch (_) {}
    final mux = _remoteMux;
    _remoteMux = null;
    _eventsClientId = null;
    _client.eventsClientId = null;
    if (mux != null) unawaited(mux.close());
    _backoffCompleter?.complete();
    _backoffCompleter = null;
  }

  /// Suspend for a mobile background transition: stop the reconnect loop,
  /// close mux/host sockets, and emit a non-connected state so the UI does
  /// not falsely show `connected` while backgrounded. Preserves the
  /// connection target and secure token; the next [resume] creates a fresh
  /// generation.
  void suspend() {
    if (!_running && !_suspended) {
      // Already stopped and not suspended — nothing to do, but ensure the UI
      // is not left showing `connected`.
      if (_lastState == ConnectionState.connected ||
          _lastState == ConnectionState.connecting ||
          _lastState == ConnectionState.reconnecting) {
        _emitState(ConnectionState.disconnected);
      }
      return;
    }
    _suspended = true;
    _running = false;
    _cancelActiveSubs();
    try {
      _client.abortEventStreams();
    } catch (_) {}
    final mux = _remoteMux;
    _remoteMux = null;
    _eventsClientId = null;
    _client.eventsClientId = null;
    if (mux != null) unawaited(mux.close());
    _backoffCompleter?.complete();
    _backoffCompleter = null;
    _emitState(ConnectionState.disconnected);
  }

  /// Resume after a background suspend: start a fresh generation with a full
  /// `host.describe` handshake, new WS ticket for [RemoteTarget], and
  /// authoritative resync via [onConnected].
  void resume() {
    if (_running) return;
    // Resume always creates a fresh generation; the generation increment
    // happens in [_loop] via `++_generation`.
    _suspended = false;
    _refreshAttemptedForCurrentFailure = false;
    start();
  }

  /// Whether the controller was suspended for background.
  bool get isSuspended => _suspended;

  bool get isRunning => _running;

  void _cancelActiveSubs() {
    for (final sub in _activeSubs.toList()) {
      unawaited(sub.cancel());
    }
    _activeSubs.clear();
  }

  /// Trigger an immediate reconnect attempt, interrupting any backoff delay.
  /// Used by the connectivity observer when the network recovers from offline.
  void handleNetworkOnline() {
    if (!_running) return;
    if (_lastState != ConnectionState.reconnecting &&
        _lastState != ConnectionState.disconnected) {
      return;
    }
    _backoffCompleter?.complete();
  }

  void _emitState(ConnectionState next) {
    if (_lastState == next) return;
    _lastState = next;
    onStateChange?.call(next);
  }

  Duration _backoffDelay(int attempt) {
    final cap =
        (_config.backoffBaseMs *
                pow(_config.backoffFactor, max(0, attempt - 1)))
            .clamp(0, _config.backoffMaxMs)
            .toInt();
    final jitter = cap ~/ 2 + (Random().nextInt(cap ~/ 2 + 1));
    return Duration(milliseconds: jitter);
  }

  bool _isRemoteAuthFailure(Object error) {
    if (error is RemoteAuthException)
      return error.statusCode == 401 || error.statusCode == 403;
    // Also handle the wrapped http ClientException that _postTypert used to throw for 401/403
    // before we switched to RemoteAuthException — keep for backward compat in tests.
    final msg = error.toString();
    return msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('RemoteAuthException');
  }

  Future<void> _enterNeedsReauth({bool deleteToken = true}) async {
    _emitState(ConnectionState.needsReauth);
    _running = false;
    _suspended = false;
    _cancelActiveSubs();
    if (!deleteToken) return;
    final target = _client.target;
    if (target is RemoteTarget) {
      try {
        await _client.tokenStore?.delete(target.deviceId);
      } catch (_) {}
    }
  }

  Future<bool> _tryRefreshTokenOnce() async {
    if (_refreshAttemptedForCurrentFailure) return false;
    _refreshAttemptedForCurrentFailure = true;
    final target = _client.target;
    if (target is! RemoteTarget) return false;
    final store = _client.tokenStore;
    if (store == null) return false;
    try {
      final newToken = await _client.remoteRefresh();
      await store.write(target.deviceId, newToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  RemoteMuxClient? _remoteMux;
  String? _eventsClientId;
  RemoteMuxClient? get remoteMux => _remoteMux;

  /// Diagnostic snapshot without credentials.
  Map<String, dynamic> get diagnostics => {
    'generation': _generation,
    'attempt': _attempt,
    'running': _running,
    'suspended': _suspended,
    'lastState': _lastState?.name,
    'target': _client.target?.toString(),
    'baseUrl': _client.baseUrl,
    'hasMux': _remoteMux != null,
    'eventsClientId': _eventsClientId != null
        ? '${_eventsClientId!.substring(0, 4)}…'
        : null,
  };

  Future<void> _loop() async {
    while (_running) {
      final int gen = ++_generation;
      _emitState(ConnectionState.connecting);
      _refreshAttemptedForCurrentFailure = false;
      _pumpAuthError = null;

      // Current master: remote.mux is the only production transport.
      {
        final muxClient = _client.createRemoteMuxClient()..start();
        _remoteMux = muxClient;
        final remoteOpen = Completer<void>();
        final remoteSub = Completer<void>();
        String? readyHostHome;
        String? readyClientId;
        // Capture ready info for onConnected
        Future<void> pumpRemote() async {
          try {
            await for (final frame in muxClient.openEvents()) {
              if (!_running || gen != _generation) break;
              if (frame is RemoteEventReadyFrame) {
                readyClientId = frame.clientId;
                _eventsClientId = frame.clientId;
                _client.eventsClientId = frame.clientId;
                readyHostHome = frame.host['home'] as String?;
                if (!remoteOpen.isCompleted) remoteOpen.complete();
                // After ready, open domain streams session/control + workspace/follow
                unawaited(_pumpSessionControl(gen, muxClient));
                unawaited(_pumpWorkspaceFollow(gen, muxClient));
                continue;
              }
              if (frame is RemoteEventEmitFrame) {
                _handleRemoteEmit(frame);
              } else if (frame is RemoteEventWaterfallFrame) {
                unawaited(_handleRemoteWaterfall(frame, muxClient, gen));
              } else if (frame is RemoteEventCancelFrame) {
                _handleRemoteCancel(frame);
              }
            }
          } catch (error) {
            if (_isRemoteAuthFailure(error)) _pumpAuthError = error;
            if (!remoteOpen.isCompleted) remoteOpen.complete();
            if (!remoteSub.isCompleted) remoteSub.complete();
            return;
          } finally {
            if (!remoteOpen.isCompleted) remoteOpen.complete();
            if (!remoteSub.isCompleted) remoteSub.complete();
            try {
              await muxClient.close();
            } catch (_) {}
            if (_remoteMux == muxClient) {
              _remoteMux = null;
              _eventsClientId = null;
              _client.eventsClientId = null;
            }
          }
        }

        unawaited(
          pumpRemote().then((_) {
            if (!remoteSub.isCompleted) remoteSub.complete();
          }),
        );

        bool timedOut = false;
        try {
          // `host.describe` is retired on the host (ApiProxy removed) — the
          // `$events` `ready` frame now carries the authoritative `host.home`.
          // Keep the call opportunistic so a 404 does not wedge the handshake
          // in `connecting` (see `ConnectionClient.hostDescribe` fallback to
          // `{}`).
          final describeFuture = _client.hostDescribe().catchError(
            (Object _) => <String, dynamic>{},
          );
          final timeout = Future<void>.delayed(
            Duration(milliseconds: _config.streamOpenTimeoutMs),
          );
          await Future.any([
            Future.wait([describeFuture, remoteOpen.future]),
            timeout.then((_) {
              timedOut = true;
              return null;
            }),
          ]);
          if (timedOut && !remoteOpen.isCompleted) {
            if (kDebugMode) {
              debugPrint(
                '[FlutterConnectionController] GEN $gen timeout waiting for ready (${_config.streamOpenTimeoutMs}ms) — failing generation to reconnect',
              );
            }
            throw TimeoutException(
              'ready within ${_config.streamOpenTimeoutMs}ms',
              Duration(milliseconds: _config.streamOpenTimeoutMs),
            );
          }
          final desc = await describeFuture;
          if (!_running || gen != _generation)
            throw StateError('generation $gen aborted');
          if (timedOut) {
            throw TimeoutException(
              'ready within ${_config.streamOpenTimeoutMs}ms',
              Duration(milliseconds: _config.streamOpenTimeoutMs),
            );
          }
          final target = _client.target;
          if (target is RemoteTarget) {
            final hostId = desc['hostId'] as String?;
            if (hostId != null && hostId != target.hostId) {
              await _enterNeedsReauth();
              return;
            }
          }
          if (!remoteOpen.isCompleted) {
            throw StateError('generation $gen ready never arrived');
          }
          _attempt = 0;
          _emitState(ConnectionState.connected);
          if (gen == _generation && _running) {
            try {
              // Merge ready host home into desc for live_sync
              final mergedDesc = Map<String, dynamic>.from(desc);
              if (readyHostHome != null) mergedDesc['home'] = readyHostHome;
              if (readyClientId != null)
                mergedDesc['eventsClientId'] = readyClientId;
              onConnected?.call(mergedDesc);
            } catch (_) {}
          }
          await remoteSub.future;
          if (_pumpAuthError != null) throw _pumpAuthError!;
        } catch (error) {
          final Object authError = _pumpAuthError ?? error;
          if (_isRemoteAuthFailure(authError)) {
            final refreshed = await _tryRefreshTokenOnce();
            if (refreshed) {
              _pumpAuthError = null;
              _cancelActiveSubs();
              try {
                _client.abortEventStreams();
              } catch (_) {}
              try {
                await muxClient.close();
              } catch (_) {}
              continue;
            }
            await _enterNeedsReauth();
            return;
          }
          _pumpAuthError = null;
        }
      }

      if (!_running) return;
      _attempt++;
      _emitState(ConnectionState.reconnecting);
      final delay = _backoffDelay(_attempt);
      _backoffCompleter = Completer<void>();
      await Future.any([
        Future<void>.delayed(delay),
        _backoffCompleter!.future,
      ]);
      _backoffCompleter = null;
      if (!_running) return;
    }
  }

  void _handleRemoteEmit(RemoteEventEmitFrame frame) {
    // Route emit frames to existing handlers via synthetic maps
    // Host events: api-session/*, llm/adapters-updated, settings/document-updated, etc.
    // Translate api-session/* to HostFrame handling via onHostEnvelope
    try {
      if (frame.event.startsWith('api-session/')) {
        final type = frame.event.replaceFirst('api-session/', 'host/session-');
        // args[0] is SessionSummary or id etc per host emit
        // Construct synthetic HostFrame-like map for live_sync
        final arg = frame.args.isNotEmpty ? frame.args[0] : null;
        Map<String, dynamic> synthetic;
        if (frame.event == 'api-session/added') {
          synthetic = {
            'type': 'host/session-added',
            'sessionId': (arg as Map?)?['sessionId'] ?? '',
            'blank': (arg as Map?)?['blank'] ?? true,
          };
          if (arg is Map) synthetic.addAll(arg.cast<String, dynamic>());
        } else if (frame.event == 'api-session/removed') {
          synthetic = {
            'type': 'host/session-removed',
            'sessionId': arg is String
                ? arg
                : (arg as Map?)?['sessionId'] ?? '',
          };
        } else if (frame.event == 'api-session/status') {
          final sid = frame.args.length > 0 ? frame.args[0] : '';
          final running = frame.args.length > 1 ? frame.args[1] : false;
          synthetic = {
            'type': 'host/session-status',
            'sessionId': sid is String ? sid : '',
            'running': running == true,
          };
        } else if (frame.event == 'api-session/activity') {
          final sid = frame.args.length > 0 ? frame.args[0] : '';
          synthetic = {
            'type': 'host/session-status',
            'sessionId': sid is String ? sid : '',
            'running': true,
          };
          // Also update via onHostEnvelope will handle; for now pass through
        } else if (frame.event == 'api-session/error') {
          synthetic = {
            'type': 'host/agent-error',
            'sessionId': frame.args.isNotEmpty ? frame.args[0] : '',
            'message': frame.args.length > 1 ? frame.args[1] : '',
          };
        } else {
          synthetic = {
            'type': type,
            'event': frame.event,
            'args': frame.args,
            'type:host/remote-event': frame.event,
          };
          // Fallback: dispatch via RemoteEventBus
          try {
            onHostEnvelope?.call({
              'type': 'host/remote-event',
              'event': frame.event,
              'args': frame.args,
            });
          } catch (_) {}
          return;
        }
        onHostEnvelope?.call(synthetic);
        // Also dispatch via RemoteEventBus for listeners like skill/commands
        try {
          onHostEnvelope?.call({
            'type': 'host/remote-event',
            'event': frame.event,
            'args': frame.args,
          });
        } catch (_) {}
      } else if (frame.event == 'llm/adapters-updated' ||
          frame.event == 'settings/document-updated' ||
          frame.event == 'credentials/reference-updated' ||
          frame.event == 'commands/change' ||
          frame.event == 'agent-preset/selected') {
        try {
          onHostEnvelope?.call({
            'type': 'host/remote-event',
            'event': frame.event,
            'args': frame.args,
          });
        } catch (_) {}
        // Also for live_sync's models_store listeners via RemoteEventBus
        // The RemoteEventBus is fed via HostFrame remote-event, so reuse that
      } else {
        try {
          onHostEnvelope?.call({
            'type': 'host/remote-event',
            'event': frame.event,
            'args': frame.args,
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _handleRemoteWaterfall(
    RemoteEventWaterfallFrame frame,
    RemoteMuxClient muxClient,
    int gen,
  ) async {
    // Waterfall: approval/requested, question/requested etc.
    // For now, translate to legacy MuxFrame synthetic and use existing respond path,
    // but also support new $events/result via client.sendEventsResult
    try {
      final clientId = _eventsClientId;
      if (clientId == null) return;
      // Build synthetic legacy frame for live_sync to show UI
      if (frame.event == 'approval/requested' ||
          frame.event == 'approval/request') {
        final req = frame.request;
        final synthetic = {
          'type': 'approval/requested',
          'sessionId': req['sessionId'] ?? frame.agentId,
          'approvalId': req['approvalId'] ?? req['id'] ?? '',
          'toolName': req['toolName'] ?? '',
          'callId': req['callId'],
          'reason': req['reason'],
          'rpcId': frame.eventId,
          '_clientId': clientId,
          '_eventId': frame.eventId,
        };
        onMuxEnvelope?.call(synthetic);
        // Wait for user action via existing approvalsProvider; the responder will call client.respond
        // But we need to intercept respond to send via $events/result
        // For now, let live_sync's ApprovalResponder handle it via old POST /api/respond → we will make ConnectionClient.respond also try $events/result
      } else if (frame.event == 'user-questions/request' ||
          frame.event == 'question/requested') {
        final req = frame.request;
        final synthetic = {
          'type': 'question/requested',
          'sessionId': req['sessionId'] ?? frame.agentId,
          'questions': req['questions'] ?? req['request']?['questions'] ?? [],
          'rpcId': frame.eventId,
          '_clientId': clientId,
          '_eventId': frame.eventId,
        };
        onMuxEnvelope?.call(synthetic);
      } else {
        // Generic waterfall: dispatch via RemoteEventBus and wait for result
        // For now, just call onHostEnvelope as remote-event waterfall
        try {
          onHostEnvelope?.call({
            'type': 'host/remote-event',
            'event': frame.event,
            'args': [frame.request],
            'eventId': frame.eventId,
            'agentId': frame.agentId,
            '_clientId': clientId,
          });
        } catch (_) {}
      }
      // For generic waterfalls, we need to wait for UI to respond via $events/result
      // This is handled by the UI responders via ConnectionClient.respond which we will make to use $events/result when _clientId present
    } catch (_) {}
  }

  void _handleRemoteCancel(RemoteEventCancelFrame frame) {
    try {
      onMuxEnvelope?.call({
        'type': 'approval/resolved',
        'approvalId': frame.eventId,
        'outcome': 'cancelled',
      });
      onMuxEnvelope?.call({
        'type': 'question/resolved',
        'questionRpcId': frame.eventId,
        'outcome': 'cancelled',
      });
    } catch (_) {}
  }

  Future<void> _pumpSessionControl(int gen, RemoteMuxClient muxClient) async {
    try {
      await for (final raw in muxClient.openSessionControl()) {
        if (!_running || gen != _generation) break;
        final type = raw['type'] as String?;
        if (type == 'baseline') {
          final value = raw['value'] as Map? ?? raw;
          // queues
          final queues = (value['queues'] as Map?) ?? const {};
          for (final e in queues.entries) {
            final sid = e.key as String;
            final items = (e.value as List? ?? const [])
                .whereType<Map>()
                .map((m) => m.cast<String, dynamic>())
                .toList();
            try {
              onMuxEnvelope?.call({
                'type': 'session/queue',
                'sessionId': sid,
                'items': items,
              });
            } catch (_) {}
          }
          final jobs = (value['jobs'] as Map?) ?? const {};
          for (final e in jobs.entries) {
            final sid = e.key as String;
            final list = (e.value as List? ?? const [])
                .whereType<Map>()
                .map((m) => m.cast<String, dynamic>())
                .toList();
            try {
              onMuxEnvelope?.call({
                'type': 'session/jobs',
                'sessionId': sid,
                'jobs': list,
              });
            } catch (_) {}
          }
          final projections = (value['projections'] as Map?) ?? const {};
          for (final e in projections.entries) {
            final sid = e.key as String;
            final block = e.value as Map?;
            if (block == null) continue;
            final asOfSeq = block['asOfSeq'] as int? ?? -1;
            final values =
                (block['values'] as Map?)?.cast<String, dynamic>() ?? const {};
            for (final kv in values.entries) {
              try {
                onMuxEnvelope?.call({
                  'type': 'session/projection',
                  'sessionId': sid,
                  'key': kv.key,
                  'value': kv.value,
                  'seq': asOfSeq,
                });
              } catch (_) {}
            }
          }
        } else if (type == 'queue') {
          try {
            onMuxEnvelope?.call({
              'type': 'session/queue',
              'sessionId': raw['sessionId'],
              'items': raw['items'] ?? const [],
            });
          } catch (_) {}
        } else if (type == 'jobs') {
          try {
            onMuxEnvelope?.call({
              'type': 'session/jobs',
              'sessionId': raw['sessionId'],
              'jobs': raw['jobs'] ?? const [],
            });
          } catch (_) {}
        } else if (type == 'projection') {
          try {
            onMuxEnvelope?.call({
              'type': 'session/projection',
              'sessionId': raw['sessionId'],
              'key': raw['key'],
              'value': raw['value'],
              'seq': raw['seq'] ?? 0,
            });
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _pumpWorkspaceFollow(int gen, RemoteMuxClient muxClient) async {
    try {
      await for (final raw in muxClient.openWorkspaceFollow()) {
        if (!_running || gen != _generation) break;
        final type = raw['type'] as String?;
        if (type == 'baseline') {
          final value = raw['value'] as Map? ?? raw;
          // Synthesize workspace list baseline via host envelope
          try {
            onHostEnvelope?.call({
              'type': 'host/workspace-changed',
              'workspace': {'baseline': value},
            });
            // Also trigger re-fetch via remote-event for workspace providers
            onHostEnvelope?.call({
              'type': 'host/remote-event',
              'event': 'workspace/follow-baseline',
              'args': [value],
            });
          } catch (_) {}
        } else {
          // Incremental: upsert/remove/order/archived
          try {
            onHostEnvelope?.call({
              'type': 'host/workspace-changed',
              'workspace': raw,
            });
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

/// Notifier that owns [ConnectionState] for the UI.
///
/// Wraps [ConnectionClient] lifecycle with backoff and `onStateChange`
/// semantics that mirror `ConnectionController.emitState` (deduplicated).
class ConnectionStateController extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => ConnectionState.idle;

  /// Transition to [next] if different (deduplicated emit).
  void setStateSafe(ConnectionState next) {
    if (state == next) return;
    state = next;
  }

  /// Convenience transition to [ConnectionState.connecting].
  void markConnecting() => setStateSafe(ConnectionState.connecting);

  /// Convenience transition to [ConnectionState.connected].
  void markConnected() => setStateSafe(ConnectionState.connected);

  /// Convenience transition to [ConnectionState.reconnecting].
  void markReconnecting() => setStateSafe(ConnectionState.reconnecting);

  /// Convenience transition to [ConnectionState.disconnected].
  void markDisconnected() => setStateSafe(ConnectionState.disconnected);
}

/// Provider for the current [ConnectionState].
final connectionStateProvider =
    NotifierProvider<ConnectionStateController, ConnectionState>(
      ConnectionStateController.new,
    );

/// Provider for a shared [ConnectionClient].
///
/// Now target-aware: watches [connectionTargetProvider] and builds a
/// transport-agnostic [ConnectionClient] (LocalTarget → loopback http,
/// RemoteTarget → https + bearer + wss?ticket). `LocalTarget` default
/// preserves the existing `DSH_HOST_URL` / `Uri.base.origin` / `127.0.0.1:3080`
/// priority exactly as before, so existing tests and macOS/Web remain
/// unchanged. Tests override either `connectionClientProvider` directly with a
/// fake `ConnectionClient(baseUrl:…)` or `connectionTargetProvider` with a
/// `RemoteTarget` plus an [InMemoryTokenStore].
final connectionClientProvider = Provider<ConnectionClient>((ref) {
  final target = ref.watch(connectionTargetProvider);
  final tokenStore = ref.watch(secureTokenStoreProvider);
  // Remote: bearer + wss?ticket, https
  if (target is RemoteTarget) {
    final client = ConnectionClient.fromTarget(target, tokenStore: tokenStore);
    ref.onDispose(client.dispose);
    return client;
  }
  // Local: preserve existing priority, but respect a non-default LocalTarget
  // (e.g. test HttpServer on 127.0.0.1:0) directly.
  final local = target as LocalTarget;
  final bool isDefaultLocal = local.host == '127.0.0.1' && local.port == 3080;
  if (!isDefaultLocal) {
    final client = ConnectionClient(
      baseUrl: local.baseUri.toString(),
      target: local,
      tokenStore: tokenStore,
    );
    ref.onDispose(client.dispose);
    return client;
  }
  const envUrl = String.fromEnvironment('DSH_HOST_URL', defaultValue: '');
  const kDefaultNativeHostUrl = 'http://127.0.0.1:3080';
  final String baseUrl;
  if (envUrl.isNotEmpty) {
    baseUrl = envUrl;
  } else if (kIsWeb) {
    final origin = Uri.base.origin;
    baseUrl = origin;
  } else {
    baseUrl = kDefaultNativeHostUrl;
  }
  final effective = baseUrl.isEmpty || baseUrl == 'file://' ? '' : baseUrl;
  final client = ConnectionClient(
    baseUrl: effective,
    target: local,
    tokenStore: tokenStore,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Live connection controller instance, wired to [connectionStateProvider].
///
/// Watch in `DshApp` (`ref.watch(flutterConnectionProvider).start()`) to
/// open the `host.describe + mux/host` handshake and keep `SessionsState` in
/// sync via `onHostEnvelope` / `onMuxEnvelope`. Tests override this provider
/// with a no-op controller so no network is touched.
final flutterConnectionProvider = Provider<FlutterConnectionController>((ref) {
  final client = ref.watch(connectionClientProvider);
  final stateNotifier = ref.watch(connectionStateProvider.notifier);
  final controller = FlutterConnectionController(
    client,
    onStateChange: stateNotifier.setStateSafe,
  );
  ref.onDispose(controller.stop);
  return controller;
});

/// Bootstrap that starts the live SSE pump once per app lifetime.
///
/// Mirrors `ConnectionController.start()` in the web client. No-ops when
/// `kIsWeb == false` (vm tests) or no host baseUrl is configured. Waits for
/// `connectionTargetBootstrapProvider` to settle first: a persisted
/// RemoteTarget must be in place before the first handshake, otherwise the
/// pump connects loopback once and immediately tears down on target flip.
final connectionBootstrapProvider = Provider<void>((ref) {
  if (ref.watch(connectionTargetBootstrapProvider).isLoading) return;
  final client = ref.watch(connectionClientProvider);
  if (client.baseUrl.isEmpty) return;
  final controller = ref.watch(flutterConnectionProvider);
  // Deferred start: the pump loop emits `connecting` synchronously, and
  // mutating connectionStateProvider during this provider's build is a
  // Riverpod initialization violation (asserts in debug builds).
  scheduleMicrotask(controller.start);
  ref.onDispose(controller.stop);
});
