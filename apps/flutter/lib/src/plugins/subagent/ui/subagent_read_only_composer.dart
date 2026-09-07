/// Read-only composer takeover — Flutter port of `SubagentReadOnlyComposer`
/// plus the `selectReadOnlySubagent` selector from the React package's
/// `index.ts`. The claim rule is ported verbatim; registration waits for the
/// conversation plugin to declare a `conversation.composer` chain hole (the
/// Dart hub has no chain seat yet), so the widget ships with its selector and
/// tests until that seam lands.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../locales.dart';

/// Why a catalog-addressed conversation cannot accept human input.
enum SubagentReadOnlyReason { oneShot, parentUnavailable }

/// One read-only match: the reason the normal composer is replaced.
class SubagentReadOnlyMatch {
  /// Creates a match.
  const SubagentReadOnlyMatch(this.reason);

  /// Why the composer is read-only.
  final SubagentReadOnlyReason reason;
}

/// Claim the composer for one-shot history or an unavailable continuation
/// owner (ported verbatim from the React package's `index.ts`). A RUNNING
/// parent-offline continuable child keeps the default composer so its Stop
/// stays reachable; once it stops, this takeover returns.
SubagentReadOnlyMatch? selectReadOnlySubagent({
  required bool subagentAddressed,
  required bool oneShot,
  required bool parentAvailable,
  required bool running,
}) {
  if (!subagentAddressed) return null;
  if (oneShot)
    return const SubagentReadOnlyMatch(SubagentReadOnlyReason.oneShot);
  if (parentAvailable) return null;
  return running
      ? null
      : const SubagentReadOnlyMatch(SubagentReadOnlyReason.parentUnavailable);
}

/// Explain why the normal composer is unavailable for an addressed child.
class SubagentReadOnlyComposer extends StatelessWidget {
  /// Creates the read-only replacement body.
  const SubagentReadOnlyComposer({super.key, required this.match});

  /// Selector-owned reason.
  final SubagentReadOnlyMatch match;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool oneShot = match.reason == SubagentReadOnlyReason.oneShot;
    // Dictionary copy rides the registered `subagent` namespace; the en dict
    // is the rendered fallback ladder's terminal entry.
    final String title = oneShot
        ? kSubagentEn['readonly.oneShot.title']!
        : kSubagentEn['readonly.title']!;
    final String body = oneShot
        ? kSubagentEn['readonly.oneShot.body']!
        : kSubagentEn['readonly.body']!;
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
          Text(
            title,
            style: TextStyle(
              fontSize: DswTokens.fontSizeS14,
              fontWeight: FontWeight.w600,
              color: aliases.labelPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
