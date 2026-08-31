/// Wire-typed background-job views for the `session/jobs` frame feed.
///
/// The frames carry raw `JobView` maps (`@deepseek-ai/dsh-jobs` wire shape:
/// `id`, `kind`, `label`, `status`, `detail?`, `startedAt`, `finishedAt?`);
/// these helpers type them for presentation and keep the ordering, duration,
/// and status semantics of React's `JobListAction.tsx`.
library;

import 'package:flutter/foundation.dart';

/// Job lifecycle state — the closed wire union
/// (`running | stopping | completed | killed | failed`).
enum JobStatus { running, stopping, completed, killed, failed }

/// One background job as the registry reports it.
@immutable
class JobViewRow {
  /// Registry-issued `<kind>-N` identity, stable for the task's whole life.
  final String id;

  /// Producer kind (`bash`, `subagent`, …).
  final String kind;

  /// Producer-supplied one-line label: the command or delegation description.
  final String label;

  /// Current lifecycle state.
  final JobStatus status;

  /// Kind-specific status detail (`exit code: 3`), when supplied.
  final String? detail;

  /// Epoch ms when the task was registered.
  final int startedAt;

  /// Epoch ms when the task settled; null while live.
  final int? finishedAt;

  /// Creates a job row.
  const JobViewRow({
    required this.id,
    required this.kind,
    required this.label,
    required this.status,
    this.detail,
    required this.startedAt,
    this.finishedAt,
  });

  /// Decodes one raw frame entry; unknown statuses are forged data and fail
  /// loud rather than silently rendering a wrong state.
  factory JobViewRow.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final kind = json['kind'];
    final label = json['label'];
    final startedRaw = json['startedAt'];
    if (id is! String ||
        kind is! String ||
        label is! String ||
        startedRaw is! int) {
      throw FormatException('JobView: missing required fields in $json');
    }
    return JobViewRow(
      id: id,
      kind: kind,
      label: label,
      status: switch (json['status']) {
        'running' => JobStatus.running,
        'stopping' => JobStatus.stopping,
        'completed' => JobStatus.completed,
        'killed' => JobStatus.killed,
        'failed' => JobStatus.failed,
        final other => throw FormatException('JobView: unknown status $other'),
      },
      detail: switch (json['detail']) {
        final String d => d,
        _ => null,
      },
      startedAt: startedRaw,
      finishedAt: switch (json['finishedAt']) {
        final int f => f,
        _ => null,
      },
    );
  }
}

/// A job the registry still holds open, whose duration therefore ticks.
bool isLive(JobViewRow job) =>
    job.status == JobStatus.running || job.status == JobStatus.stopping;

/// Status marker semantics. `stopping` and `killed` share the attention
/// color: both mean the work ended (or is ending) on request rather than on
/// its own.
String dotState(JobStatus status) => switch (status) {
  JobStatus.running => 'ongoing',
  JobStatus.stopping => 'warning',
  JobStatus.completed => 'done',
  JobStatus.killed => 'warning',
  JobStatus.failed => 'error',
};

/// Human status word for the row and its accessible name.
String statusLabel(JobStatus status) => switch (status) {
  JobStatus.running => 'running',
  JobStatus.stopping => 'stopping',
  JobStatus.completed => 'completed',
  JobStatus.killed => 'cancelled',
  JobStatus.failed => 'failed',
};

/// Elapsed time in at most two adjacent units; hours is the widest unit.
String formatDuration(int elapsedMs) {
  final total = elapsedMs < 0 ? 0 : elapsedMs ~/ 1000;
  final seconds = total % 60;
  final minutes = (total ~/ 60) % 60;
  final hours = total ~/ 3600;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '$minutes m ${seconds}s';
  return '${seconds}s';
}

/// Live rows first in start order, then settled rows newest-first. Two jobs
/// that settled in the same millisecond fall back to start order, so the
/// sort never depends on the host's map iteration.
List<JobViewRow> ordered(List<JobViewRow> jobs) {
  final sorted = List.of(jobs);
  sorted.sort((left, right) {
    final liveLeft = isLive(left);
    if (liveLeft != isLive(right)) return liveLeft ? -1 : 1;
    if (liveLeft) return left.startedAt.compareTo(right.startedAt);
    final leftEnd = left.finishedAt ?? left.startedAt;
    final rightEnd = right.finishedAt ?? right.startedAt;
    final finished = rightEnd.compareTo(leftEnd);
    return finished != 0 ? finished : left.startedAt.compareTo(right.startedAt);
  });
  return sorted;
}

/// Count-line key semantics: a running session shows the live count,
/// otherwise the total.
String countLabel(int liveCount, int totalCount) {
  if (liveCount > 0) {
    return '$liveCount background job${liveCount == 1 ? '' : 's'} running';
  }
  return '$totalCount background job${totalCount == 1 ? '' : 's'}';
}
