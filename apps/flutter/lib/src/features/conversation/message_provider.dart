import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';

/// Message role — mirrors `assistant/message`, `user/message`, `tool/result`.
enum MessageRole { user, assistant, system, tool }

/// Citation reference inside a message.
class Citation {
  /// Citation label e.g. "[1]".
  final String label;

  /// Optional url / source id.
  final String? url;

  /// Optional title.
  final String? title;

  /// Creates a citation.
  const Citation({required this.label, this.url, this.title});
}

/// UI-classified assistant block — mirrors `AssistantBlock` in
/// `packages/client/runtime/src/client/sessions/conversation.ts`.
class AssistantBlock {
  final String kind; // 'text' | 'reasoning' | 'tool-call' | 'other'
  final String? text;
  final String? toolCallId;
  final String? toolName;
  final String? argsRaw;
  final dynamic raw;

  const AssistantBlock.text(String text)
    : kind = 'text',
      text = text,
      toolCallId = null,
      toolName = null,
      argsRaw = null,
      raw = null;
  const AssistantBlock.reasoning(String text)
    : kind = 'reasoning',
      text = text,
      toolCallId = null,
      toolName = null,
      argsRaw = null,
      raw = null;
  const AssistantBlock.toolCall({
    required String callId,
    required String name,
    required String argsRaw,
  }) : kind = 'tool-call',
       text = null,
       toolCallId = callId,
       toolName = name,
       argsRaw = argsRaw,
       raw = null;
  const AssistantBlock.other(this.raw)
    : kind = 'other',
      text = null,
      toolCallId = null,
      toolName = null,
      argsRaw = null;
}

/// Renderable message — projection of [HistoryEntry] / session log.
///
/// Extended to cover non-message Chat Nodes (retry, turn-error) so
/// `MessageList` can render the same disclosure surfaces as web
/// `MessageItem.tsx:ModelRetryItem` / `TurnErrorItem`. Retained as a
/// single `Message` type to keep `messageListProvider` stable for tests;
/// new fields are nullable and ignored by existing `role==user/assistant` paths.
class Message {
  /// Stable id (seq or synthetic).
  final String id;

  /// Role.
  final MessageRole role;

  /// Markdown body.
  final String content;

  /// Citations extracted from `view` / model output.
  final List<Citation> citations;

  /// Wall time ms since epoch.
  final int time;

  /// Whether streaming is still in progress for this message.
  final bool streaming;

  /// Image attachments for user messages (from `content` blocks with `type: 'image'`).
  final List<String> imageUrls;

  /// Assistant blocks for rich rendering (text / reasoning / tool-call).
  /// Only set for `role == assistant` when the host's `content` array
  /// was available; otherwise `content` holds the plain text fallback.
  final List<AssistantBlock>? blocks;

  /// Retry disclosure — non-null only for `llm/retry` nodes (mirrors `ModelRetryNode`).
  final int? retry;
  final int? maxRetries;
  final int? delayMs;
  final String? failureMessage;
  final String? retryMode;

  /// Whether this message is a retry disclosure (vs user/assistant).
  bool get isRetry => retry != null;

  /// Creates a message.
  const Message({
    required this.id,
    required this.role,
    required this.content,
    this.citations = const [],
    required this.time,
    this.streaming = false,
    this.imageUrls = const [],
    this.blocks,
    this.retry,
    this.maxRetries,
    this.delayMs,
    this.failureMessage,
    this.retryMode,
  });
}

