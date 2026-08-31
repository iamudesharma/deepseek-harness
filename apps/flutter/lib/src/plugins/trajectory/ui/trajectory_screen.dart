import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/session_provider.dart';
import '../../../core/session/session_models.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/disclosure_row.dart';
import '../../../widgets/primitives/icons.dart';
import '../../../widgets/primitives/json_tree.dart';
import '../../tool/tool_models.dart';
import '../trajectory_provider.dart';

/// Trajectory view — timeline / table of turns for a session.
///
/// Uses [trajectoryProvider] (sessionId family) for [Trajectory] data and
/// renders via [TrajectoryTimeline]. Handles empty / loading / error states
/// and is a [ConsumerWidget] that respects [Theme].
///
/// Route: `/sessions/:sid/trajectory`
class TrajectoryScreen extends ConsumerWidget {
  /// Creates the trajectory screen.
  const TrajectoryScreen({super.key, required this.sessionId});

  /// Session id from route param (raw string).
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<Trajectory> async = ref.watch(
      trajectoryProvider(sessionId),
    );
    final SessionSummary? summary = ref.watch(
      sessionByIdProvider(SessionId(sessionId)),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          summary == null
              ? 'Trajectory · $sessionId'
              : summary.blank
              ? 'New session'
              : summary.displayTitle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        leading: IconButton(
          tooltip: 'Back to conversation',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/sessions/$sessionId'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => ref.invalidate(trajectoryProvider(sessionId)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: async.when(
        data: (Trajectory trajectory) {
          if (trajectory.turns.isEmpty) {
            return _EmptyTrajectory(sessionId: sessionId, aliases: aliases);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TrajectoryHeader(trajectory: trajectory, aliases: aliases),
              Divider(height: 1, color: aliases.borderL2),
              Expanded(child: TrajectoryTimeline(trajectory: trajectory)),
            ],
          );
        },
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
                'Loading trajectory…',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.labelSecondary,
                ),
              ),
            ],
          ),
        ),
        error: (Object err, StackTrace st) => _ErrorState(
          error: err.toString(),
          aliases: aliases,
          onRetry: () => ref.invalidate(trajectoryProvider(sessionId)),
        ),
      ),
    );
  }
}

/// Header summary bar for a trajectory — turn count, total duration, status.
class _TrajectoryHeader extends StatelessWidget {
  const _TrajectoryHeader({required this.trajectory, required this.aliases});

  final Trajectory trajectory;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final int count = trajectory.turns.length;
    final bool running = trajectory.isRunning;
    final String durationLabel = _durationLabel(trajectory.totalDurationMs);

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
              color: running ? aliases.stateSuccessTertiary : aliases.bgOverlay,
              borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              border: Border.all(
                color: running ? aliases.stateSuccessPrimary : aliases.borderL2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: running
                        ? aliases.stateSuccessPrimary
                        : aliases.labelTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  running ? 'Running' : 'Idle',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    fontWeight: FontWeight.w600,
                    color: running
                        ? aliases.stateSuccessPrimary
                        : aliases.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          Text(
            '$count turn${count == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              color: aliases.labelSecondary,
            ),
          ),
          if (durationLabel.isNotEmpty) ...[
            const SizedBox(width: DswTokens.spaceSm),
            Text(
              '· $durationLabel',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelCaption,
              ),
            ),
          ],
          const Spacer(),
          Text(
            'Session ${trajectory.sessionId}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelCaption,
            ),
          ),
        ],
      ),
    );
  }

  String _durationLabel(int? ms) {
    if (ms == null) return '';
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    final int mins = ms ~/ 60000;
    final int secs = (ms % 60000) ~/ 1000;
    return '${mins}m ${secs}s';
  }
}

/// Timeline widget — vertical timeline / table of turns.
///
/// Pure layout widget that can be embedded independently of the full screen.
/// Renders a vertical dotted line with status-colored turn dots and an
/// expandable detail row per turn (title, summary, tool count, duration).
class TrajectoryTimeline extends ConsumerWidget {
  /// Creates the trajectory timeline.
  const TrajectoryTimeline({super.key, required this.trajectory});

  /// Trajectory to render.
  final Trajectory trajectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        DswTokens.spaceLg,
        DswTokens.spaceLg,
        DswTokens.spaceLg,
        DswTokens.spaceXl,
      ),
      itemCount: trajectory.turns.length,
      separatorBuilder: (_, _) => const SizedBox(height: DswTokens.spaceSm),
      itemBuilder: (BuildContext context, int index) {
        final Turn turn = trajectory.turns[index];
        final bool isFirst = index == 0;
        final bool isLast = index == trajectory.turns.length - 1;
        return _TurnTile(
          turn: turn,
          aliases: aliases,
          isFirst: isFirst,
          isLast: isLast,
        );
      },
    );
  }
}

class _TurnTile extends StatefulWidget {
  const _TurnTile({
    required this.turn,
    required this.aliases,
    required this.isFirst,
    required this.isLast,
  });

