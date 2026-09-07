/// Workflow-run chat-node panel — Flutter port of `WorkflowRunPanel.tsx`
/// trimmed to the seam data the Dart fold carries.
///
/// Renders one durable workflow run: a run disclosure (name, member count,
/// status tail) over phase disclosures, each listing its members with status
/// dots. Status-driven initial disclosure follows React's facts model —
/// abnormal or running runs open, clean runs stay collapsed; the deferred
/// focus-collapse machinery is browser-focus-specific and stays out until
/// the desktop surface needs it. Members whose child session is navigable
/// open it through the injected [openSession] face.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/disclosure_row.dart';
import '../../../widgets/primitives/state_dot.dart';
import '../locales.dart';
import '../workflow_run_models.dart';

StateDotState _dotFor(WorkflowRunStatus status) => switch (status) {
  WorkflowRunStatus.running => StateDotState.ongoing,
  WorkflowRunStatus.completed => StateDotState.done,
  WorkflowRunStatus.failed => StateDotState.error,
  WorkflowRunStatus.cancelled ||
  WorkflowRunStatus.interrupted => StateDotState.warning,
};

String _statusText(WorkflowRunStatus status) =>
    kWorkflowRunEn['status.${status.name}'] ?? status.name;

bool _abnormal(WorkflowRunStatus status) =>
    status == WorkflowRunStatus.failed ||
    status == WorkflowRunStatus.cancelled ||
    status == WorkflowRunStatus.interrupted;

/// Whether a run/phase opens expanded on first build: anything abnormal or
/// still moving opens; settled-clean stays collapsed.
bool initiallyOpen(
  Iterable<WorkflowRunMemberData> members,
  WorkflowRunStatus status,
) {
  if (_abnormal(status) || status == WorkflowRunStatus.running) return true;
  return members.any(
    (m) => _abnormal(m.status) || m.status == WorkflowRunStatus.running,
  );
}

/// Human phase title: absent field, empty name, then the phase itself.
String readablePhase(String? phase) {
  if (phase == null) return kWorkflowRunEn['phase.unassigned']!;
  return phase.isEmpty ? kWorkflowRunEn['phase.empty']! : phase;
}

/// Human member title: empty labels keep their placeholder word.
String readableMember(String label) =>
    label.isEmpty ? kWorkflowRunEn['member.empty']! : label;

/// `Completed 2 · Failed 1`-style per-status summary for a collapsed phase.
String phaseStatusSummary(List<WorkflowRunMemberData> members) {
  final counts = <WorkflowRunStatus, int>{};
  for (final member in members) {
    counts[member.status] = (counts[member.status] ?? 0) + 1;
  }
  int countOf(WorkflowRunStatus s) => counts[s] ?? 0;
  final active = [
    for (final s in [
      WorkflowRunStatus.running,
      WorkflowRunStatus.failed,
      WorkflowRunStatus.cancelled,
      WorkflowRunStatus.interrupted,
    ])
      if (countOf(s) > 0) s,
  ];
  if (active.isEmpty)
    return 'Completed ${countOf(WorkflowRunStatus.completed)}';
  final visible =
      active.contains(WorkflowRunStatus.interrupted) &&
          countOf(WorkflowRunStatus.completed) > 0
      ? [WorkflowRunStatus.completed, ...active]
      : active;
  return [
    for (final s in visible)
      '${_statusText(s)[0].toUpperCase()}${_statusText(s).substring(1)} ${countOf(s)}',
  ].join(' · ');
}

/// Renders one durable workflow run with status-driven disclosure.
class WorkflowRunPanel extends StatefulWidget {
  /// Creates the panel over decoded run [data].
  const WorkflowRunPanel({super.key, required this.data, this.openSession});

  /// Decoded renderer payload ([decodeWorkflowRun]).
  final WorkflowRunChatData data;

  /// Opens a member's child session; null keeps rows inert.
  final void Function(String childId)? openSession;

  @override
  State<WorkflowRunPanel> createState() => _WorkflowRunPanelState();
}

class _WorkflowRunPanelState extends State<WorkflowRunPanel> {
  late bool _runOpen;
  final Set<String> _openPhases = {};

  @override
  void initState() {
    super.initState();
    _runOpen = initiallyOpen(
      widget.data.phases.expand((p) => p.members),
      widget.data.status,
    );
    for (final phase in widget.data.phases) {
      if (initiallyOpen(phase.members, widget.data.status)) {
        _openPhases.add(phase.key);
      }
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
    final data = widget.data;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        border: Border.all(color: aliases.borderL2),
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      ),
      child: DisclosureRow(
        icon: const Icon(Icons.account_tree_outlined, size: 16),
        title: data.name,
        open: _runOpen,
        expandable: true,
        expandOnRowClick: true,
        previewChevron: false,
        keepContentWhenOpen: true,
        onToggle: () => setState(() => _runOpen = !_runOpen),
        collapsedContent: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${data.memberCount} member${data.memberCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(width: 8),
            StateDot(state: _dotFor(data.status), size: 8),
            const SizedBox(width: 4),
            Text(
              _statusText(data.status),
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontWeight: FontWeight.w600,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
        child: data.phases.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: DswTokens.spaceSm),
                child: Text(
                  kWorkflowRunEn['run.empty']!,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelTertiary,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final phase in data.phases)
                    _PhaseSection(
                      phase: phase,
                      open: _openPhases.contains(phase.key),
                      onToggle: () => setState(() {
                        _openPhases.contains(phase.key)
                            ? _openPhases.remove(phase.key)
                            : _openPhases.add(phase.key);
                      }),
                      openSession: widget.openSession,
                      aliases: aliases,
                    ),
                ],
              ),
      ),
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({
    required this.phase,
    required this.open,
    required this.onToggle,
    required this.openSession,
    required this.aliases,
  });

  final WorkflowRunPhaseData phase;
  final bool open;
  final VoidCallback onToggle;
  final void Function(String childId)? openSession;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DswTokens.spaceSm),
      child: DisclosureRow(
        icon: Icon(
          open ? Icons.expand_more : Icons.expand_less,
          size: 16,
          color: aliases.labelTertiary,
        ),
        title: readablePhase(phase.phase),
        open: open,
        expandable: true,
        expandOnRowClick: true,
        previewChevron: false,
        keepContentWhenOpen: true,
        onToggle: onToggle,
        collapsedContent: Text(
          phaseStatusSummary(phase.members),
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelSecondary,
          ),
        ),
        child: Column(
          children: [
            for (final member in phase.members)
              _MemberRow(
                member: member,
                openSession: openSession,
                aliases: aliases,
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.openSession,
    required this.aliases,
  });

  final WorkflowRunMemberData member;
  final void Function(String childId)? openSession;
  final DswAliases aliases;

  bool get _navigable =>
      member.status == WorkflowRunStatus.running && openSession != null;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          StateDot(state: _dotFor(member.status), size: 8),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              readableMember(member.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelPrimary,
              ),
            ),
          ),
          Text(
            _statusText(member.status),
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ),
    );
    if (!_navigable) return row;
    return InkWell(
      onTap: () => openSession!(member.childId),
      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      child: row,
    );
  }
}
