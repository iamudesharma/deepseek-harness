import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_provider.dart';
import '../../conversation/jobs_state.dart';
import '../locales.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/state_dot.dart';
import '../job_models.dart';

/// Jobs list screen — background jobs with status dots.
///
/// Flutter-side surface over the authoritative [jobsProvider] frame feed
/// (React `ui-jobs` ships only the header action): shows this session's rows
/// when [sessionId] is given, otherwise every session's, grouped by session.
/// Empty sessions render the empty state; no demo data.
class JobsScreen extends ConsumerWidget {
  /// Creates the jobs screen.
  const JobsScreen({super.key, this.sessionId});

  /// Optional session scoping — falls back to every session.
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final Map<String, List<Map<String, Object?>>> bySession = ref.watch(
      jobsProvider,
    );
    final String? scoped =
        sessionId ?? ref.watch(currentSessionIdProvider)?.value;
    final entries = bySession.entries
        .where((e) => scoped == null || e.key == scoped)
        .toList(growable: false);
    final int total = entries.fold(0, (sum, e) => sum + e.value.length);
    final Translate t = ref.bindLocale(kJobNamespace);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          t('list.aria'),
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: total == 0
          ? _EmptyJobs(aliases: aliases)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _JobsHeader(
                  count: total,
                  running: entries.fold(
                    0,
                    (sum, e) =>
                        sum +
                        e.value.where((j) => j['status'] == 'running').length,
                  ),
                  aliases: aliases,
                ),
                Divider(height: 1, color: aliases.borderL2),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(DswTokens.spaceLg),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: DswTokens.spaceMd),
                    itemBuilder: (BuildContext context, int index) {
                      final entry = entries[index];
                      final rows = ordered([
                        for (final raw in entry.value) JobViewRow.fromJson(raw),
                      ]);
                      return _SessionGroup(
                        sessionKey: entry.key,
                        rows: rows,
                        aliases: aliases,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _SessionGroup extends StatelessWidget {
  const _SessionGroup({
    required this.sessionKey,
    required this.rows,
    required this.aliases,
  });

  final String sessionKey;
  final List<JobViewRow> rows;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sessionKey,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelTertiary,
          ),
        ),
        const SizedBox(height: DswTokens.spaceSm),
        for (final job in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
            child: _JobTile(job: job, aliases: aliases),
          ),
      ],
    );
  }
}

class _JobsHeader extends ConsumerWidget {
  const _JobsHeader({
    required this.count,
    required this.running,
    required this.aliases,
  });

  final int count;
  final int running;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kJobNamespace);
    return Container(
      color: aliases.bgLayer2,
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceLg,
        vertical: DswTokens.spaceMd,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: running > 0
                  ? aliases.stateSuccessTertiary
                  : aliases.bgOverlay,
              borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              border: Border.all(
                color: running > 0
                    ? aliases.stateSuccessPrimary
                    : aliases.borderL2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: running > 0
                        ? aliases.stateSuccessPrimary
                        : aliases.labelTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  running > 0 ? t('status.running') : t('badge.idle'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    fontWeight: FontWeight.w600,
                    color: running > 0
                        ? aliases.stateSuccessPrimary
                        : aliases.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          Text(
            t('header.count').replaceAll('{n}', '$count'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
            ),
          ),
          const Spacer(),
          Text(
            t('list.aria'),
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelCaption,
            ),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job, required this.aliases});

  final JobViewRow job;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // React's `job` dictionary carries the status vocabulary (lowercase in
    // the English source of truth); the badge renders it verbatim.
    final Translate t = ref.bindLocale(kJobNamespace);
    final StateDotState dot = switch (dotState(job.status)) {
      'ongoing' => StateDotState.ongoing,
      'done' => StateDotState.done,
      'error' => StateDotState.error,
      _ => StateDotState.warning,
    };
    final String statusLabel = switch (job.status) {
      JobStatus.running => t('status.running'),
      JobStatus.stopping => t('status.stopping'),
      JobStatus.completed => t('status.completed'),
      JobStatus.killed => t('status.killed'),
      JobStatus.failed => t('status.failed'),
    };
    final Color statusColor = switch (job.status) {
      JobStatus.running || JobStatus.stopping => aliases.stateWarnPrimary,
      JobStatus.completed => aliases.stateSuccessPrimary,
      JobStatus.killed => aliases.labelCaption,
      JobStatus.failed => aliases.stateErrorPrimary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceMd,
        vertical: DswTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StateDot(state: dot, size: 10),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w500,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: DswTokens.spaceSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          DswTokens.radiusFull,
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (job.detail != null)
                      Text(
                        job.detail!,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    Text(
                      formatDuration(
                        (job.finishedAt ??
                                DateTime.now().millisecondsSinceEpoch) -
                            job.startedAt,
                      ),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelCaption,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          Text(
            job.id,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelCaption,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyJobs extends ConsumerWidget {
  const _EmptyJobs({required this.aliases});

  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kJobNamespace);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_outline, size: 32, color: aliases.labelCaption),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              t('empty.title'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('empty.hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
