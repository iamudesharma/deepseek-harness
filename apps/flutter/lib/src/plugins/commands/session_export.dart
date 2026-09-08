/// Session-log ZIP download — Flutter side-effect of the Host `/export`
/// command, mirroring `packages/session-query/session-log-export/src/client`
/// (`controller.download()` + the `command/executed` listener).
///
/// The Host command itself only acknowledges (`commands/execute` → success
/// text); the bytes stream from the exact fetch route
/// `GET /api/session.export?sessionId=<id>&includeDescendants=true`
/// (`SESSION_LOG_EXPORT_PATH`). React downloads through an anchor click;
/// here the bytes are saved through the platform save sheet
/// (`FilePicker.saveBytes` — native dialog on desktop, share/save sheet on
/// mobile, download on web), so mobile never pretends desktop filesystem
/// behavior exists. A cancelled save sheet is a benign no-op.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/connection/browser_cookie.dart'
    if (dart.library.io) '../../core/connection/browser_cookie_io.dart'
    if (dart.library.js_interop) '../../core/connection/browser_cookie_web.dart'
    as browser_cookie;
import '../../core/connection/connection_client.dart';
import '../../core/connection/http_client.dart'
    if (dart.library.io) '../../core/connection/http_client_io.dart'
    if (dart.library.js_interop) '../../core/connection/http_client_web.dart'
    as http_client_factory;
import '../../core/session/session_models.dart';
import 'command_service.dart' show CommandExecutionOutcome, CommandExecutor;

/// Platform save sheet: persists [bytes] under [fileName], returning the
/// saved path, or null when the user cancels.
typedef FileSaver =
    Future<String?> Function({
      required Uint8List bytes,
      required String fileName,
    });

/// Default saver — the platform-native save sheet on every platform
/// (desktop save dialog, mobile save/share sheet, web download).
Future<String?> defaultFileSaver({
  required Uint8List bytes,
  required String fileName,
}) => FilePicker.platform.saveFile(bytes: bytes, fileName: fileName);

/// Download failure with a user-presentable message (never includes tokens).
class SessionExportException implements Exception {
  /// Creates the failure.
  const SessionExportException(this.message);

  /// User-presentable reason.
  final String message;

  @override
  String toString() => 'SessionExportException: $message';
}

/// Downloads one session's log ZIP and hands it to the save sheet.
class SessionExportService {
  /// Creates the service over [client] (auth + base URL owner).
  ///
  /// [httpClient] overrides the transport in tests (production uses the
  /// platform factory, matching every other connection caller).
  SessionExportService(
    this._client, {
    FileSaver? fileSaver,
    http.Client? httpClient,
  }) : _fileSaver = fileSaver ?? defaultFileSaver,
       _httpClient = httpClient;

  final ConnectionClient _client;
  final FileSaver _fileSaver;
  final http.Client? _httpClient;

  /// `GET /api/session.export` for [sessionId] and save the ZIP.
  ///
  /// Throws [SessionExportException] with user-presentable text on HTTP or
  /// transport failure. A cancelled save sheet returns normally.
  Future<void> download(SessionId sessionId) async {
    final uri = _uri('/api/session.export', {
      'sessionId': sessionId.value,
      'includeDescendants': 'true',
    });
    final headers = await _headers();
    final client = _http();
    final ownsClient = !identical(client, _httpClient);
    try {
      final resp = await client.get(uri, headers: headers);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw SessionExportException(
          resp.statusCode == 401 || resp.statusCode == 403
              ? 'Session log download is not authorized for this session.'
              : resp.statusCode == 404
              ? 'Session log was not found on the host.'
              : 'Session log download failed (status ${resp.statusCode}).',
        );
      }
      if (resp.bodyBytes.isEmpty) {
        throw const SessionExportException(
          'Session log download returned an empty archive.',
        );
      }
      await _fileSaver(
        bytes: resp.bodyBytes,
        fileName: _fileName(resp, sessionId),
      );
    } on SessionExportException {
      rethrow;
    } catch (e) {
      throw SessionExportException('Session log download failed: $e');
    } finally {
      if (ownsClient) client.close();
    }
  }

  String _fileName(http.Response resp, SessionId sessionId) {
    final contentDisposition = resp.headers['content-disposition'];
    if (contentDisposition != null) {
      final match = RegExp(
        r'filename="([^"]+)"',
      ).firstMatch(contentDisposition);
      final name = match?.group(1);
      if (name != null && name.isNotEmpty) return name;
    }
    return 'dsh-session-${sessionId.value}.zip';
  }

  Uri _uri(String path, Map<String, String> query) {
    final baseUrl = _client.baseUrl;
    final base = Uri.parse(
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
    );
    // `?token=` belongs to the `GET /?token=` → `Set-Cookie` exchange, never
    // to API routes (mirrors `ConnectionClient._uri`).
    final filtered = Map<String, String>.from(base.queryParameters)
      ..remove('token');
    return base.replace(
      path: path,
      queryParameters: {...filtered, ...query},
    );
  }

  http.Client _http() {
    final override = _httpClient;
    if (override != null) return override;
    try {
      return http_client_factory.createHttpClient();
    } catch (_) {
      return http.Client();
    }
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'accept': 'application/zip'};
    // Same fence as every `/api/*` caller: web relies on the browser jar
    // (`withCredentials`), native replays the minted cookie.
    String? cookie;
    try {
      cookie = await browser_cookie.getBrowserCookie(_client.baseUrl);
    } catch (_) {
      cookie = null;
    }
    if (cookie != null && !kIsWeb) headers['cookie'] = cookie;
    return headers;
  }
}

/// Wraps [inner] so a successful bare `/export` line also downloads the ZIP
/// (React's `command/executed` listener). Argued lines are left to the Host
/// usage-error path; download failures report through [onExportError] and
/// never fail the already-admitted command outcome.
CommandExecutor exportAwareExecutor(
  CommandExecutor inner, {
  SessionExportService? exporter,
  void Function(String message)? onExportError,
}) {
  return (sessionId, line) async {
    final outcome = await inner(sessionId, line);
    if (outcome.ok && exporter != null && line.trim() == '/export') {
      try {
        await exporter.download(sessionId);
      } on SessionExportException catch (e) {
        onExportError?.call(e.message);
      } catch (e) {
        onExportError?.call('Session log download failed: $e');
      }
    }
    return outcome;
  };
}