/// Decode history entries into [Message]s for UI.
///
/// Handles `user/message`, `assistant/message`, `assistant/chunk`, `tool/*`
/// opaquely: unknown types become system notes so the list never drops data.
///
/// `isRunning` mirrors `ConversationSnapshot.running` — when true and the
/// tail is an `assistant/chunk` buffer not yet flushed by an
/// `assistant/message`, the buffer is emitted as a `streaming: true` message
/// so the UI shows the partial immediately (like React's `PartialAssistant`).
List<Message> messagesFromHistory(
  List<HistoryEntry> entries, {
  bool isRunning = false,
}) {
  final List<Message> out = <Message>[];
  final StringBuffer assistantBuffer = StringBuffer();
  int? assistantSeq;
  int? assistantTime;

  void flushAssistant({bool streaming = false}) {
    if (assistantBuffer.isEmpty) return;
    out.add(
      Message(
        id: 'assistant-${assistantSeq ?? out.length}',
        role: MessageRole.assistant,
        content: assistantBuffer.toString(),
        time: assistantTime ?? DateTime.now().millisecondsSinceEpoch,
        streaming: streaming,
      ),
    );
    assistantBuffer.clear();
    assistantSeq = null;
    assistantTime = null;
  }

  for (final HistoryEntry entry in entries) {
    final SessionEvent event = entry.event;
    final String type = event.type;
    if (type == 'user/message') {
      flushAssistant();
      final String text = _unescapeHtml(_extractText(event.data));
      // Extract image urls from content blocks
      final List<String> imageUrls = [];
      final dynamic content = event.data['content'];
      if (content is List) {
        for (final dynamic blk in content) {
          if (blk is Map && blk['type'] == 'image') {
            final String? url =
                (blk['attachment'] as Map?)?['url'] as String? ??
                blk['url'] as String?;
            if (url != null) imageUrls.add(url);
          }
        }
      }
      out.add(
        Message(
          id: 'user-${event.seq}',
          role: MessageRole.user,
          content: text.isEmpty ? '(empty message)' : text,
          time: event.time,
          imageUrls: List<String>.unmodifiable(imageUrls),
        ),
      );
    } else if (type == 'assistant/message') {
      // Streaming buffer is superseded by the final message — clear without
      // emitting a duplicate. The `assistant/chunk` already populated the
      // buffer for live `isRunning:true` streaming, but the final `message`
      // carries the complete `content` (reasoning+text) as `blocks`.
      assistantBuffer.clear();
      assistantSeq = null;
      assistantTime = null;
      // Host shape is {turn,step,message:AssistantMessage{content,...},usage?,interrupted?}
      // (packages/core/session/src/types.ts:262). Older snapshots used {content} directly.
      final Map<String, dynamic> msgData = event.data['message'] is Map
          ? (event.data['message'] as Map).cast<String, dynamic>()
          : event.data;
      final String text = _unescapeHtml(_extractText(msgData));
      final List<Citation> citations = _extractCitations(
        entry.view ?? msgData,
      );
      // Try to preserve structured blocks for rich rendering (text / reasoning / tool-call)
      List<AssistantBlock>? blocks;
      final dynamic rawContent = msgData['content'] ?? event.data['content'];
      if (rawContent is List) {
        final List<AssistantBlock> b = [];
        for (final dynamic blk in rawContent) {
          if (blk is Map) {
            final String? t = blk['type'] as String?;
            if (t == 'text' && blk['text'] is String) {
              b.add(AssistantBlock.text(_unescapeHtml(blk['text'] as String)));
            } else if (t == 'reasoning' && blk['text'] is String) {
              b.add(
                AssistantBlock.reasoning(_unescapeHtml(blk['text'] as String)),
              );
            } else if (t == 'tool-call') {
              final String callId =
                  (blk['id'] as String?) ??
                  (blk['callId'] as String?) ??
                  'call-${event.seq}';
              final String name = (blk['name'] as String?) ?? 'tool';
              final String argsRaw =
                  (blk['arguments'] as String?) ??
                  (blk['args'] as String?) ??
                  '';
              b.add(
                AssistantBlock.toolCall(
                  callId: callId,
                  name: name,
                  argsRaw: argsRaw,
                ),
              );
            } else if (t == 'image') {
              b.add(AssistantBlock.other(blk));
            } else {
              b.add(AssistantBlock.other(blk));
            }
          }
        }
        if (b.isNotEmpty) blocks = List<AssistantBlock>.unmodifiable(b);
      }
      out.add(
        Message(
          id: 'assistant-${event.seq}',
          role: MessageRole.assistant,
          content: text,
          citations: citations,
          time: event.time,
          blocks: blocks,
        ),
      );
    } else if (type == 'assistant/chunk') {
      // New StreamChunk shape (packages/core/session/src/types.ts:251):
      // {turn,step,chunk:{type:'block-start'|'block-end'|'usage'|'finish', ...}}
      // Old shape was {delta|chunk|text: string|{type,text}} — keep backward compat.
      final dynamic rawChunk = event.data['chunk'] ?? event.data['delta'] ?? event.data['text'] ?? event.data['block'];
      String delta = '';
      String? deltaType;
      if (rawChunk is String) {
        delta = rawChunk;
      } else if (rawChunk is Map) {
        final m = rawChunk.cast<String, dynamic>();
        final String? t = m['type'] as String?;
        if (t == 'block-start') {
          // No text yet — just a marker, ignore for buffer.
          continue;
        } else if (t == 'block-end') {
          final block = m['block'] as Map?;
          if (block is Map) {
            final bm = block.cast<String, dynamic>();
            deltaType = bm['type'] as String?;
            delta = _asString(bm['text']) ?? '';
            // Fallback: block may be {type:'text', text:...} or {type:'reasoning',...}
            if (delta.isEmpty) delta = _asString(m['text']) ?? '';
          } else {
            delta = _asString(m['text']) ?? '';
            deltaType = t;
          }
        } else if (t == 'usage' || t == 'finish') {
          // No visible text.
          continue;
        } else if (t == 'reasoning' && m['text'] is String) {
          deltaType = 'reasoning';
          delta = _asString(m['text']) ?? '';
        } else if (t == 'text' && m['text'] is String) {
          deltaType = 'text';
          delta = _asString(m['text']) ?? '';
        } else {
          // Legacy: {type:'text', text} or {delta, content}
          deltaType = t;
          delta = _asString(m['text']) ??
              _asString(m['delta']) ??
              _asString(m['content']) ??
              _asString(m['block']) ??
              '';
          if (delta.isEmpty && m['block'] is Map) {
            final bm = (m['block'] as Map).cast<String, dynamic>();
            deltaType = bm['type'] as String? ?? deltaType;
            delta = _asString(bm['text']) ?? '';
          }
        }
      } else {
        delta = _asString(rawChunk) ?? '';
      }
      if (delta.isEmpty) continue;
      if (assistantSeq == null) {
        assistantSeq = event.seq;
        assistantTime = event.time;
      }
      if (deltaType == 'reasoning') {
        assistantBuffer.write(delta);
      } else {
        assistantBuffer.write(delta);
      }
    } else if (type == 'llm/retry') {
      flushAssistant();
      final Map<String, dynamic> data = event.data;
      final int retry = (data['retry'] as num?)?.toInt() ?? 0;
      final int maxRetries = (data['maxRetries'] as num?)?.toInt() ?? 0;
      final int delayMs = (data['delayMs'] as num?)?.toInt() ?? 0;
      final dynamic failure = data['failure'];
      String failureMsg = '';
      if (failure is Map) {
        failureMsg =
            _asString((failure as Map).cast<String, dynamic>()['message']) ??
            failure.toString();
      } else if (failure != null) {
        failureMsg = failure.toString();
      }
      final String mode = _asString(data['mode']) ?? 'normal';
      out.add(
        Message(
          id: 'retry-${event.seq}',
          role: MessageRole.system,
          content: '',
          time: event.time,
          retry: retry,
          maxRetries: maxRetries,
          delayMs: delayMs,
          failureMessage: _unescapeHtml(failureMsg),
          retryMode: mode,
        ),
      );
    } else if (type == 'llm/retry-started') {
      // Transition after retry delay — no visible row in web (state becomes 'started'); skip.
      continue;
    } else if (type == 'turn/error') {
      flushAssistant();
      final String msg = _unescapeHtml(
        _asString(event.data['message']) ?? event.data.toString(),
      );
      final String? code = _asString(event.data['code']);
      out.add(
        Message(
          id: 'turn-error-${event.seq}',
          role: MessageRole.system,
          content: code != null ? '$msg ($code)' : msg,
          time: event.time,
        ),
      );
    } else if (type == 'turn/end') {
      // A failed turn closes with `reason.kind == 'error'` and no
      // `assistant/message`; surface the failure like web's TurnErrorItem.
      // A successful turn/end renders nothing.
      final dynamic reason = event.data['reason'];
      if (reason is Map && reason['kind'] == 'error') {
        flushAssistant();
        final dynamic err = reason['error'];
        String msg = err is Map
            ? (_asString((err as Map).cast<String, dynamic>()['message']) ?? '')
            : (_asString(err) ?? '');
        if (msg.isEmpty) msg = 'Turn failed';
        out.add(
          Message(
            id: 'turn-error-${event.seq}',
            role: MessageRole.system,
            content: _unescapeHtml(msg),
            time: event.time,
          ),
        );
      }
      continue;
    } else if (type.startsWith('tool/')) {
      flushAssistant();
      // Tool events are rendered via ToolCallTree; still emit a stub so
      // message count matches log during debugging.
      continue;
    } else {
      // Unknown — flush any pending assistant text then emit system note
      // when view contains human-readable content. Otherwise skip.
      final String text = _unescapeHtml(_extractText(event.data));
      if (text.isNotEmpty) {
        flushAssistant();
        out.add(
          Message(
            id: 'system-${event.seq}',
            role: MessageRole.system,
            content: text,
            time: event.time,
          ),
        );
      }
    }
  }
  flushAssistant(streaming: isRunning);
  return List<Message>.unmodifiable(out);
}

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is SessionId) return v.value;
  if (v is WorkspaceId) return v.value;
  // For other extension types that wrap String, fall back to toString only if it looks like a plain value
  // Avoid Map's toString.
  if (v is Map || v is List) return null;
  try {
    final String s = v.toString();
    // Heuristic: if toString is the default Object toString for extension types, it will be the underlying string
    // For SessionId/WorkspaceId, toString returns the string value; for other objects it returns Instance...
    if (s.startsWith('Instance of')) return null;
    return s;
  } catch (_) {
    return null;
  }
}