  final Turn turn;
  final DswAliases aliases;
  final bool isFirst;
  final bool isLast;

  @override
  State<_TurnTile> createState() => _TurnTileState();
}

class _TurnTileState extends State<_TurnTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final Turn turn = widget.turn;
    final DswAliases aliases = widget.aliases;
    final Color dotColor = _dotColor(turn.status, aliases);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline gutter: vertical line + dot.
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 2,
                height: widget.isFirst ? 8 : 12,
                color: widget.isFirst
                    ? DswTokens.transparent
                    : aliases.borderL2,
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: dotColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: dotColor, width: 1.5),
                ),
                child: Center(child: _statusGlyph(turn.status, dotColor)),
              ),
              Container(
                width: 2,
                height: widget.isLast ? 8 : 24,
                color: widget.isLast ? DswTokens.transparent : aliases.borderL2,
              ),
            ],
          ),
        ),
        const SizedBox(width: DswTokens.spaceSm),
        // Card.
        Expanded(
          child: Material(
            color: aliases.bgLayer2,
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            clipBehavior: Clip.hardEdge,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                  border: Border.all(
                    color: _expanded
                        ? aliases.stateBusinessPrimary
                        : aliases.borderL2,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  DswTokens.spaceMd,
                  DswTokens.spaceSm,
                  DswTokens.spaceMd,
                  DswTokens.spaceSm,
                ),
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
                            'Turn ${turn.ordinal}',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              fontWeight: FontWeight.w600,
                              color: aliases.labelTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: DswTokens.spaceSm),
                        Expanded(
                          child: Text(
                            turn.title,
                            maxLines: _expanded ? null : 1,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w500,
                              color: aliases.labelPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: DswTokens.spaceSm),
                        _StatusChip(status: turn.status, aliases: aliases),
                        const SizedBox(width: 4),
                        _expanded
                            ? DsIcons.chevronUp(
                                size: 16,
                                color: aliases.labelCaption,
                              )
                            : DsIcons.chevronDown(
                                size: 16,
                                color: aliases.labelCaption,
                              ),
                      ],
                    ),
                    if (turn.summary != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        turn.summary!,
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          color: aliases.labelSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Meta row: duration · tool count · time.
                    Wrap(
                      spacing: DswTokens.spaceSm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MetaPill(
                          icon: Icons.schedule,
                          label: _timeLabel(turn.startTime),
                          aliases: aliases,
                        ),
                        if (turn.durationMs != null)
                          _MetaPill(
                            icon: Icons.timer_outlined,
                            label: _durationLabel(turn.durationMs!),
                            aliases: aliases,
                          ),
                        if (turn.toolCalls.isNotEmpty)
                          _MetaPill(
                            icon: Icons.build_outlined,
                            label:
                                '${turn.toolCalls.length} tool${turn.toolCalls.length == 1 ? '' : 's'}',
                            aliases: aliases,
                          ),
                        _MetaPill(
                          icon: Icons.tag,
                          label: turn.id,
                          aliases: aliases,
                        ),
                      ],
                    ),
                    if (_expanded && turn.toolCalls.isNotEmpty) ...[
                      const SizedBox(height: DswTokens.spaceMd),
                      Divider(height: 1, color: aliases.borderL2),
                      const SizedBox(height: DswTokens.spaceSm),
                      Text(
                        'Tool calls',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelTertiary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...turn.toolCalls.map(
                        (c) => _ToolCallRecord(call: c, aliases: aliases),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _dotColor(TurnStatus status, DswAliases a) => switch (status) {
    TurnStatus.pending => a.labelCaption,
    TurnStatus.running => a.stateBusinessPrimary,
    TurnStatus.completed => a.stateSuccessPrimary,
    TurnStatus.failed => a.stateErrorPrimary,
  };

  // Completed/failed dots ride the shared DsIcons substitution map
  // (ui-primitives icons/index.tsx); the pending/running clocks have no
  // mapped glyph and stay Material-inline.
  Widget _statusGlyph(TurnStatus status, Color color) => switch (status) {
    TurnStatus.pending => Icon(Icons.schedule, size: 14, color: color),
    TurnStatus.running => Icon(Icons.sync, size: 14, color: color),
    TurnStatus.completed => DsIcons.check(size: 14, color: color),
    TurnStatus.failed => DsIcons.close(size: 14, color: color),
  };

  String _timeLabel(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _durationLabel(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms ~/ 60000}m ${(ms % 60000) ~/ 1000}s';
  }
}

/// One tool-call record inside an expanded turn — the Flutter analog of
/// TrajectoryTable.tsx's RecordPayload (lines ~1509-1574): expanding the row
/// reveals the call's args as "Payload JSON" and its settled result as
/// "Result JSON" through [DsJsonTree], with a mono fallback when the result
/// text is not a JSON container.
class _ToolCallRecord extends StatefulWidget {
  const _ToolCallRecord({required this.call, required this.aliases});

  final ToolCall call;
  final DswAliases aliases;

  @override
  State<_ToolCallRecord> createState() => _ToolCallRecordState();
}

class _ToolCallRecordState extends State<_ToolCallRecord> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ToolCall call = widget.call;
    final DswAliases aliases = widget.aliases;
    final dynamic resultJson = jsonContainerOf(call.result);
    final String resultText = resultJson == null
        ? scalarResultText(call.result)
        : '';
    final bool expandable =
        call.args.isNotEmpty || resultJson != null || resultText.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DisclosureRow(
        leadingSize: 14,
        icon: _kindGlyph(call.kind, aliases.labelTertiary),
        title: '${call.toolName} · ${call.status.name}',
        open: _open,
        expandable: expandable,
        onToggle: () => setState(() => _open = !_open),
        expandOnRowClick: true,
        collapsedContent: resultText.isEmpty
            ? null
            : Text(
                resultText.split('\n').first,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelCaption,
                ),
                overflow: TextOverflow.ellipsis,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (call.args.isNotEmpty) ...<Widget>[
              const _PayloadLabel('Payload JSON'),
              // JsonTree.tsx expandTopLevel defaults to true: the root node
              // renders expanded so record payloads read without extra taps.
              DsJsonTree(data: call.args, initiallyExpanded: true),
            ],
            if (resultJson != null) ...<Widget>[
              const _PayloadLabel('Result JSON'),
              DsJsonTree(data: resultJson, initiallyExpanded: true),
            ] else if (resultText.isNotEmpty) ...<Widget>[
              const _PayloadLabel('Result'),
              _MonoFallback(text: resultText, aliases: aliases),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kindGlyph(ToolCallKind kind, Color color) => switch (kind) {
    ToolCallKind.search => DsIcons.search(size: 12, color: color),
    ToolCallKind.read => Icon(Icons.article_outlined, size: 12, color: color),
    ToolCallKind.diff => Icon(
      Icons.difference_outlined,
      size: 12,
      color: color,
    ),
    ToolCallKind.bash => Icon(Icons.terminal, size: 12, color: color),
    ToolCallKind.generic => Icon(Icons.build_outlined, size: 12, color: color),
  };
}

/// Section label above a record payload section.
class _PayloadLabel extends StatelessWidget {
  const _PayloadLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: DswTokens.fontSizeXxs12,
          fontWeight: FontWeight.w600,
          color: aliases.labelTertiary,
        ),
      ),
    );
  }
}

