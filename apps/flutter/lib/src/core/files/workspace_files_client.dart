/// Typed `workspaceFiles/*` client — the Dart slice of
/// `packages/api/workspace-files` (`src/types.ts` wire shapes,
/// `src/index.ts` service contract, `src/client/remote.ts` faces).
///
/// Every method resolves the workspace root from [SessionId] Host-side (the
/// session travels with the call, exactly like the generated
/// `remote.workspaceFiles.list(sessionId, path, signal)` face); the client
/// never invents local filesystem state. Caps (`maxBytes` 2MiB, `maxLines`
/// 5000, `maxEntries` 2000) are Host-enforced and mirrored here as
/// documentation constants only — this client never pre-rejects.
///
/// Failures arrive as typed [WorkspaceFileException] (never message-parsed):
/// the six `workspace-file/*` codes plus `gateway/bad-request` for
/// over-cap `limit`/`length`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/rpc_envelope.dart';
import '../connection/connection_client.dart';
import '../connection/remote_mux_client.dart';
import '../session/session_models.dart';

/// Host `maxBytes` cap (2 MiB): pages cut by bytes refuse past it.
/// Host-enforced; mirrored here for display copy only.
const int kWorkspaceFileMaxBytes = 2 * 1024 * 1024;

/// Host `maxLines` cap (5000): the default and maximum page length.
/// Host-enforced; mirrored here for display copy only.
const int kWorkspaceFileMaxLines = 5000;

/// Host `maxEntries` cap (2000): listings past it report `truncated`.
/// Host-enforced; mirrored here for display copy only.
const int kWorkspaceFileMaxEntries = 2000;

/// What a listed child resolves to. A symlink reports its destination type;
/// `other` is neither regular file nor directory. A `file` listing is a
/// listing fact, not a readability promise (`read` still refuses symlinks).
enum WorkspaceEntryType { file, directory, other }

/// Identity and freshness of one workspace file, without content.
/// Mirrors `WorkspaceFileStat`: absolute path with symlinks resolved, opaque
/// version token (equality only, never parsed), optional byte size.
class WorkspaceFileStat {
  /// Creates a stat value.
  const WorkspaceFileStat({
    required this.absolutePath,
    required this.version,
    this.bytes,
  });

  /// Absolute path in the filesystem's execution world.
  final String absolutePath;

  /// Opaque freshness token.
  final String version;

  /// Complete file byte size, when reported.
  final int? bytes;

  /// Decodes a Host stat object.
  factory WorkspaceFileStat.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileStat(
      absolutePath: json['absolutePath'] as String,
      version: json['version'] as String,
      bytes: json['bytes'] as int?,
    );
  }
}

/// One page of a workspace text file. Lines are 1-based; `text` holds at
/// most `limit` lines joined by `\n` with no trailing terminator. Empty
/// `text` with `lines == 0` means past-the-end; check [lines], not emptiness.
class WorkspaceFileText extends WorkspaceFileStat {
  /// Creates a text page value.
  const WorkspaceFileText({
    required super.absolutePath,
    required super.version,
    super.bytes,
    required this.offset,
    required this.text,
    required this.lines,
    required this.eof,
  });

  /// First line of the page, as requested.
  final int offset;

  /// Page lines joined by `\n`.
  final String text;

  /// How many lines the page holds; 0 past the file's last line.
  final int lines;

  /// Whether the page includes the file's last line.
  final bool eof;

  /// Decodes a Host text page.
  factory WorkspaceFileText.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileText(
      absolutePath: json['absolutePath'] as String,
      version: json['version'] as String,
      bytes: json['bytes'] as int?,
      offset: json['offset'] as int,
      text: json['text'] as String? ?? '',
      lines: json['lines'] as int? ?? 0,
      eof: json['eof'] as bool? ?? false,
    );
  }
}

/// One byte window of a workspace file: base64 `data`, 0-based `offset`.
class WorkspaceFileBytes extends WorkspaceFileStat {
  /// Creates a byte window value.
  const WorkspaceFileBytes({
    required super.absolutePath,
    required super.version,
    super.bytes,
    required this.offset,
    required this.data,
    required this.eof,
  });

  /// First byte of the window, as requested.
  final int offset;

  /// Window bytes in base64; empty at or past the file's end.
  final String data;

  /// Whether the window includes the file's last byte.
  final bool eof;

  /// Decodes a Host byte window.
  factory WorkspaceFileBytes.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileBytes(
      absolutePath: json['absolutePath'] as String,
      version: json['version'] as String,
      bytes: json['bytes'] as int?,
      offset: json['offset'] as int,
      data: json['data'] as String? ?? '',
      eof: json['eof'] as bool? ?? false,
    );
  }
}