String _extractText(Map<String, dynamic> data) {
  // Try common shapes: `content` (string or block array), `text`, `message`.
  final dynamic content = data['content'];
  if (content is String) return content;
  if (content is List) {
    final StringBuffer buf = StringBuffer();
    for (final dynamic block in content) {
      if (block is Map) {
        final String? t =
            _asString(block['text']) ?? _asString(block['content']);
        if (t != null) buf.writeln(t);
      } else if (block is String) {
        buf.writeln(block);
      } else {
        final String? s = _asString(block);
        if (s != null) buf.writeln(s);
      }
    }
    final String s = buf.toString().trim();
    if (s.isNotEmpty) return s;
  }
  final String? text =
      _asString(data['text']) ??
      _asString(data['message']) ??
      _asString(data['delta']);
  if (text != null) return text;
  return '';
}

/// Decode HTML entities that the host may have escaped in text blocks (e.g. `&quot;hi&quot;`).
/// Web's `MessageText` does this via the browser's innerHTML; Flutter must do it manually.
String _unescapeHtml(String input) {
  return input
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/');
}

List<Citation> _extractCitations(Map<String, dynamic> view) {
  final dynamic raw = view['citations'] ?? view['sources'];
  if (raw is List) {
    return raw.whereType<Map>().map((Map<dynamic, dynamic> e) {
      final m = e.cast<String, dynamic>();
      final String label = _asString(m['label']) ?? _asString(m['id']) ?? '[?]';
      return Citation(
        label: label,
        url: _asString(m['url']),
        title: _asString(m['title']),
      );
    }).toList();
  }
  return const [];
}

