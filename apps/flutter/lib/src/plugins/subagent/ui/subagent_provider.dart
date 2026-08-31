import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../features/conversation/message_provider.dart' show liveHistoryProvider;

/// Minimal subagent view — mirrors the catalog row shape `SubagentCatalogAction`
/// renders while its authoritative snapshot hydrates (label, running bit,
/// parent lineage from the shared sessions list).
class SubagentView {
  /// Stable subagent id.
  final String id;

  /// Parent session id that spawned this subagent.
  final String parentSessionId;

  /// Display label / task.
  final String label;

  /// Whether the subagent is still running.
  final bool running;

  /// Child session title when the host projection carries one.
  final String? preview;

  /// Wall time ms.
  final int updatedAt;

  /// Creates a subagent view.
  const SubagentView({
    required this.id,
    required this.parentSessionId,
    required this.label,
    required this.running,
    this.preview,
    required this.updatedAt,
  });
}

/// Transcript line for a subagent child session, folded from the child's
/// durable event window (`user/message` / `assistant/message` / `tool/call`).
class SubagentTranscriptEntry {
  /// Line id (event seq).
  final String id;

  /// Role — `user` | `assistant` | `tool`.
  final String role;

  /// Text content.
  final String content;

  /// Wall time ms.
  final int time;

  /// Creates an entry.
  const SubagentTranscriptEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.time,
  });
}

/// Subagent children of [parentSessionId] — derived from the shared sessions
/// list (`origin == 'subagent'`, oldest first), the same summary-known shape
/// React renders while the descriptor-backed catalog hydrates. No fixtures:
/// an unconnected boot shows the empty state, never invented rows.
final subagentsFamilyProvider = Provider.family<List<SubagentView>, String>((
  ref,
  parentSessionId,
) {
  final SessionsState sessions = ref.watch(sessionsProvider);
  final List<SubagentView> children =
      sessions.byId.values
          .where(
            (s) =>
                s.origin == 'subagent' &&
                s.parentSessionId != null &&
                s.parentSessionId!.value == parentSessionId,
          )
          .map(
            (s) => SubagentView(
              id: s.sessionId.value,
              parentSessionId: parentSessionId,
              label: s.title ?? s.sessionId.value,
              running: s.running,
              updatedAt: s.updatedAt,
            ),
          )
          .toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return children;
});

/// Legacy alias over the current session's children so existing watches keep
/// compiling; new code should watch [subagentsFamilyProvider] with the
/// screen's own parent id.
final subagentsProvider = Provider<List<SubagentView>>((ref) {
  final String? current = ref.watch(currentSessionIdProvider)?.value;
  if (current == null) return const [];
  return ref.watch(subagentsFamilyProvider(current));
});

/// First text line of one event payload (content string, block list, or
/// bare `text`/`message` field).
String _eventText(Map<String, dynamic> data) {
  final dynamic content = data['content'];
  if (content is String && content.isNotEmpty) return content;
  if (content is List) {
    for (final block in content) {
      if (block is Map) {
        final String? t =
            block['text'] as String? ?? block['content'] as String?;
        if (t != null && t.isNotEmpty) return t;
      } else if (block is String && block.isNotEmpty) {
        return block;
      }
    }
  }
  return (data['text'] as String?) ??
      (data['message'] as String?) ??
      (data['prompt'] as String?) ??
      '';
}

/// Folds one history window into transcript rows in event order.
List<SubagentTranscriptEntry> transcriptFromHistory(
  List<HistoryEntry> entries,
) {
  final List<SubagentTranscriptEntry> rows = [];
  for (final HistoryEntry entry in entries) {
    switch (entry.event.type) {
      case 'user/message':
        final String text = _eventText(entry.event.data);
        if (text.isNotEmpty) {
          rows.add(
            SubagentTranscriptEntry(
              id: '${entry.event.seq}',
              role: 'user',
              content: text,
              time: entry.event.time,
            ),
          );
        }
      case 'assistant/message':
        final String text = _eventText(entry.event.data);
        if (text.isNotEmpty) {
          rows.add(
            SubagentTranscriptEntry(
              id: '${entry.event.seq}',
              role: 'assistant',
              content: text,
              time: entry.event.time,
            ),
          );
        }
      case 'tool/call':
        final String name = entry.event.data['name'] as String? ?? 'tool';
        rows.add(
          SubagentTranscriptEntry(
            id: '${entry.event.seq}',
            role: 'tool',
            content: name,
            time: entry.event.time,
          ),
        );
    }
  }
  return rows;
}

/// Transcript of one subagent child session — read from the child's
/// authoritative `liveHistoryProvider` (session/follow snapshot), not
/// `session/page` probe. When the child's follow snapshot has not yet
/// arrived the transcript is empty until the window lands.
final subagentTranscriptProvider =
    FutureProvider.family<List<SubagentTranscriptEntry>, String>((
      ref,
      childSessionId,
    ) async {
      final live = ref.watch(liveHistoryProvider(childSessionId));
      if (live.isEmpty) return const <SubagentTranscriptEntry>[];
      return transcriptFromHistory(live);
    });

/// Selected subagent id — null means list view.
final selectedSubagentProvider = StateProvider<String?>((ref) => null);