/// Non-JSON result text rendered as a plain mono block — TrajectoryTable.tsx's
/// bare `<pre class=css.payload>` fallback.
class _MonoFallback extends StatelessWidget {
  const _MonoFallback({required this.text, required this.aliases});

  final String text;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
        border: Border.all(color: aliases.borderL2),
      ),
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      child: SelectableText(
        text,
        style: TextStyle(
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          color: aliases.labelPrimary,
          fontFamily: 'SF Mono',
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
        ),
      ),
    );
  }
}

/// Parses a JSON container out of a raw tool result — analog of TrajectoryTable.tsx's `parseJsonContainer`:
/// Map/List values and strings that decode to Map/List render as trees; everything else returns null so the
/// caller falls back to the mono block.
dynamic jsonContainerOf(dynamic value) {
  if (value is Map || value is List) return value;
  if (value is String) {
    final String trimmed = value.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is Map || decoded is List) return decoded;
    } on FormatException {
      // Not JSON text — caller renders the mono fallback instead.
    }
  }
  return null;
}

/// Result text for non-container results (plain strings, numbers, bools).
String scalarResultText(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.aliases});

  final TurnStatus status;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String label) = switch (status) {
      TurnStatus.pending => (
        aliases.bgOverlay,
        aliases.labelCaption,
        'Pending',
      ),
      TurnStatus.running => (
        aliases.stateBusinessTertiary,
        aliases.stateBusinessPrimary,
        'Running',
      ),
      TurnStatus.completed => (
        aliases.stateSuccessTertiary,
        aliases.stateSuccessPrimary,
        'Done',
      ),
      TurnStatus.failed => (
        DswTokens.red100,
        aliases.stateErrorPrimary,
        'Failed',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DswTokens.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.aliases,
  });

  final IconData icon;
  final String label;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(DswTokens.radiusFull),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: aliases.labelCaption),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: aliases.labelTertiary),
          ),
        ],
      ),
    );
  }
}

class _EmptyTrajectory extends StatelessWidget {
  const _EmptyTrajectory({required this.sessionId, required this.aliases});

  final String sessionId;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 32, color: aliases.labelCaption),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              'No turns yet',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Trajectory for $sessionId is empty.\nSend a message to create the first turn.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: DswTokens.spaceLg),
            OutlinedButton.icon(
              onPressed: () => context.go('/sessions/$sessionId'),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('Back to conversation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.aliases,
    required this.onRetry,
  });

  final String error;
  final DswAliases aliases;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
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
              'Failed to load trajectory',
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              error,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: DswTokens.spaceMd),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