/// Provider for messages of a session.
///
/// Per CURRENT master, conversation history comes from the `session/follow`
/// snapshot (via `liveHistoryProvider` → `live_sync.openFollowFor`), not from
/// `session/page`. React parity: `RemoteJournalStream.open()` yields the follow
/// snapshot `cursor+records+hasMore` and never HTTP `session/page` on open
/// (`packages/api/session-controller/src/client/transport.ts:133` +
/// `packages/api/gateway/src/client/journal-stream.ts:149`). Flutter previously
/// did 2× `session/page` per open (`LiveHistory.build` microtask +
/// `messageListProvider` fallback), which saturated the browser 6-conn limit
/// and left `session/prompt` queued behind pending `page` — see the 25-pending
/// screenshot bug. Now this provider is a pure view of `liveHistory` (0 HTTP
/// on open); an explicit `getSessionEvents` remains for `loadOlder` and
/// offline tests but is not auto-invoked.
final messageListProvider = FutureProvider.family<List<Message>, String>((
  ref,
  sessionId,
) async {
  // Initial history is solely the `session/follow` snapshot
  // (`liveHistoryProvider` ← `live_sync.openFollowFor` `replaceAllWithCursor`).
  // No HTTP `session/page` fallback: when the snapshot has not yet arrived
  // (mux reconnect/backoff) the conversation legitimately shows empty until
  // the authoritative window lands, matching React `SessionEventStream`.
  final live = ref.watch(liveHistoryProvider(sessionId));
  if (live.isNotEmpty) return messagesFromHistory(live);
  return const <Message>[];
});

