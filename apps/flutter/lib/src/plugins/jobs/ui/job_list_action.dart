/// Session-header background-job action — Flutter port of
/// `JobListAction.tsx`, mounted through the `conversation.session.header.
/// actions` hole (id `job-list`, order 20, after the subagent catalog).
///
/// The data arrives entirely through [jobsProvider] (the authoritative whole
/// snapshots of the `session/jobs` frames), so the action issues no RPC and
/// holds no state beyond popover visibility. It renders nothing at all until
/// the session has at least one job, so an ordinary conversation never grows
/// a control for a capability it is not using.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/state_dot.dart';
import '../../conversation/jobs_state.dart';
import '../job_models.dart';
import '../locales.dart';

StateDotState _dotFor(String state) => switch (state) {
  'ongoing' => StateDotState.ongoing,
  'done' => StateDotState.done,
  'error' => StateDotState.error,
  _ => StateDotState.warning,
};

/// Session-header entry point for this session's background jobs.
class JobListAction extends ConsumerStatefulWidget {
  /// Creates the header action.
  const JobListAction({super.key});

  @override
  ConsumerState<JobListAction> createState() => _JobListActionState();
}

class _JobListActionState extends ConsumerState<JobListAction> {
  bool _open = false;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _setOpen(bool open, List<JobViewRow> rows) {
    setState(() {
      _open = open;
      // Sample the clock in the same commit that opens the list: a stale
      // value would clamp a long-running row to zero until the ticker fires.
      _now = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = null;
    // The clock only runs while an open list is showing something that moves.
    final liveCount = rows.where(isLive).length;
    if (open && liveCount > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final String? sessionId = ref.watch(currentSessionIdProvider)?.value;
    final Map<String, List<Map<String, Object?>>> bySession = ref.watch(
      jobsProvider,
    );
    final rawJobs = sessionId == null ? null : bySession[sessionId];
    // A session with no jobs keeps one empty array identity — and renders
    // nothing (React visibility rule).
    if (rawJobs == null || rawJobs.isEmpty) return const SizedBox.shrink();

    final rows = ordered([for (final raw in rawJobs) JobViewRow.fromJson(raw)]);
    final int liveCount = rows.where(isLive).length;
    final String label = countLabel(liveCount, rows.length);

    return PopupMenuButton<int>(
      tooltip: kJobEn['list.aria'],
      enabled: true,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      ),
      color: aliases.specificMenu,
      onOpened: () => _setOpen(true, rows),
      onCanceled: () => _setOpen(false, rows),
      itemBuilder: (context) => [
        for (final (index, job) in rows.indexed)
          PopupMenuItem<int>(
            value: index,
            enabled: false,
            child: _JobRow(job: job, now: _now, aliases: aliases),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (liveCount > 0) ...[
            StateDot(state: StateDotState.ongoing, size: 8),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              fontWeight: FontWeight.w600,
              color: aliases.labelSecondary,
            ),
          ),
          Icon(
            _open ? Icons.expand_less : Icons.expand_more,
            size: 14,
            color: aliases.labelTertiary,
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.now, required this.aliases});

  final JobViewRow job;
  final DateTime now;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final bool live = isLive(job);
    final int elapsed = live
        ? now.millisecondsSinceEpoch - job.startedAt
        : (job.finishedAt ?? job.startedAt) - job.startedAt;
    final String duration = formatDuration(elapsed);
    final String status = statusLabel(job.status);

    return Row(
      children: [
        StateDot(state: _dotFor(dotState(job.status)), size: 8),
        const SizedBox(width: 6),
        Text(
          job.kind,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            job.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              fontWeight: FontWeight.w500,
              color: aliases.labelPrimary,
            ),
          ),
        ),
        Text(
          job.detail ?? status,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          duration,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelCaption,
          ),
        ),
      ],
    );
  }
}
