/// Dedicated skill tool row — Flutter port of `SkillRow.tsx` as the
/// `conversation.chat.node` keyed renderer for `skill` (the Dart hub resolves
/// tool nodes by name, which is the `tool.call.toolview` key='skill' analog).
///
/// The seam's [ChatNodeData] carries the folded call lines (`[callId, ?result]`),
/// so the view model derives from those: summary is the result's first line or
/// the call id, and the disclosure shows the full durable output. Lifecycle
/// state coloring needs the settled status bit the data face does not carry
/// and stays out until the seam widens.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../conversation/hub.dart' show ChatNodeData;
import '../locales.dart';

/// First physical line for the collapsed summary.
String firstLine(String text) {
  final newline = text.indexOf('\n');
  return newline == -1 ? text : text.substring(0, newline);
}

/// Renders one `skill` tool node as an accent summary + instructions
/// disclosure.
Widget renderSkillRow(BuildContext context, ChatNodeData data) =>
    _SkillRowCard(data: data);

class _SkillRowCard extends StatefulWidget {
  const _SkillRowCard({required this.data});

  final ChatNodeData data;

  @override
  State<_SkillRowCard> createState() => _SkillRowCardState();
}

class _SkillRowCardState extends State<_SkillRowCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // lines: [callId, ?result] per the ToolNode fold.
    final String callId = widget.data.lines.isNotEmpty
        ? widget.data.lines.first
        : '';
    final String? output =
        widget.data.lines.length > 1 && widget.data.lines[1].isNotEmpty
        ? widget.data.lines[1]
        : null;
    final bool expandable = output != null;
    final bool open = _expanded && expandable;
    final String summary = output != null
        ? firstLine(output)
        : (callId.isEmpty ? 'skill' : callId);

    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: expandable
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceMd,
                vertical: DswTokens.spaceSm,
              ),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.expand_more : Icons.auto_awesome_outlined,
                    size: 14,
                    color: aliases.labelTertiary,
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  Text(
                    'Skill',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelCaption,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: DswTokens.spaceSm,
                    ),
                    width: 1,
                    height: 12,
                    color: aliases.borderL2,
                  ),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w500,
                        color: aliases.labelPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: aliases.borderL1),
            Padding(
              padding: const EdgeInsets.all(DswTokens.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kSkillEn['row.instructions']!,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelCaption,
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceSm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DswTokens.spaceMd),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: aliases.markdownCodeBlock,
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        output,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
