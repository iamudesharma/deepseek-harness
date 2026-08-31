/// Child-transcript chat-node card — the `conversation.chat.node` keyed
/// renderer for `subagent` nodes (hub map §6). Presentation mirrors the
/// re-homed transcript rows: accent header plus per-line transcript entries.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../conversation/hub.dart' show ChatNodeData;

/// Renders one subagent node from the seam's [data] (key + folded lines).
Widget renderSubagentNode(BuildContext context, ChatNodeData data) =>
    _SubagentNodeCard(data: data);

class _SubagentNodeCard extends StatelessWidget {
  const _SubagentNodeCard({required this.data});

  final ChatNodeData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 14,
                color: aliases.stateBusinessPrimary,
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Text(
                'Subagent',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: aliases.stateBusinessPrimary,
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Text(
                  data.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelCaption,
                  ),
                ),
              ),
            ],
          ),
          if (data.lines.isNotEmpty) ...[
            const SizedBox(height: DswTokens.spaceSm),
            for (final String line in data.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    height: 1.4,
                    color: aliases.labelSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
