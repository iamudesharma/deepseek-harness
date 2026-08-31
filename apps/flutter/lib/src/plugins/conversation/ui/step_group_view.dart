/// Grouped rendering for StepGroupNode — collapsed summary tile with the
/// newest group expanded (step-summary view lives in step_summary_line.dart).
library;

import 'package:flutter/material.dart';

import '../nodes/conversation_nodes.dart';

Widget renderStepGroup(
  BuildContext context,
  StepGroupNode group, {
  required bool expanded,
  required Widget Function(BuildContext, ConversationNode) childBuilder,
}) {
  return ExpansionTile(
    initiallyExpanded: expanded,
    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
    title: Text(summaryLine(group)),
    subtitle: group.settled ? null : const Text('running…'),
    children: [
      for (final child in group.children)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: childBuilder(context, child),
        ),
    ],
  );
}

String summaryLine(StepGroupNode group) => group.summary;