/// One direct child of a listed directory.
class WorkspaceDirectoryEntry {
  /// Creates a directory entry.
  const WorkspaceDirectoryEntry({required this.name, required this.type, this.size});

  /// Basename inside the listed directory.
  final String name;

  /// Resolved child type.
  final WorkspaceEntryType type;

  /// Byte size, present only for regular files that report it.
  final int? size;

  /// Decodes a Host directory entry.
  factory WorkspaceDirectoryEntry.fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'directory' => WorkspaceEntryType.directory,
      'other' => WorkspaceEntryType.other,
      _ => WorkspaceEntryType.file,
    };
    return WorkspaceDirectoryEntry(
      name: json['name'] as String,
      type: type,
      size: json['size'] as int?,
    );
  }
}

/// Direct children of one directory in backend stable name order.
/// [path] is workspace-relative (empty for the root); a child's path is
/// `path + '/' + name`. Presentation order is the caller's choice.
class WorkspaceDirectoryListing {
  /// Creates a directory listing value.
  const WorkspaceDirectoryListing({
    required this.path,
    required this.entries,
    required this.truncated,
  });

  /// Listed directory as a workspace path (empty for root).
  final String path;

  /// Direct children, cut to the entry cap.
  final List<WorkspaceDirectoryEntry> entries;

  /// Whether the entry cap dropped children.
  final bool truncated;

  /// Decodes a Host listing.
  factory WorkspaceDirectoryListing.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'];
    return WorkspaceDirectoryListing(
      path: json['path'] as String? ?? '',
      entries: entries is List
          ? entries
                .whereType<Map>()
                .map(
                  (e) => WorkspaceDirectoryEntry.fromJson(
                    e.cast<String, dynamic>(),
                  ),
                )
                .toList()
          : const [],
      truncated: json['truncated'] as bool? ?? false,
    );
  }
}

/// One filesystem observation: a new version, or a disappearance.
/// Frames report observations, not deltas: holding the version already
/// means the consumer learns nothing new.
class WorkspaceFileChange {
  /// Creates a change observation.
  const WorkspaceFileChange({required this.absolutePath, this.version})
    : absent = version == null;

  /// Observed absolute path.
  final String absolutePath;

  /// Freshness token after the operation; null when the file is gone.
  final String? version;

  /// Whether the file was observed gone.
  final bool absent;

  /// Decodes a Host change observation.
  factory WorkspaceFileChange.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileChange(
      absolutePath: json['absolutePath'] as String,
      version: json['absent'] == true ? null : json['version'] as String?,
    );
  }
}

/// One watch frame: `ready` confirms observation; `change` carries one.
class WorkspaceFileWatchFrame {
  /// Creates a watch frame.
  const WorkspaceFileWatchFrame.ready() : change = null;
  /// Creates a watch frame.
  const WorkspaceFileWatchFrame.change(this.change);

  /// Whether this frame confirms observation is live.
  bool get isReady => change == null;

  /// The observation; null on ready frames.
  final WorkspaceFileChange? change;

  /// Decodes a Host watch frame.
  factory WorkspaceFileWatchFrame.fromJson(Map<String, dynamic> json) {
    if (json['kind'] == 'ready') return const WorkspaceFileWatchFrame.ready();
    final change = json['change'];
    if (change is Map) {
      return WorkspaceFileWatchFrame.change(
        WorkspaceFileChange.fromJson(change.cast<String, dynamic>()),
      );
    }
    throw FormatException('invalid workspace file watch frame: $json');
  }
}

/// Typed `workspace-file/*` failure. Never constructed from human-readable
/// text: [code] is the exact Host code, [path] the subject when carried.
class WorkspaceFileException implements Exception {
  /// Creates a file failure.
  const WorkspaceFileException({
    required this.code,
    required this.message,
    this.path,
    this.limit,
  });

  /// Exact Host error code.
  final RpcErrorCode code;

  /// Host seam text, shown as-is.
  final String message;

  /// Subject path when the Host carries one.
  final String? path;

  /// Cap that refused the page (`too-large` only).
  final int? limit;

  /// Maps a transport failure to the typed file failure when it carries a
  /// `workspace-file/*` code; rethrows anything else untouched.
  factory WorkspaceFileException.fromTransport(Object error) {
    if (error is RemoteMethodException) {
      switch (error.code) {
        case RpcErrorCode.workspaceFileNotFound:
        case RpcErrorCode.workspaceFileOutsideWorkspace:
        case RpcErrorCode.workspaceFileTooLarge:
        case RpcErrorCode.workspaceFileNotText:
        case RpcErrorCode.workspaceFileNotRegularFile:
        case RpcErrorCode.workspaceFileNotDirectory:
        case RpcErrorCode.workspaceFileUnsupportedAddress:
        case RpcErrorCode.workspaceFileUnknownWorkspace:
          final details = error.details;
          return WorkspaceFileException(
            code: error.code,
            message: error.message,
            path: details['path'] as String?,
            limit: details['limit'] as int?,
          );
        default:
          throw error;
      }
    }
    throw error;
  }

