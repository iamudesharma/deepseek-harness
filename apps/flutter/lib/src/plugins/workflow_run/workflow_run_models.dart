/// Durable workflow-run renderer data — the Dart slice of
/// `packages/client/ui-workflow-run/src/client/workflow-definition.ts`.
///
/// The fold side (`tool-workflow/*` event family) lands with the
/// conversation-fold workstream; this module owns the renderer-side data
/// model plus the [ChatNodeData.lines] codec the keyed seam hands over until
/// the node family is typed there.
library;

import 'package:flutter/foundation.dart';

import '../conversation/hub.dart' show ChatNodeData;

/// Status shown for a workflow, phase, or member.
enum WorkflowRunStatus { running, completed, failed, cancelled, interrupted }

/// Final renderer data for one member.
@immutable
class WorkflowRunMemberData {
  /// Source seq of the member's start event (stable row id).
  final int seq;

  /// Producer-supplied member label.
  final String label;

  /// Child session carrying the member's work.
  final String childId;

  /// Member status.
  final WorkflowRunStatus status;

  /// Creates member data.
  const WorkflowRunMemberData({
    required this.seq,
    required this.label,
    required this.childId,
    required this.status,
  });
}

/// Final renderer data for one exact phase identity.
@immutable
class WorkflowRunPhaseData {
  /// Collision-free phase key (`workflowPhaseKey`).
  final String key;

  /// `null` is the absent field; the empty string remains a distinct
  /// identity.
  final String? phase;

  /// Members that actually started, in start order.
  final List<WorkflowRunMemberData> members;

  /// Creates phase data.
  const WorkflowRunPhaseData({
    required this.key,
    required this.phase,
    required this.members,
  });
}

/// Final keyed Chat payload for one workflow run.
@immutable
class WorkflowRunChatData {
  /// Workflow name.
  final String name;

  /// Run status.
  final WorkflowRunStatus status;

  /// Phases in first-seen order.
  final List<WorkflowRunPhaseData> phases;

  /// Creates run data.
  const WorkflowRunChatData({
    required this.name,
    required this.status,
    required this.phases,
  });

  /// Total started members across phases.
  int get memberCount =>
      phases.fold(0, (count, phase) => count + phase.members.length);
}

/// Build a collision-free phase key preserving absent versus empty identity.
String workflowPhaseKey(String? phase) {
  return phase == null ? 'missing' : 'value:${phase.length}:$phase';
}

/// The phase a key was built from (`null` for the absent-field key).
String? phaseFromKey(String key) {
  if (key == 'missing') return null;
  const prefix = 'value:';
  if (!key.startsWith(prefix)) return key;
  final colon = key.indexOf(':', prefix.length);
  if (colon == -1) return key;
  final length = int.tryParse(key.substring(prefix.length, colon));
  if (length == null) return key;
  return key.substring(colon + 1);
}

WorkflowRunStatus? _statusOf(String raw) => switch (raw) {
  'running' => WorkflowRunStatus.running,
  'completed' => WorkflowRunStatus.completed,
  'failed' => WorkflowRunStatus.failed,
  'cancelled' => WorkflowRunStatus.cancelled,
  'interrupted' => WorkflowRunStatus.interrupted,
  _ => null,
};

/// Encodes one run onto the seam's line contract: `[name, status, …member]`
/// with member rows `workflowPhaseKey(phase)\tlabel\tchildId\tstatus`.
List<String> encodeWorkflowRunLines(WorkflowRunChatData data) => [
  data.name,
  data.status.name,
  for (final phase in data.phases)
    for (final member in phase.members)
      '${workflowPhaseKey(phase.phase)}\t${member.label}\t${member.childId}\t${member.status.name}',
];

/// Decodes the seam's [ChatNodeData.lines] into renderer data; null when the
/// node does not carry the run header pair yet.
WorkflowRunChatData? decodeWorkflowRun(ChatNodeData data) {
  if (data.lines.length < 2) return null;
  final status = _statusOf(data.lines[1]);
  if (status == null) return null;

  final Map<String, List<WorkflowRunMemberData>> grouped = {};
  var seq = 0;
  for (final line in data.lines.sublist(2)) {
    final fields = line.split('\t');
    if (fields.length != 4) continue;
    final memberStatus = _statusOf(fields[3]);
    if (memberStatus == null) continue;
    seq += 1;
    grouped
        .putIfAbsent(fields[0], () => [])
        .add(
          WorkflowRunMemberData(
            seq: seq,
            label: fields[1],
            childId: fields[2],
            status: memberStatus,
          ),
        );
  }
  return WorkflowRunChatData(
    name: data.lines[0],
    status: status,
    phases: [
      for (final MapEntry(key: key, value: members) in grouped.entries)
        WorkflowRunPhaseData(
          key: key,
          phase: phaseFromKey(key),
          members: members,
        ),
    ],
  );
}