/// Live history window for a session — holds the event list and updates
/// from the mux stream via `liveSyncProvider`.
///
/// Mirrors `Session.events` + `RemoteJournalStream` in
/// `packages/client/runtime/src/client/sessions/session.ts` + `gateway/.../journal-stream.ts`.
/// History is **solely** sourced from `session/follow` snapshot (`liveSync.openFollowFor`
/// `replaceAll`); there is no HTTP `session/page` on open — matching React's
/// `Session.doOpen() → SessionEventStream.open({maxMessages:50})` which yields
/// the follow snapshot and never `readPage`. The previous `Future.microtask` fallback
/// (`getSessionEvents` → `getSessions()+page`) caused the double-fetch storm
/// (2× `session/page` per open, 25 pending in screenshot) and is removed.
/// Whether older history remains before the current window.
///
/// Mirrors `SessionSnapshot.hasMore` from `packages/api/session-controller`.
final liveHasMoreProvider = StateProvider.family<bool, String>((ref, _) => false);

/// Whether a `loadOlder` page fetch is in flight.
///
/// Mirrors `SessionSnapshot.loadingOlder`.
final liveLoadingOlderProvider = StateProvider.family<bool, String>((ref, _) => false);

class LiveHistory extends FamilyNotifier<List<HistoryEntry>, String> {
  /// Accepted cursor from the latest follow snapshot. Events with `seq` <=
  /// this cursor are already represented by the snapshot and must be ignored
  /// on live append (CURRENT master sequence identity rule).
  int _acceptedSeq = -1;

  /// Last cursor value received from `session/follow` snapshot, or -1 if none.
  int get acceptedSeq => _acceptedSeq;

  /// Whether older history remains before the current window.
  bool get hasMore => ref.read(liveHasMoreProvider(arg));

  /// Whether a `loadOlder` page fetch is in flight.
  bool get loadingOlder => ref.read(liveLoadingOlderProvider(arg));

  @override
  List<HistoryEntry> build(String arg) {
    _acceptedSeq = -1;
    // Reset paging flags when the provider is (re)created for a session.
    Future.microtask(() {
      try {
        ref.read(liveHasMoreProvider(arg).notifier).state = false;
        ref.read(liveLoadingOlderProvider(arg).notifier).state = false;
      } catch (_) {}
    });
    return const <HistoryEntry>[];
  }

  /// Append a live `HistoryEntry` (from `session/event` mux frame).
  ///
  /// Gap vs duplicate is checked like `journal-stream.ts:284 acceptEntry`:
  /// `seq <= acceptedSeq` or `seq <= tail` → duplicate drop, `seq > tail+1` → gap
  /// (previously `invalidateSelf()` → full tail `session/page` re-fetch storm).
  /// Now we drop with a debug log and let the next `snapshot` (follow reconnect
  /// `replaceAll`) repair, matching React's `replaceThrough` without flooding.
  ///
  /// Also enforces the snapshot cursor fence: if the snapshot established cursor
  /// X, events <= X already represented by snapshot are ignored; only > X are
  /// appended. Implemented via [_acceptedSeq] which is max(cursor, tailMaxSeq).
  void appendLive(HistoryEntry entry) {
    if (entry.event.seq <= _acceptedSeq) {
      // Duplicate or already represented by snapshot cursor — drop
      return;
    }
    final tailSeq = state.isEmpty ? null : state.last.event.seq;
    if (tailSeq != null && entry.event.seq > tailSeq + 1) {
      // Gap — do not storm `session/page`; wait for follow snapshot repair.
      // React would do 1-2 targeted `readPage` via `replaceThrough` while still
      // following; Flutter's follow snapshot already raced and will deliver.
      return;
    }
    if (tailSeq != null && entry.event.seq <= tailSeq) {
      // Duplicate or old event (reconnect replay) — drop
      return;
    }
    state = List<HistoryEntry>.unmodifiable([...state, entry]);
    if (entry.event.seq > _acceptedSeq) _acceptedSeq = entry.event.seq;
  }

