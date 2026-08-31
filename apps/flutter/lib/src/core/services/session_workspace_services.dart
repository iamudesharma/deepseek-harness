/// Sessions and workspaces service slices of the runtime mount face —
/// Dart carriers of the React runtime's `ctx.sessions` / `ctx.workspaces`
/// outward faces (packages/client/runtime/src/client/index.ts).
///
/// - [SessionsService]   slice of `ISessions` (history window fetch)
/// - [WorkspacesService] slice of `IWorkspaces` over `workspace.*` RPCs
/// - [DirectoryListSignal] cooperative abort token for directory scans
///
/// Re-exported by runtime_services.dart so the single service-face import
/// stays stable for every consumer.
library;

import 'dart:async';

import '../api/rpc_envelope.dart' show RpcErrorCode, RemoteMethodException;
import '../connection/connection_client.dart' show ConnectionClient;
import '../session/session_models.dart';

/// Host directory-picker capability kind — mirrors the `kind` discriminant on
/// `DirectoryPickerCapability` in
/// `packages/host/directory-picker/src/index.ts`.
///
/// The harness has no wire advertisement for this — see
/// [WorkspacesService.probeDirectoryPickerKind] for how Flutter discovers it.
enum DirectoryPickerKind {
  /// OS chooser on the host display (`directoryPicker/pick`).
  native,

  /// In-app Miller-column browser (`directoryPicker/list`,
  /// `directoryPicker/createDirectory`). The remote-capable interaction.
  browse,
}

/// Sessions slice: durable history window fetch for a session. Live list and
/// current-session state ride the existing sessions provider, which is wired
/// to host frames by live_sync; this service adds the pull path used on
/// open/resync.
class SessionsService {
  /// Creates the service around one client.
  SessionsService(this._client);

  final ConnectionClient _client;

  /// Loads a session's durable history window (typed entries).
  ///
  /// `throughSeq` is the authoritative cursor from `session/follow`
  /// snapshot (`LiveHistory.acceptedSeq`). Callers without a cursor must
  /// wait for the snapshot; no sentinel probe.
  Future<List<HistoryEntry>> history(
    SessionId sessionId, {
    required int throughSeq,
    int? beforeSeq,
    int? maxMessages,
  }) =>
      _client.getSessionEvents(
        sessionId,
        throughSeq: throughSeq,
        beforeSeq: beforeSeq,
        maxMessages: maxMessages,
      );
}

class _AbortedException implements Exception {}

/// Abort signal for directory listing — Dart analog of `AbortSignal`.
///
/// The host `listDirectory` scan aborts when this signal fires. Mirrors the
/// React `listDirectory(path, signal)` contract where `AbortController`
/// cancellation aborts the wire scan and frees host resources. Dart's `http`
/// has no native abort, so this is a cooperative token that races the HTTP
/// future via [whenAborted] — the caller aborts the previous scan on
/// supersession instead of only discarding its eventual result.
class DirectoryListSignal {
  bool _aborted = false;
  final Completer<void> _completer = Completer<void>();

  /// Whether abort has been requested.
  bool get aborted => _aborted;

  /// Completes when abort is requested.
  Future<void> get whenAborted => _completer.future;

