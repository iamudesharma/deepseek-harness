/// Per-session durable image URL cache — mirrors
/// `packages/client/ui-conversation/src/client/conversation/historical-images.ts`
/// `HistoricalImageCache` (ctx.uiConversation.imageUrl / peekImageUrl).
///
/// One session-authorized browser URL per attachment, revoked with the Session
/// binding. Every Conversation target shares one `session.attachment` read.
/// Concrete targets resolve through this cache instead of calling
/// `ConnectionClient.readAttachment` directly.
///
/// `imageUrl` dedupes concurrent fetches (one inflight per SessionId+attachmentId),
/// `peekImageUrl` returns synchronously when cached, `seed` installs a preview
/// URL from an optimistic echo and later replaces it with the canonical URL,
/// `revoke` clears on Session dispose.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import 'session_models.dart';

class HistoricalImageCache {
  HistoricalImageCache(this._client);

  final ConnectionClient _client;

  final Map<String, String> _urls = {}; // key = "$sessionId:$attachmentId" -> objectUrl/dataUrl
  final Map<String, Future<String>> _inflight = {};

  String _key(SessionId sessionId, String attachmentId) => '${sessionId.value}:$attachmentId';

  /// Synchronous cache read — returns cached URL if present, null otherwise.
  /// Mirrors `peekImageUrl`.
  String? peekImageUrl(SessionId sessionId, String attachmentId) {
    return _urls[_key(sessionId, attachmentId)];
  }

  /// Resolve one session-authorized browser URL per attachment.
  ///
  /// Dedupes concurrent callers on the same key; stores the result for `peek`.
  /// Mirrors `imageUrl(sessionId, attachment)`.
  Future<String> imageUrl(SessionId sessionId, String attachmentId) {
    final key = _key(sessionId, attachmentId);
    final cached = _urls[key];
    if (cached != null) return Future.value(cached);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _fetchAndCache(sessionId, attachmentId, key);
    _inflight[key] = future;
    return future;
  }

  Future<String> _fetchAndCache(SessionId sessionId, String attachmentId, String key) async {
    try {
      // Primary path: use typed readAttachment (returns Uint8List bytes).
      try {
        final bytes = await _client.readAttachment(sessionId, attachmentId);
        if (bytes.isNotEmpty) {
          final String b64 = base64Encode(bytes);
          // mediaType unknown from bytes alone; default to png; host's attachment ref
          // would carry precise type but is not exposed via this byte-only face.
          final String dataUrl = 'data:image/png;base64,$b64';
          _urls[key] = dataUrl;
          return dataUrl;
        }
      } catch (_) {
        // Fallback to generic Typert call for hosts that expose Map shape
        Map<String, dynamic>? result;
        try {
          result = await _client.callMethod('session/attachment', {
            'sessionId': sessionId.value,
            'attachmentId': attachmentId,
          });
        } catch (_) {
          result = await _client.callMethod('session.attachment', {
            'sessionId': sessionId.value,
            'attachmentId': attachmentId,
          });
        }
        String dataUrl = '';
        if (result != null) {
          final data = result['data']?.toString() ?? result['value']?.toString() ?? '';
          String mediaType = 'image/png';
          final att = result['attachment'];
          if (att is Map && att['mediaType'] is String) mediaType = att['mediaType'] as String;
          if (data.isNotEmpty) {
            dataUrl = 'data:$mediaType;base64,$data';
          } else if (result['dataUrl'] is String) {
            dataUrl = result['dataUrl'] as String;
          }
          if (dataUrl.isNotEmpty) {
            _urls[key] = dataUrl;
            return dataUrl;
          }
        }
      }
      return '';
    } catch (e) {
      if (kDebugMode) debugPrint('[HistoricalImageCache] fetch failed $key: $e');
      rethrow;
    } finally {
      _inflight.remove(key);
    }
  }

  /// Seed a preview URL from an optimistic echo (e.g., FileReader data URL).
  /// Exposes the preview synchronously via `peek`, later replaced when
  /// `imageUrl` fetches the canonical URL.
  void seed(SessionId sessionId, String attachmentId, String previewUrl) {
    final key = _key(sessionId, attachmentId);
    if (!_urls.containsKey(key)) {
      _urls[key] = previewUrl;
    }
  }

  /// Revoke and clear URLs for a Session binding (on dispose).
  void revokeSession(SessionId sessionId) {
    final prefix = '${sessionId.value}:';
    final keys = _urls.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _urls.remove(k);
    }
    final inflightKeys = _inflight.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in inflightKeys) {
      _inflight.remove(k);
    }
  }

  /// Clear all.
  void clear() {
    _urls.clear();
    _inflight.clear();
  }
}

/// Riverpod provider for the per-session durable image URL cache.
///
/// Mirrors `ctx.uiConversation.imageUrl/peekImageUrl` — every Conversation
/// target shares one `session.attachment` read via this cache.
final historicalImageCacheProvider = Provider<HistoricalImageCache>((ref) {
  final client = ref.watch(connectionClientProvider);
  final cache = HistoricalImageCache(client);
  ref.onDispose(cache.clear);
  return cache;
});