  /// Replace the whole window (e.g., from `session/follow` snapshot).
  void replaceAll(List<HistoryEntry> entries) {
    state = List<HistoryEntry>.unmodifiable(entries);
    _acceptedSeq = entries.isEmpty
        ? _acceptedSeq
        : entries.last.event.seq > _acceptedSeq
        ? entries.last.event.seq
        : _acceptedSeq;
  }

  /// Replace with explicit cursor fence from follow snapshot.
  void replaceAllWithCursor(List<HistoryEntry> entries, int cursor) {
    state = List<HistoryEntry>.unmodifiable(entries);
    final int maxSeq = entries.isEmpty ? cursor : entries.last.event.seq;
    _acceptedSeq = cursor > maxSeq ? cursor : maxSeq;
    // Also ensure _acceptedSeq at least cursor even if entries empty (window gap).
    if (cursor > _acceptedSeq) _acceptedSeq = cursor;
  }

  /// Snapshot-aware replace that also records `hasMore`.
  void replaceAllWithCursorAndHasMore(
    List<HistoryEntry> entries,
    int cursor,
    bool hasMore,
  ) {
    state = List<HistoryEntry>.unmodifiable(entries);
    final int maxSeq = entries.isEmpty ? cursor : entries.last.event.seq;
    _acceptedSeq = cursor > maxSeq ? cursor : maxSeq;
    if (cursor > _acceptedSeq) _acceptedSeq = cursor;
    ref.read(liveHasMoreProvider(arg).notifier).state = hasMore;
  }

  /// Explicitly set `hasMore` (e.g., from `session/follow` snapshot).
  void setHasMore(bool value) {
    ref.read(liveHasMoreProvider(arg).notifier).state = value;
  }

  /// Prepend one older history page and update `hasMore`.
  void prependOlder(List<HistoryEntry> older, bool hasMore) {
    if (older.isEmpty) {
      ref.read(liveHasMoreProvider(arg).notifier).state = hasMore;
      return;
    }
    state = List<HistoryEntry>.unmodifiable([...older, ...state]);
    ref.read(liveHasMoreProvider(arg).notifier).state = hasMore;
  }

  /// Pull one older history page with re-entry guard, mirroring
  /// `Session.loadOlder()` (`session.ts:414`).
  ///
  /// Uses the authoritative snapshot cursor (`_acceptedSeq`) as `throughSeq`
  /// and the first visible seq as `beforeSeq`. No sentinel probe.
  Future<void> loadOlder() async {
    if (ref.read(liveLoadingOlderProvider(arg))) return;
    if (!ref.read(liveHasMoreProvider(arg))) return;
    final int cursor = _acceptedSeq;
    if (cursor < 0) return; // no authoritative cursor yet; wait for snapshot
    if (state.isEmpty) return;
    ref.read(liveLoadingOlderProvider(arg).notifier).state = true;
    try {
      final client = ref.read(connectionClientProvider);
      final int? beforeSeq = state.first.event.seq;
      final result = await client.getSessionHistory(
        SessionId(arg),
        throughSeq: cursor,
        beforeSeq: beforeSeq,
        maxMessages: 50,
      );
      final List<HistoryEntry> entries = result.entries;
      // Host `hasMore` is not returned by `getSessionHistory`'s projection
      // shape; derive from page fullness like React's `hasMore = cut>0`.
      final bool hasMore = entries.length >= 50;
      if (entries.isNotEmpty) {
        prependOlder(entries, hasMore);
      } else {
        ref.read(liveHasMoreProvider(arg).notifier).state = hasMore;
      }
    } catch (_) {
      // Soft fail like React's loadOlder catch — keep window and hasMore
    } finally {
      ref.read(liveLoadingOlderProvider(arg).notifier).state = false;
    }
  }
}

