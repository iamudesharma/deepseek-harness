/// TurnNavigator rail — compact vertical overview of loaded Turns.
///
/// Mirrors `packages/client/ui-chat/src/client/chat/TurnNavigator.tsx` +
/// `turn-navigation.ts` ChatTurnNavigationIndex. Loaded Turns with visible
/// anchors in timeline order; array identity moves only when a Turn enters,
/// leaves, or changes preview (prompt/response bounded). Marks stay 10px apart
/// until the loaded set exceeds available height, then compress to fit.
///
/// This widget is mounted alongside the transcript scrollport (not inside the
/// flow), positioned absolute right, and collapses to zero when only one turn
/// or empty. Click navigates to anchorKey row (flowTop 24).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';

/// One loaded Turn projection for the rail.
class TurnNavigationItem {
  const TurnNavigationItem({
    required this.turn,
    required this.anchorKey,
    required this.prompt,
    required this.response,
  });

  final int turn;
  final String anchorKey;
  final String prompt;
  final String response;
}

class TurnNavigatorRail extends StatelessWidget {
  const TurnNavigatorRail({
    super.key,
    required this.items,
    required this.activeTurn,
    required this.onNavigate,
  });

  final List<TurnNavigationItem> items;
  final int? activeTurn;
  final ValueChanged<TurnNavigationItem> onNavigate;

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double available = constraints.maxHeight;
        final int count = items.length;
        // React: marks stay 10px apart until loaded set exceeds available height, then compress.
        final double gap = count * 10 <= available ? 10 : available / count;
        final double barHeight = (gap - 2).clamp(6, 10);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Padding(
                padding: EdgeInsets.only(bottom: item == items.last ? 0 : 2),
                child: GestureDetector(
                  onTap: () => onNavigate(item),
                  child: Container(
                    width: 24,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: item.turn == activeTurn ? aliases.stateBusinessPrimary : aliases.borderL2,
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Derive navigation items from grouped history.
///
/// Simplified: groups by turn derived from envelope data turn field or sequential
/// order. For each turn that has a visible anchor (user or assistant), produce
/// bounded prompt (first user text truncated 80) and response (first assistant text truncated 80).
List<TurnNavigationItem> deriveTurnNavigationItems(List<dynamic> nodes) {
  // nodes are ConversationNode with turn field via StepGroupNode or UserMessageNode seq inference.
  // For standalone rail without full folder, this helper is not used directly; ChatView
  // will compute items from its folder timeline. Keep stub for widget tests.
  return const [];
}