  @override
  String toString() => 'WorkspaceFileException(${code.wire}: $message)';
}

/// Typed `workspaceFiles/*` Remote client.
///
/// The session id travels with every call because the endpoint resolves the
/// workspace root from it (generated face
/// `remote.workspaceFiles.list(sessionId, path, signal)`); paths follow the
/// two vocabularies in `types.ts` (absolute for read/stat, workspace paths
/// for list). A Remote failure never rejects with a bare map: callers get
/// either values or [WorkspaceFileException]/transport errors.
class WorkspaceFilesClient {
  /// Creates the client over a connection and an optional mux opener for
  /// the `changes` stream (absent when no mux generation is active).
  WorkspaceFilesClient(
    this._client, {
    RemoteMuxClient? Function()? muxForSession,
  }) : _muxForSession = muxForSession;

  final ConnectionClient _client;
  final RemoteMuxClient? Function()? _muxForSession;

  /// Stats one file by absolute path.
  /// @param sessionId - session whose workspace authorizes the read.
  /// @param path - absolute path in the filesystem's execution world.
  Future<WorkspaceFileStat> stat(SessionId sessionId, String path) async {
    try {
      final result = await _client.callMethod('workspaceFiles/stat', {
        'sessionId': sessionId.value,
        'path': path,
      });
      return WorkspaceFileStat.fromJson(result);
    } catch (e) {
      throw WorkspaceFileException.fromTransport(e);
    }
  }

  /// Reads one text page (1-based [offset], at most [limit] lines).
  /// @param sessionId - session whose workspace authorizes the read.
  /// @param path - absolute path in the filesystem's execution world.
  Future<WorkspaceFileText> read(
    SessionId sessionId,
    String path, {
    int offset = 1,
    int? limit,
  }) async {
    try {
      final result = await _client.callMethod('workspaceFiles/read', {
        'sessionId': sessionId.value,
        'path': path,
        'range': {
          'offset': offset,
          if (limit != null) 'limit': limit,
        },
      });
      return WorkspaceFileText.fromJson(result);
    } catch (e) {
      throw WorkspaceFileException.fromTransport(e);
    }
  }

  /// Reads one byte window (0-based [offset], at most [length] bytes).
  Future<WorkspaceFileBytes> readBytes(
    SessionId sessionId,
    String path, {
    int offset = 0,
    int? length,
  }) async {
    try {
      final result = await _client.callMethod('workspaceFiles/readBytes', {
        'sessionId': sessionId.value,
        'path': path,
        'range': {
          'offset': offset,
          if (length != null) 'length': length,
        },
      });
      return WorkspaceFileBytes.fromJson(result);
    } catch (e) {
      throw WorkspaceFileException.fromTransport(e);
    }
  }

  /// Lists one directory by workspace path (empty for the root).
  /// @param sessionId - session whose workspace root anchors [path].
  /// @param path - workspace-relative path, empty for the root.
  Future<WorkspaceDirectoryListing> list(SessionId sessionId, String path) async {
    try {
      final result = await _client.callMethod('workspaceFiles/list', {
        'sessionId': sessionId.value,
        'path': path,
      });
      return WorkspaceDirectoryListing.fromJson(result);
    } catch (e) {
      throw WorkspaceFileException.fromTransport(e);
    }
  }

  /// Watches one session's workspace file observations. The stream ends when
  /// the mux generation turns over; the owner reopens per generation (the
  /// preview host does this on its lifetime, like follow resubscription).
  /// @param sessionId - session whose writes this feed follows.
  Stream<WorkspaceFileWatchFrame> watch(SessionId sessionId) async* {
    final mux = _muxForSession?.call();
    if (mux == null) {
      throw StateError('workspace file watch needs an active mux generation');
    }
    await for (final raw in mux.open('workspaceFiles/changes', {
      'args': {
        'sessionId': sessionId.value,
      },
    })) {
      final kind = raw['kind'];
      if (kind == 'ready') {
        yield const WorkspaceFileWatchFrame.ready();
      } else if (kind == 'change' && raw['change'] is Map) {
        yield WorkspaceFileWatchFrame.change(
          WorkspaceFileChange.fromJson(
            (raw['change'] as Map).cast<String, dynamic>(),
          ),
        );
      }
    }
  }
}

/// Shared typed workspace-files client (no file state lives here; trees and
/// previews own their level/page caches like React's per-tab stores).
final workspaceFilesClientProvider = Provider<WorkspaceFilesClient>((ref) {
  return WorkspaceFilesClient(ref.watch(connectionClientProvider));
});
