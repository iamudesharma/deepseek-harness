import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/session/session_provider.dart';

class SkillRef {
  const SkillRef({
    required this.name,
    this.description,
    this.source,
    this.modelInvocable,
  });
  final String name;
  final String? description;
  final String? source;
  final bool? modelInvocable;
}

/// Real `skill.list` provider — session-addressed.
///
/// Calls `ref.watch(connectionClientProvider).skillList(sessionId: currentSessionId)`
/// and maps `skills` (name/description) to [SkillRef]. Requires a selected
/// session; when none is selected, returns an empty list so the UI can prompt
/// to select a session. No synthetic delay.
final skillListProvider = FutureProvider<List<SkillRef>>((ref) async {
  final client = ref.watch(connectionClientProvider);
  final sessionId = ref.watch(currentSessionIdProvider);
  if (sessionId == null) return const [];
  final value = await client.skillList(sessionId: sessionId.value);
  final skillsRaw = value['skills'] as List<dynamic>? ?? const [];
  return skillsRaw.map((dynamic e) {
    final map = (e as Map).cast<String, dynamic>();
    return SkillRef(
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      source: map['whenToUse'] as String?,
      modelInvocable: map['modelInvocable'] as bool?,
    );
  }).toList();
});

/// Legacy alias — keep for backwards compat, now backed by real host.
///
/// Previously returned synthetic fixtures; now forwards to [skillListProvider]
/// so existing watches still hit the real typert without duplication.
final skillRefsProvider = FutureProvider<List<SkillRef>>((ref) async {
  return ref.watch(skillListProvider.future);
});

final skillQueryProvider = StateProvider<String>((ref) => '');
