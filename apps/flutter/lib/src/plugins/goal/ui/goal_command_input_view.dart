/// `/goal` command-input chat-node renderer — Flutter port of
/// `GoalCommandInputView.tsx`, registered on the keyed chat-node seam under
/// React's key `command-input`.
///
/// The right-aligned bubble renders the human-entered `/goal` line without
/// ordinary message actions. The Dart fold does not emit a `command-input`
/// node family yet, so the renderer reads the seam's [ChatNodeData.lines]
/// contract: one line, the rendered command text (e.g. `/goal ship it`).
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../conversation/hub.dart' show ChatNodeData;
import '../locales.dart';

/// Renders one `command-input` node as a right-aligned `/goal` bubble.
Widget renderGoalCommandInput(BuildContext context, ChatNodeData data) {
  final ThemeData theme = Theme.of(context);
  final DswAliases aliases =
      theme.extension<DswThemeExtension>()?.aliases ??
      (theme.brightness == Brightness.dark
          ? DswTokens.darkAliases
          : DswTokens.lightAliases);
  final String text = data.lines.isNotEmpty ? data.lines.first : '';

  return Semantics(
    label: kGoalEn['commandInput.aria'],
    child: Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: aliases.stateBusinessTertiary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            color: aliases.labelPrimary,
          ),
        ),
      ),
    ),
  );
}
