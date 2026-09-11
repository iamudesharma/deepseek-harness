/// Authenticated session-media client — the Dart slice of React
/// `AssistantMarkdown.localPathMediaUrl` + `SessionMediaReferences`
/// (`packages/api/session-controller/src/media-references.ts`).
///
/// Assistant prose may reference Host-local absolute media paths; same-origin
/// `GET|HEAD /api/file?path=` serves them through the connection's cookie /
/// bearer handshake with per-request Host policy (workspace-root
/// containment, regular-file, allowlisted media, byte caps, fail-closed).
/// This client never invents policy: caps and containment are Host-owned;
/// HTTP statuses map to typed failures and the caller renders alt text.
///
/// URL mapping mirrors React exactly: only absolute POSIX paths (`/...`,
/// not `//...`, not `file://`) map; everything else yields null (inert).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/connection_client.dart';

/// How a media fetch failed. Never message-parsed: HTTP statuses only.
enum MediaFileFailure {
  /// Outside the workspace root, not a regular file, or not served.
  unavailable,

  /// Over the Host byte cap.
  tooLarge,

  /// Not authenticated (caller re-auths; no retry loop here).
  denied,
}

/// Typed session-media failure.
class MediaFileException implements Exception {
  /// Creates a media failure.
  const MediaFileException(this.failure, [this.message = '']);

  /// Failure class.
  final MediaFileFailure failure;

  /// Optional detail (never a credential or absolute path).
  final String message;

  @override
  String toString() => 'MediaFileException($failure${message.isEmpty ? '' : ': $message'})';
}

/// Maps an assistant-prose media destination to the authenticated file URL.
/// Mirrors React `localPathMediaUrl`: absolute POSIX paths only.
/// @param origin - connection origin (`http(s)://host:port`).
/// @param value - markdown image destination as written.
/// @returns the `/api/file` URL, or null when the destination stays inert.
String? localPathMediaUrl(String origin, String value) {
  if (value.isEmpty || value.startsWith('//') || value.startsWith('file://')) {
    return null;
  }
  if (!value.startsWith('/')) return null;
  final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  return '$base/api/file?path=${Uri.encodeComponent(value)}';
}

/// Session-media fetch over an authenticated connection.
class MediaFileClient {
  /// Creates the client.
  MediaFileClient(this._client);

  final ConnectionClient _client;

  /// Fetches one media file's bytes, enforcing nothing client-side: the
  /// Host applies containment, type, and byte policy per request.
  /// @param fileUrl - URL from [localPathMediaUrl].
  /// @throws [MediaFileException] on unavailable/too-large/denied.
  Future<Uint8List> fetchBytes(String fileUrl) async {
    final response = await _client.fetchMedia(Uri.parse(fileUrl));
    switch (response.statusCode) {
      case 200:
        return response.bodyBytes;
      case 413:
        throw const MediaFileException(MediaFileFailure.tooLarge);
      case 401:
      case 403:
        throw const MediaFileException(MediaFileFailure.denied);
      default:
        throw MediaFileException(
          MediaFileFailure.unavailable,
          'HTTP ${response.statusCode}',
        );
    }
  }

  /// Fetches one image as a data URL for `Image.memory` display.
  /// @param fileUrl - URL from [localPathMediaUrl].
  /// @param mediaType - image media type for the data URL prefix.
  Future<String> fetchDataUrl(String fileUrl, {String mediaType = 'image/png'}) async {
    final bytes = await fetchBytes(fileUrl);
    return 'data:$mediaType;base64,${base64Encode(bytes)}';
  }

  /// Existence probe without downloading.
  /// @returns true on 200, false on any failure (never throws).
  Future<bool> exists(String fileUrl) async {
    try {
      final response = await _client.fetchMedia(Uri.parse(fileUrl), head: true);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Shared session-media client (no media state lives here; image caches own
/// their entries like `HistoricalImageCache`).
final mediaFileClientProvider = Provider<MediaFileClient>((ref) {
  return MediaFileClient(ref.watch(connectionClientProvider));
});
