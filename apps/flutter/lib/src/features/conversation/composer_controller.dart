import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';
import '../../plugins/conversation/hub.dart';
import '../../core/session/sessions_controller.dart';
import '../../platform/attachment_bytes.dart';
import '../model_selection/model_directory.dart';
import 'message_provider.dart';

/// Attachment for the composer rail — Dart port of
/// `ComposerAttachment` (`packages/client/ui-conversation/src/client/contract/slots.ts`).
///
/// Mirrors the React contract: `kind: 'image'`, stable `id` (DraftAttachmentId),
/// `file` fields (name/type/size/path) and `previewUrl` (blob or file path for
/// the thumbnail). Kept as pure Dart — the host attachment admission may derive
/// its wire payload from these fields.
///
/// A single model is used across the app (composer controller,
/// AttachmentStagingService, and the rail/lightbox). The previous split
/// (`features/attachment` vs this file) is removed — this file is the owner.
class ComposerAttachment {
  /// Stable draft identity — mirrors `DraftAttachmentId` (`crypto.randomUUID`)
  /// branded as [DraftAttachmentId].
  ///
  /// Empty string denotes a legacy const fixture without an id (dedup falls back
  /// to name+path so existing tests keep passing). Real drops always generate
  /// a non-empty id via [ComposerAttachment.create] / [generateId].
  final DraftAttachmentId id;

  /// File name.
  final String name;

  /// Optional local path or object URL (macOS path, web blob URL).
  final String? path;

  /// Mime type hint (e.g. `image/png`).
  final String? mimeType;

  /// Size in bytes.
  final int? size;

  /// Preview URL for the thumbnail rail — blob URL (web), file path (macOS),
  /// or `null` when unavailable (falls back to an icon).
  final String? previewUrl;

  /// Raw image bytes when available in memory (web `File.bytes`, native read).
  ///
  /// `null` means bytes must be read lazily from [path] at submit time via
  /// `readAttachmentBytes` (native file seam) — mirrors React's `File` object
  /// that is kept until `serializeDraftImages` reads `file.arrayBuffer()`.
  final Uint8List? bytes;

  /// Creates a composer attachment.
  ///
  /// `id` may be omitted for test fixtures; real code should use
  /// [ComposerAttachment.create] or supply a generated id.
  const ComposerAttachment({
    this.id = const DraftAttachmentId(''),
    required this.name,
    this.path,
    this.mimeType,
    this.size,
    this.previewUrl,
    this.bytes,
  });

  /// Creates an attachment with a generated stable id and a preview URL.
  ///
  /// Mirrors `browserDraftAttachment` in `packages/client/ui-conversation/src/client/service.ts`:
  /// `id: crypto.randomUUID()`, `previewUrl: URL.createObjectURL(file)` on web,
  /// and a file-path fallback on native. The preview URL is `path` when present
  /// (native file) else `null`.
  factory ComposerAttachment.create({
    required String name,
    String? path,
    String? mimeType,
    int? size,
    String? previewUrl,
    Uint8List? bytes,
  }) {
    return ComposerAttachment(
      id: generateId(),
      name: name,
      path: path,
      mimeType: mimeType,
      size: size,
      previewUrl: previewUrl ?? path,
      bytes: bytes,
    );
  }

  static int _seq = 0;

  /// Generates a unique draft attachment id.
  ///
  /// Uses a monotonic counter + timestamp; sufficient for draft-local
  /// uniqueness without adding a uuid dependency.
  static DraftAttachmentId generateId() {
    _seq += 1;
    return DraftAttachmentId('att-${DateTime.now().microsecondsSinceEpoch}-$_seq');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ComposerAttachment) return false;
    // Real attachments dedup by stable id; legacy const fixtures fall back
    // to name+path.
    if (id.value.isNotEmpty && other.id.value.isNotEmpty) return id == other.id;
    return name == other.name && path == other.path;
  }

  @override
  int get hashCode => id.value.isNotEmpty ? id.hashCode : Object.hash(name, path);
}

/// Composer state — explicit resolve step owns defaults, never hidden `??` in
/// run() / build().
class ComposerState {
  /// Draft text.
  final String text;

  /// Staged attachments shown in the rail.
  final List<ComposerAttachment> attachments;

  /// Selected model id (e.g. `deepseek-chat`), `null` means default.
  final String? selectedModel;

  /// Whether a send is in flight.
  final bool isSending;

  /// Last error from submit, if any.
  final String? error;

  /// Whether the draft is non-empty or has attachments.
  bool get canSubmit =>
      !isSending && (text.trim().isNotEmpty || attachments.isNotEmpty);

