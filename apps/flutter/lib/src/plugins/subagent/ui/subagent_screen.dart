import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import 'subagent_provider.dart';

/// Subagent screen — summary-derived child list + child transcript.
///
/// The list derives from the shared sessions list (`origin == 'subagent'`
/// children of [sessionId], the catalog action's data source); the detail
/// view folds the child's durable history. Handles empty/loading/error and
/// uses [DswTokens] via [Theme].
class SubagentScreen extends ConsumerWidget {
  /// Creates the subagent screen.
  const SubagentScreen({super.key, required this.sessionId});

  /// Parent session whose subagent children are listed.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String? selectedId = ref.watch(selectedSubagentProvider);
    final List<SubagentView> subagents = ref.watch(
      subagentsFamilyProvider(sessionId),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          selectedId == null ? 'Subagents' : 'Subagent · $selectedId',
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        leading: selectedId == null
            ? null
            : IconButton(
                tooltip: 'Back to list',
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    ref.read(selectedSubagentProvider.notifier).state = null,
              ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () {
              ref.invalidate(subagentsFamilyProvider(sessionId));
              if (selectedId != null)
                ref.invalidate(subagentTranscriptProvider(selectedId));
            },
          ),
          const SizedBox(width: DswTokens.spaceSm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: selectedId != null
          ? _TranscriptBody(sessionId: selectedId, aliases: aliases)
          : _ListView(subagents: subagents, aliases: aliases),
    );
  }
}

/// List body: header strip + one tile per summary-known child.
class _ListView extends StatelessWidget {
  const _ListView({required this.subagents, required this.aliases});

  final List<SubagentView> subagents;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    if (subagents.isEmpty) return _EmptySubagents(aliases: aliases);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubagentHeader(
          count: subagents.length,
          running: subagents.where((s) => s.running).length,
          aliases: aliases,
        ),
        Divider(height: 1, color: aliases.borderL2),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            itemCount: subagents.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: DswTokens.spaceSm),
            itemBuilder: (BuildContext context, int index) {
              final SubagentView view = subagents[index];
              return _SubagentTile(view: view, aliases: aliases);
            },
          ),
        ),
      ],
    );
  }
}

/// Transcript body: async scaffold over the child's durable history.
class _TranscriptBody extends ConsumerWidget {
  const _TranscriptBody({required this.sessionId, required this.aliases});

  final String sessionId;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SubagentTranscriptEntry>> async = ref.watch(
      subagentTranscriptProvider(sessionId),
    );
    return async.when(
      data: (List<SubagentTranscriptEntry> entries) => _TranscriptView(
        childId: sessionId,
        entries: entries,
        aliases: aliases,
      ),
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: aliases.labelTertiary,
              ),
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'Loading transcript…',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      ),
      error: (Object err, StackTrace st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 28,
                color: aliases.stateErrorPrimary,
              ),
              const SizedBox(height: DswTokens.spaceSm),
              Text(
                'Failed to load transcript',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                err.toString(),
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                ),
              ),
              const SizedBox(height: DswTokens.spaceMd),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(subagentTranscriptProvider(sessionId)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubagentHeader extends StatelessWidget {
  const _SubagentHeader({
    required this.count,
    required this.running,
    required this.aliases,
  });

  final int count;
  final int running;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
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
                  running > 0 ? '$running running' : 'Idle',
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
            '$count subagent${count == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
            ),
          ),
          const Spacer(),
          Text(
            'Child sessions',
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

class _SubagentTile extends ConsumerWidget {
  const _SubagentTile({required this.view, required this.aliases});

  final SubagentView view;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: aliases.bgLayer2,
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: InkWell(
        // Opening a child navigates to its detail view (the catalog action's
        // shared-list navigation analog for the standalone screen).
        onTap: () =>
            ref.read(selectedSubagentProvider.notifier).state = view.id,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DswTokens.spaceMd,
            vertical: DswTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            border: Border.all(color: aliases.borderL1),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: view.running
                      ? aliases.stateBusinessTertiary
                      : aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                ),
                child: Icon(
                  view.running ? Icons.sync : Icons.check_circle_outline,
                  size: 16,
                  color: view.running
                      ? aliases.stateBusinessPrimary
                      : aliases.labelTertiary,
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w500,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      view.preview ?? view.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: view.running
                          ? aliases.stateSuccessTertiary
                          : aliases.bgOverlay,
                      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                    ),
                    child: Text(
                      view.running ? 'Running' : 'Done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: view.running
                            ? aliases.stateSuccessPrimary
                            : aliases.labelTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    view.id,
                    style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                  ),
                ],
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Icon(Icons.chevron_right, size: 16, color: aliases.labelCaption),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscriptView extends StatelessWidget {
  const _TranscriptView({
    required this.childId,
    required this.entries,
    required this.aliases,
  });

  final String childId;
  final List<SubagentTranscriptEntry> entries;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      children: [
        Container(
          padding: const EdgeInsets.all(DswTokens.spaceMd),
          decoration: BoxDecoration(
            color: aliases.bgLayer2,
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            border: Border.all(color: aliases.borderL2),
          ),
          child: Row(
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: aliases.labelTertiary,
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Text(
                  childId,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DswTokens.spaceLg),
        Text(
          'Transcript',
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            fontWeight: FontWeight.w600,
            color: aliases.labelCaption,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: DswTokens.spaceSm),
        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(DswTokens.spaceMd),
            decoration: BoxDecoration(
              color: aliases.bgOverlay,
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              border: Border.all(color: aliases.borderL1),
            ),
            child: Text(
              'No transcript yet.',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelTertiary,
              ),
            ),
          )
        else
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
              child: _TranscriptRow(entry: e, aliases: aliases),
            ),
          ),
      ],
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  const _TranscriptRow({required this.entry, required this.aliases});

  final SubagentTranscriptEntry entry;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (entry.role) {
      'user' => Icons.person_outline,
      'tool' => Icons.build_outlined,
      _ => Icons.smart_toy_outlined,
    };
    final Color roleColor = switch (entry.role) {
      'user' => aliases.stateBusinessPrimary,
      'tool' => aliases.labelTertiary,
      _ => aliases.labelSecondary,
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
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: aliases.bgOverlay,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: roleColor),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: aliases.bgOverlay,
                        borderRadius: BorderRadius.circular(
                          DswTokens.radiusFull,
                        ),
                      ),
                      child: Text(
                        entry.role,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: roleColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeLabel(entry.time),
                      style: TextStyle(
                        fontSize: 11,
                        color: aliases.labelCaption,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.content,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _EmptySubagents extends StatelessWidget {
  const _EmptySubagents({required this.aliases});

  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'No subagents',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Subagents delegated from this session will appear here.',
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