final liveHistoryProvider =
    NotifierProvider.family<LiveHistory, List<HistoryEntry>, String>(
      LiveHistory.new,
    );

/// Optimistic user messages per session — shown immediately after `submit`
/// before the host's `user/message` event arrives via the mux stream.
///
/// Mirrors the web composer's optimistic draft handling: the UI shows the
/// user bubble instantly, then the live `session/event` (seq-gapped) replaces
/// it. Deduplication is by content + recency (host echo within 5s).
final optimisticMessagesProvider = StateProvider.family<List<Message>, String>(
  (ref, sessionId) => const <Message>[],
);

/// Transient agent-level error for a session, set live from the
/// `host/agent-error` host-stream frame (failures with no turn position —
/// e.g. `401 ModelError: model not supported`). Rendered as a banner at the
/// conversation tail; cleared when the session's next turn starts.
final agentErrorProvider = StateProvider.family<String?, String>(
  (ref, sessionId) => null,
);

/// Live message list derived from `liveHistoryProvider` plus `partial` handling.
///
/// Watches the live window and maps via `messagesFromHistory` with streaming
/// support: if the last event is an `assistant/chunk` and the session is
/// still running, the buffered text is emitted as a `streaming: true` message
/// so the UI shows the partial immediately (like React's `PartialAssistant`).
/// React parity: conversation rendering reads the `Session` window (follow
/// snapshot + `appendLive`), not a separate `session/page` fallback. This
/// provider now mirrors that — when `history` is non-empty it folds it;
/// otherwise it returns `[]` (empty until follow snapshot arrives) without
/// touching `messageListProvider`, breaking the `watch(messageListProvider)`
/// → `getSessionEvents` → `session/page` storm chain.
///
/// Merges `optimisticMessagesProvider` (user message shown instantly on submit)
/// with the host-confirmed history, deduplicating when the host echo arrives.
final liveMessageListProvider = Provider.family<List<Message>, String>((
  ref,
  sessionId,
) {
  final history = ref.watch(liveHistoryProvider(sessionId));
  final optimistic = ref.watch(optimisticMessagesProvider(sessionId));
  final isRunning = ref.watch(
    sessionsProvider.select(
      (s) => s.byId[SessionId(sessionId)]?.running ?? false,
    ),
  );
  final List<Message> base = history.isNotEmpty
      ? messagesFromHistory(history, isRunning: isRunning)
      : const <Message>[];
  if (optimistic.isEmpty) return base;
  // Deduplicate optimistic vs host-confirmed by tail only, not global content.
  // Previous global Set dedup incorrectly hid legitimate repeated "hi" across
  // turns (same content in history set). Now we only hide the optimistic when
  // the durable tail is the same user text (echo of the just-sent message),
  // mirroring ChatView tail dedup and React's observedRpcIds atomic swap.
  // This preserves seq-based identity: repeated identical text in separate
  // turns remains visible until its own echo lands.
  if (base.isNotEmpty) {
    final tail = base.last;
    if (tail.role == MessageRole.user) {
      final filteredOptimistic = optimistic
          .where((o) => o.content.trim() != tail.content.trim())
          .toList();
      if (filteredOptimistic.isEmpty) return base;
      return List<Message>.unmodifiable([...base, ...filteredOptimistic]);
    }
  }
  // If tail is not user (assistant/tool between), no echo yet — show optimistic.
  return List<Message>.unmodifiable([...base, ...optimistic]);
});

/// Synchronous demo messages for tests / offline preview when history is
/// empty. Not wired to [messageListProvider] by default — tests override
/// [messageListProvider] with these when they need deterministic content.
const List<Message> kDemoMessages = <Message>[
  Message(
    id: 'demo-1',
    role: MessageRole.user,
    content: 'Hello! Summarize this repo.',
    time: 0,
  ),
  Message(
    id: 'demo-2',
    role: MessageRole.assistant,
    content: 'This is **DeepSeek Harness** — a plugin-based agent harness on vendored Cordis.\n\n- Everything is a plugin\n- Model-visible means logged',
    citations: <Citation>[Citation(label: '[1]', url: 'https://example.com')],
    time: 1,
  ),
];