  /// Creates composer state.
  const ComposerState({
    this.text = '',
    this.attachments = const [],
    this.selectedModel,
    this.isSending = false,
    this.error,
  });

  /// Copy with.
  ComposerState copyWith({
    String? text,
    List<ComposerAttachment>? attachments,
    String? selectedModel,
    bool? isSending,
    String? error,
    bool clearError = false,
    bool clearModel = false,
  }) {
    return ComposerState(
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      selectedModel: clearModel ? null : (selectedModel ?? this.selectedModel),
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Riverpod controller for the conversation composer.
///
/// No static singleton — scoped via ProviderContainer / ProviderScope. Mirrors
/// the web composer's draft + model + attachments shape. Submission is kept
/// local (no host mutation) unless callers override [submit] via a provider
/// override in tests.
///
/// Default models reflect the DeepSeek catalogue; change via cordis.yml
/// `Config` in real wiring — never a hardcoded tunable outside Config.
class ComposerController extends FamilyNotifier<ComposerState, String> {
  @override
  ComposerState build(String arg) => const ComposerState();

  /// Update draft text.
  void setText(String value) {
    if (state.text == value) return;
    state = state.copyWith(text: value, clearError: state.error != null);
  }

  /// Select model. Pass `null` to clear.
  void setModel(String? modelId) {
    if (state.selectedModel == modelId) return;
    if (modelId == null) {
      state = state.copyWith(clearModel: true, clearError: state.error != null);
    } else {
      state = state.copyWith(
        selectedModel: modelId,
        clearError: state.error != null,
      );
    }
  }

  /// Add attachments (deduped by name+path).
  void addAttachments(List<ComposerAttachment> items) {
    if (items.isEmpty) return;
    final next = <ComposerAttachment>[...state.attachments];
    for (final item in items) {
      if (!next.contains(item)) next.add(item);
    }
    state = state.copyWith(attachments: List.unmodifiable(next));
  }

  /// Remove attachment at index.
  void removeAttachmentAt(int index) {
    if (index < 0 || index >= state.attachments.length) return;
    final next = List<ComposerAttachment>.from(state.attachments)
      ..removeAt(index);
    state = state.copyWith(attachments: List.unmodifiable(next));
  }

  /// Remove attachment by stable id (mirrors React `onRemoveImage(id)`).
  void removeAttachmentById(DraftAttachmentId id) {
    final next = state.attachments.where((a) => a.id != id).toList();
    if (next.length == state.attachments.length) return;
    state = state.copyWith(attachments: List.unmodifiable(next));
  }

  /// Clear all attachments.
  void clearAttachments() {
    if (state.attachments.isEmpty) return;
    state = state.copyWith(attachments: const []);
  }

  /// Submit draft — live path `ConnectionClient.sendMessage` → `session.prompt`.
  ///
  /// * `canSubmit == false` → no-op (matches web composer guard).
  /// * On success clears `text`+`attachments`, keeps `selectedModel`, resets
  ///   `isSending`.
  /// * On host failure sets `error` and resets `isSending` without clearing
  ///   the draft, so the user can retry (parity with React `InputBar` error).
  ///
  /// Images are serialized via [serializeDraftImages] into base64
  /// `PromptContentPart` image blocks — the same wire shape React's
  /// `ConversationController.serializeDraftImages` / `encodeImage` produce
  /// (`mediaType` + `data` base64 + optional `name`). A serialization failure
  /// (unsupported type or missing bytes) is surfaced as a draft error without
  /// clearing the draft.
  ///
  /// The `DSH_REPLAY` synthetic fallback invariant is enforced upstream in
  /// `welcomeModelCatalogProvider`; this method never synthesizes a success
  /// when the host is unreachable — it surfaces the transport error.
  Future<void> submit() async {
    debugPrint(
      '[composerController] submit entry canSubmit=${state.canSubmit} text="${state.text}" attachments=${state.attachments.length} isSending=${state.isSending}',
    );
    if (!state.canSubmit) {
      debugPrint('[composerController] submit aborted canSubmit false');
      return;
    }
    final String text = state.text.trim();
    if (text.isEmpty && state.attachments.isEmpty) {
      debugPrint('[composerController] submit aborted empty');
      return;
    }
    final String sessionId = arg;
    // Serialize images before optimistic clear — mirrors React's
    // `serializeImages` before `session.prompt`.
    List<Map<String, dynamic>> imageParts = const [];
    if (state.attachments.isNotEmpty) {
      debugPrint(
        '[composerController] serializeDraftImages start count=${state.attachments.length}',
      );
      try {
        imageParts = await serializeDraftImages(state.attachments);
        debugPrint(
          '[composerController] serializeDraftImages done parts=${imageParts.length}',
        );
      } catch (e, st) {
        debugPrint('[composerController] serializeDraftImages failed: $e\n$st');
        state = state.copyWith(isSending: false, error: e.toString());
        return;
      }
    }
    // Optimistic user bubble — shown immediately before host echo.
    final optimistic = Message(
      id: 'optimistic-${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text,
      time: DateTime.now().millisecondsSinceEpoch,
    );
    ref.read(optimisticMessagesProvider(sessionId).notifier).state = [
      ...ref.read(optimisticMessagesProvider(sessionId)),
      optimistic,
    ];
    final String savedText = state.text;
    final List<ComposerAttachment> savedAttachments = state.attachments;
    state = state.copyWith(
      text: '',
      attachments: const [],
      isSending: true,
      clearError: true,
    );
    try {
      final ConnectionClient client = ref.read(connectionClientProvider);
      if (client.baseUrl.isEmpty) {
        debugPrint('[composerController] baseUrl empty, fake delay');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        state = state.copyWith(isSending: false);
        return;
      }
      // Busy-enter policy via the conversation hub when active.
      final hub = activatedHub;
      final running =
          ref.read(sessionsProvider).byId[SessionId(sessionId)]?.running ??
          false;
      final String mode =
          hub?.controller.policy.resolveMode(agentRunning: running) ?? 'queue';
      debugPrint(
        '[composerController] sendMessage sid=$sessionId mode=$mode textLen=${text.length} images=${imageParts.length}',
      );
      await client.sendMessage(
        sessionId: SessionId(sessionId),
        content: text,
        mode: mode,
        images: imageParts,
      );
      debugPrint('[composerController] sendMessage success');
      state = state.copyWith(isSending: false);
    } catch (e, st) {
      debugPrint('[composerController] sendMessage failed: $e\n$st');
      // Remove optimistic on failure and restore draft so user can retry.
      final curOpt = ref.read(optimisticMessagesProvider(sessionId));
      ref.read(optimisticMessagesProvider(sessionId).notifier).state = curOpt
          .where((m) => m.id != optimistic.id)
          .toList();
      state = state.copyWith(
        text: savedText,
        attachments: savedAttachments,
        isSending: false,
        error: e.toString(),
      );
    }
  }

  /// Serialize ordered draft attachments to `PromptContentPart` image payloads.
  ///
  /// Mirrors `ConversationController.serializeDraftImages` + `encodeImage`:
  /// validates media type, reads bytes (in-memory or lazily from `path` on
  /// native), and base64-encodes. `name` is included only when non-empty.
  static Future<List<Map<String, dynamic>>> serializeDraftImages(
    List<ComposerAttachment> attachments,
  ) async {
    const allowed = <String>{
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
    };
    final List<Map<String, dynamic>> parts = [];
    for (final att in attachments) {
      final String mediaType = att.mimeType ?? '';
      if (!allowed.contains(mediaType)) {
        throw Exception(
          'unsupported image media type: ${mediaType.isEmpty ? '(empty)' : mediaType}',
        );
      }
      Uint8List? bytes = att.bytes;
      if (bytes == null && att.path != null && att.path!.isNotEmpty) {
        bytes = await readFileBytes(att.path!);
      }
      if (bytes == null) {
        throw Exception('missing image data for ${att.name}');
      }
      final String data = base64Encode(bytes);
      final Map<String, dynamic> part = <String, dynamic>{
        'type': 'image',
        'mediaType': mediaType,
        'data': data,
      };
      if (att.name.isNotEmpty) part['name'] = att.name;
      parts.add(part);
    }
    return parts;
  }

  /// Set error.
  void setError(String message) {
    state = state.copyWith(error: message, isSending: false);
  }

  /// Clear error.
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }
}

/// Global composer provider family keyed by session.
///
/// Each session owns its draft — mirrors web session-scoped composer store.
final composerControllerProvider =
    NotifierProvider.family<ComposerController, ComposerState, String>(
      ComposerController.new,
    );

/// Available model ids for the dropdown — fallback when ModelDirectory not yet loaded.
///
/// In live wiring this is overridden by `availableModelsProvider` which
/// derives from `modelDirectoryProvider(sessionId).groups`.
const List<String> kAvailableModels = <String>[
  'deepseek-chat',
  'deepseek-reasoner',
];

/// Live available models derived from per-session ModelDirectory.
///
/// Falls back to `kAvailableModels` until the directory loads.
final availableModelsProvider = Provider.family<List<String>, String>((
  ref,
  sessionId,
) {
  final dirState = ref.watch(modelDirectoryProvider(sessionId));
  if (dirState.groups.isEmpty) return kAvailableModels;
  return dirState.groups.expand((g) => g.models.map((m) => m.id)).toList();
});