  /// Requests cancellation — completes [whenAborted] and sets [aborted].
  void abort() {
    if (_aborted) return;
    _aborted = true;
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Workspaces slice mirroring the `WorkspaceApi` method names exactly
/// (`workspace.list`, `workspace.create`, … in rpc-map.ts).
class WorkspacesService {
  /// Creates the service around one client.
  WorkspacesService(this._client);

  final ConnectionClient _client;

  /// Whether the underlying client is remote (bearer).
  bool get isRemote => _client.isRemote;

  /// The directory-picker kind the current host composition actually serves.
  ///
  /// The harness advertises no `host.describe` field for the picker — the
  /// only signal is the host's typed failure on a cross-kind call. Resolved
  /// lazily from the first [probeDirectoryPickerKind] and cached for the
  /// lifetime of this service so subsequent calls skip the probe round-trip.
  DirectoryPickerKind? _directoryPickerKind;

  /// Reads the cached host picker kind, or `null` if the service has not
  /// observed either success or a typed cross-kind failure yet.
  DirectoryPickerKind? get directoryPickerKind => _directoryPickerKind;

  /// Resolves the host's directory-picker capability kind and caches it.
  ///
  /// Mirrors React's branch in `ui-directory-picker-*`: the trigger has no
  /// idea which kind is composed — the branch lives at server boot. The only
  /// runtime hint is the host's typed `directory-picker-unavailable`
  /// failure on a cross-kind call (`details.capability` carries the actual
  /// kind). Flutter web/remote must always use `browse`; Flutter desktop
  /// prefers `native`. We probe once and remember; a wrong guess surfaces the
  /// host's authoritative message verbatim, never a fabricated path.
  Future<DirectoryPickerKind> probeDirectoryPickerKind() async {
    final cached = _directoryPickerKind;
    if (cached != null) return cached;
    try {
      // `directoryPicker/pick` is the universal "is the host alive" probe
      // because both kinds accept an empty args body. A native host returns
      // a path or null; a browse host returns
      // `directory-picker-unavailable { capability: 'browse' }`.
      await _client.callMethod('directoryPicker/pick', const {});
      _directoryPickerKind = DirectoryPickerKind.native;
      return DirectoryPickerKind.native;
    } on RemoteMethodException catch (e) {
      if (e.code == RpcErrorCode.directoryPickerUnavailable) {
        final kind = e.details['capability'];
        if (kind == 'native') {
          _directoryPickerKind = DirectoryPickerKind.native;
          return DirectoryPickerKind.native;
        }
        if (kind == 'browse') {
          _directoryPickerKind = DirectoryPickerKind.browse;
          return DirectoryPickerKind.browse;
        }
      }
      rethrow;
    }
  }

  /// Forces a re-probe on the next call; tests and host-restart scenarios
  /// may swap the composition under our feet.
  void invalidateDirectoryPickerKind() {
    _directoryPickerKind = null;
  }

  Future<Map<String, Object?>> _call(
    String method, [
    Map<String, Object?> payload = const {},
  ]) => _client.callMethod(method, payload);

  List<Map<String, Object?>> _items(Map<String, Object?> value) {
    final items = value['items'];
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
    }
    return const [];
  }

  /// `workspace.list` → ordered workspace rows.
  Future<List<Map<String, Object?>>> list() async =>
      _items(await _call('workspace/list'));

  /// `workspace.create { path }` → created workspace row.
  Future<Map<String, Object?>> create({required String path}) async {
    final value = await _call('workspace/create', {'path': path});
    final workspace = value['workspace'];
    if (workspace is Map) return workspace.cast<String, Object?>();
    return value;
  }

  /// `directoryPicker.pick` → native directory chooser result (null cancels).
  ///
  /// Caller-facing entry point for the host's OS chooser. For browse hosts,
  /// surfaces the typed `directory-picker-unavailable { capability: 'browse' }`
  /// verbatim so the UI can re-route to the Miller dialog rather than
  /// silently failing.
  Future<String?> pickDirectory() async {
    final value = await _client.callMethod('directoryPicker/pick', const {});
    _directoryPickerKind = DirectoryPickerKind.native;
    final path = value['path'];
    return path is String ? path : null;
  }

  /// `host.listDirectory { path? }` → directory level with ancestry (browse capability).
  ///
  /// [signal] mirrors React's `AbortSignal` — when it aborts, the underlying
  /// HTTP call is raced and the host scan is abandoned. The host itself
  /// receives no explicit abort frame over Typert HTTP, but the client stops
  /// waiting and supersedes the stale result, freeing the caller immediately
  /// while the host scan naturally completes without consumer.
  ///
  /// Capability routing: the harness has no `host.describe` advertisement for
  /// the picker kind, so the first failure is the runtime hint. If the host
  /// serves `native`, the typed `directory-picker-unavailable { capability:
  /// 'native' }` is re-thrown unchanged so the trigger surface can drive
  /// [pickDirectory] instead (mirrors React's slot-driven branch — no client
  /// code invents a kind).
  Future<Map<String, Object?>> listDirectory({
    String? path,
    DirectoryListSignal? signal,
  }) async {
    final payload = <String, Object?>{'path': ?path};
    if (signal?.aborted ?? false) {
      throw Exception('listDirectory aborted');
    }
    try {
      final future = _client.callMethod('directoryPicker/list', payload);
      final value = signal == null
          ? await future
          : await Future.any(<Future<Map<String, Object?>>>[
              future,
              signal.whenAborted.then((_) => throw _AbortedException()),
            ]);
      _directoryPickerKind = DirectoryPickerKind.browse;
      return value;
    } on _AbortedException {
      throw Exception('listDirectory aborted');
    } on RemoteMethodException catch (e) {
      if (e.code == RpcErrorCode.directoryPickerUnavailable &&
          e.details['capability'] == 'native') {
        _directoryPickerKind = DirectoryPickerKind.native;
      }
      rethrow;
    }
  }

  /// `directoryPicker.createDirectory { path, name }` → created directory absolute path.
  ///
  /// Throws [RemoteMethodException] with code
  /// [RpcErrorCode.directoryPickerUnavailable] when the host serves `native`
  /// — there is no native equivalent for non-recursive create, so the trigger
  /// surface must drive [pickDirectory] for new-folder cases on native hosts.
  Future<String> createDirectory({
    required String path,
    required String name,
  }) async {
    try {
      final value = await _client.callMethod('directoryPicker/createDirectory', {
        'path': path,
        'name': name,
      });
      final created = value['path'];
      if (created is String) return created;
      // Fallback: host may return { path } nested differently.
      final inner = value['value'];
      if (inner is Map && inner['path'] is String) return inner['path'] as String;
      return created?.toString() ?? '$path/$name';
    } on RemoteMethodException catch (e) {
      if (e.code == RpcErrorCode.directoryPickerUnavailable) {
        _directoryPickerKind = DirectoryPickerKind.values.firstWhere(
          (k) => k.name == (e.details['capability'] as String? ?? ''),
          orElse: () => _directoryPickerKind ?? DirectoryPickerKind.browse,
        );
      }
      rethrow;
    }
  }

  /// `workspace.archiveSession { sessionId }`.
  Future<void> archiveSession(String sessionId) =>
      _call('workspace/archiveSession', {'sessionId': sessionId});
}
