/// Session-addressed background file upload — Dart port of the
/// `FileUploadService` background-carrier path
/// (`packages/client/file-upload/src/client/contract.ts` +
/// `runtime.ts` `upload()`).
///
/// Dart has no Blob/ReadableStream split: every body is exact bytes, so the
/// background route (`POST /api/session/uploadFileBinary?sessionId&name`,
/// octet-stream) serves all uploads. The exact-bytes Typert fallback
/// (`remote.fileUploads.upload`, Agent-scoped) has no Dart equivalent and is
/// intentionally absent: the background route accepts the same bytes.
/// `available` is always true — Flutter has no `?fixture` page mode that
/// disables the carrier. Composer wiring for non-image attachments
/// (`{type:'file', receiptId}` prompt parts, React `service.ts:261`) is
/// deferred; this face stages the receipt, it does not submit it.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../connection/connection_client.dart';
import '../session/session_models.dart';

/// Raw-byte upload route owned by the file-upload service.
const String kFileUploadPath = '/api/session/uploadFileBinary';

/// Durable receipt for one staged file upload.
class FileUploadReceipt {
  /// Per-upload authority accepted only inside the receiving Agent scope.
  final String receiptId;

  /// Durable attachment identity.
  final String attachmentId;

  /// Stored display name.
  final String name;

  /// Stored byte count.
  final int bytes;

  /// Creates a receipt.
  const FileUploadReceipt({
    required this.receiptId,
    required this.attachmentId,
    required this.name,
    required this.bytes,
  });

  /// Validates one `{ok:true, value:{receiptId, file}}` body.
  ///
  /// Mirrors `parseFileUploadResult` receipt validation (string ids/name,
  /// safe non-negative integer bytes). Throws [TypeError] on invalid shape.
  /// @param body - decoded JSON response body.
  static FileUploadReceipt parseSuccess(Map<String, dynamic> body) {
    final result = body['value'];
    final file = result is Map ? result['file'] : null;
    final receiptId = result is Map ? result['receiptId'] : null;
    final attachmentId = file is Map ? file['attachmentId'] : null;
    final name = file is Map ? file['name'] : null;
    final bytes = file is Map ? file['bytes'] : null;
    if (receiptId is! String ||
        attachmentId is! String ||
        name is! String ||
        bytes is! int ||
        bytes < 0) {
      throw TypeError();
    }
    return FileUploadReceipt(
      receiptId: receiptId,
      attachmentId: attachmentId,
      name: name,
      bytes: bytes,
    );
  }
}

/// Outcome of one staged upload: receipt or business failure.
///
/// Mirrors `RemoteResult<FileUploadValue>`: `ok:false` business failures are
/// values, not throws. Transport failures (non-200, invalid shape) throw.
sealed class FileUploadOutcome {
  /// Creates an outcome.
  const FileUploadOutcome();
}

/// Staged receipt for the upload.
class FileUploadSuccess extends FileUploadOutcome {
  /// Creates a success.
  const FileUploadSuccess(this.receipt);

  /// The staged receipt and durable file reference.
  final FileUploadReceipt receipt;
}

/// Business failure reported by the host route.
class FileUploadFailure extends FileUploadOutcome {
  /// Creates a failure.
  const FileUploadFailure({required this.code, required this.message});

  /// Stable error code.
  final String code;

  /// Human-readable message.
  final String message;
}

/// Session-addressed staged file uploader over the background route.
class FileUploadService {
  /// Creates the service over [client]'s authenticated binary POST.
  const FileUploadService(this._client);

  /// Host RPC client carrying the cookie/bearer handshake.
  final ConnectionClient _client;

  /// Whether the background carrier can be used. Always true: Flutter has
  /// no fixture-page mode that disables it (React `available` gates `?fixture`
  /// pages, which do not exist in the app).
  bool get available => true;

  /// Stores one file for [sessionId].
  ///
  /// Posts exact [bytes] as octet-stream; empty names are omitted from the
  /// query (the host sanitizes the stored leaf name). [onProgress] observes
  /// completion counts only (one-shot POST; wire-chunk progress deferred).
  /// @param sessionId - session owning the staged receipt.
  /// @param bytes - exact file bytes.
  /// @param name - optional display name.
  /// @param onProgress - byte-progress observer called once on success.
  Future<FileUploadOutcome> upload({
    required SessionId sessionId,
    required Uint8List bytes,
    String? name,
    void Function(int loaded, int total)? onProgress,
  }) async {
    final trimmed = name?.trim() ?? '';
    final response = await _client.postBinary(
      kFileUploadPath,
      {
        'sessionId': sessionId.value,
        if (trimmed.isNotEmpty) 'name': trimmed,
      },
      bytes,
      headers: {'content-type': 'application/octet-stream'},
    );
    if (response.statusCode != 200) {
      throw StateError(
        'file upload transport failed with HTTP ${response.statusCode}',
      );
    }
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] is! bool) {
      throw TypeError();
    }
    if (decoded['ok'] == false) {
      final error = decoded['error'];
      final code = error is Map ? error['code'] : null;
      final message = error is Map ? error['message'] : null;
      if (code is! String || message is! String) throw TypeError();
      return FileUploadFailure(code: code, message: message);
    }
    final receipt = FileUploadReceipt.parseSuccess(decoded);
    onProgress?.call(bytes.length, bytes.length);
    return FileUploadSuccess(receipt);
  }
}
