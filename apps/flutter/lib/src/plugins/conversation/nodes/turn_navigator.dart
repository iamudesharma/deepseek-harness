/// Turn navigation index — Flutter port of web's `turn-navigation.ts`
/// and `snapshot.ts:ChatTurnNavigationIndex`.
///
/// Groups the live history window into turn-anchored rail items
/// (turn → anchorKey → bounded prompt/response previews) derived from
/// `liveHistoryProvider` → `ConversationNodeFolder` timeline.
///
/// Grouping rule: prefer explicit [StepGroupNode.turn] when available
/// (envelope `turn` when present) else sequential user-message boundaries.
/// Each turn that has a visible anchor (user or assistant) produces an item
/// with prompt = first user text (80 chars) and response = first assistant
/// text (80 chars). Array identity is stable via reference equality.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_event_map.dart';
import '../../../core/session/session_models.dart';
import '../../../features/conversation/message_provider.dart';
import '../../../theme/app_theme.dart';
import 'conversation_nodes.dart';

/// One loaded Turn projected into the compact rail.
@immutable
class TurnNavigationItem {
  const TurnNavigationItem({
    required this.turn,
    required this.anchorKey,
    required this.prompt,
    required this.response,
  });

  /// Turn number (host turn or sequential fallback).
  final int turn;

  /// Stable node key the rail scrolls to.
  final String anchorKey;

  /// Bounded prompt preview (first user text, 80 chars).
  final String prompt;

  /// Bounded assistant response preview (first assistant text, 80 chars).
  final String response;

  @override
  bool operator ==(Object other) =>
      other is TurnNavigationItem &&
      turn == other.turn &&
      anchorKey == other.anchorKey &&
      prompt == other.prompt &&
      response == other.response;

  @override
  int get hashCode => Object.hash(turn, anchorKey, prompt, response);

  @override
  String toString() =>
      'TurnNavigationItem(turn:$turn, anchor:$anchorKey, prompt:${prompt.length}, response:${response.length})';
}

/// Tests whether two items carry the same rail state.
bool sameTurnNavigationItem(
  TurnNavigationItem? left,
  TurnNavigationItem? right,
) {
  if (left == null || right == null) return left == right;
  return left.turn == right.turn &&
      left.anchorKey == right.anchorKey &&
      left.prompt == right.prompt &&
      left.response == right.response;
}

const int _previewLimit = 80;

String _preview(String raw) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= _previewLimit) return normalized;
  return normalized.substring(0, _previewLimit);
}

String _promptText(ConversationNode node) {
  if (node is UserMessageNode) return _preview(node.text);
  return '';
}

String _responseText(ConversationNode node) {
  if (node is AssistantNode) return _preview(node.text);
  return '';
}

// ---------------------------------------------------------------------------
// Derivation
// ---------------------------------------------------------------------------

/// Derive navigation items from the live history entries.
List<TurnNavigationItem> _deriveTurnNavigationItems(
  List<HistoryEntry> entries,
) {
  if (entries.isEmpty) return const [];

  final folder = ConversationNodeFolder();
  for (final e in entries) {
    final envelope = SessionEventEnvelope.fromJson({
      'type': e.event.type,
      'seq': e.event.seq,
      'time': e.event.time,
      'data': e.event.data,
      if (e.event.ignorable) 'ignorable': true,
    });
    // Folder expects sourceEventSeqs/surfaceOp for compaction; HistoryEntry
    // drops them – not needed for turn prompt derivation.
    folder.add(envelope);
  }
  final rawNodes = folder.snapshot().nodes;
  if (rawNodes.isEmpty) return const [];

  // Group nodes by turn.
  final Map<int, List<ConversationNode>> grouped = {};
  final List<int> order = [];
  int autoTurn = 1;

  int? peekNextGroupTurn(int fromIndex) {
    for (var j = fromIndex + 1; j < rawNodes.length; j++) {
      final n = rawNodes[j];
      if (n is StepGroupNode) return n.turn;
    }
    return null;
  }

  for (var i = 0; i < rawNodes.length; i++) {
    final node = rawNodes[i];
    if (node is StepGroupNode) {
      final t = node.turn;
      if (!grouped.containsKey(t)) {
        grouped[t] = [];
        order.add(t);
        if (t >= autoTurn) autoTurn = t + 1;
      }
      // StepGroup children are the visible nodes for this turn.
      grouped[t]!.addAll(node.children);
    } else if (node is UserMessageNode) {
      final nextTurn = peekNextGroupTurn(i);
      late final int target;
      if (nextTurn != null) {
        // Merge user bubble with its following step group (same host turn).
        target = nextTurn;
        if (!grouped.containsKey(target)) {
          grouped[target] = [];
          order.add(target);
          if (target >= autoTurn) autoTurn = target + 1;
        }
      } else {
        target = autoTurn++;
        grouped[target] = [];
        order.add(target);
      }
      grouped[target]!.add(node);
    } else if (node is MarkerNode) {
      // Structural marker – no visible anchor, skip for grouping.
      continue;
    } else {
      // Other top-level nodes (Context, Assistant outside group, Tool, etc.)
      // Attach to most recent turn if any, otherwise create a new one.
      late final int target;
      if (order.isNotEmpty) {
        target = order.last;
      } else {
        target = autoTurn++;
        grouped[target] = [];
        order.add(target);
      }
      grouped[target]!.add(node);
    }
  }

  // Order is insertion order (appearance). Ensure sorted ascending for
  // deterministic rail even when compaction created gaps but appearance is
  // already sorted; we keep appearance order which equals ascending turn for
  // sequential cases. For gaps, appearance order still equals numeric order
  // because turns increase monotonically.
  final List<TurnNavigationItem> items = [];
  for (final turn in order) {
    final nodes = grouped[turn]!;
    if (nodes.isEmpty) continue;
    // Find first user (prompt) and first assistant with non-empty preview.
    UserMessageNode? user;
    AssistantNode? assistant;
    for (final n in nodes) {
      if (user == null && n is UserMessageNode) user = n;
      if (assistant == null && n is AssistantNode && _responseText(n).isNotEmpty) {
        assistant = n;
      }
      if (user != null && assistant != null) break;
    }
    // Visible anchor: user or assistant required (task filter).
    final hasVisibleAnchor = user != null || assistant != null;
    if (!hasVisibleAnchor) {
      // Fallback to web behavior: if turn has any visible node, use it.
      // We keep the task's stricter filter – skip turns without user/assistant.
      continue;
    }
    final anchor = user ?? assistant ?? nodes.first;
    final anchorKey = anchor.key;
    final prompt = user != null ? _promptText(user) : '';
    final response = assistant != null ? _responseText(assistant) : '';
    // If response empty, try last assistant with preview (web chooses last).
    String effectiveResponse = response;
    if (effectiveResponse.isEmpty) {
      for (var k = nodes.length - 1; k >= 0; k--) {
        final c = _responseText(nodes[k]);
        if (c.isNotEmpty) {
          effectiveResponse = c;
          break;
        }
      }
    }
    items.add(
      TurnNavigationItem(
        turn: turn,
        anchorKey: anchorKey,
        prompt: prompt,
        response: effectiveResponse,
      ),
    );
  }
  return List.unmodifiable(items);
}

bool _sameItems(
  List<TurnNavigationItem> a,
  List<TurnNavigationItem> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!sameTurnNavigationItem(a[i], b[i])) return false;
  }
  return true;
}

final Map<String, List<TurnNavigationItem>> _turnNavCache = {};

/// Stable navigation items per session derived from liveHistoryProvider.
///
/// Identity is stable: returns the same list instance until an item
/// actually changes (turn added/removed or preview changes).
final turnNavigationItemsProvider =
    Provider.family<List<TurnNavigationItem>, String>((ref, sessionId) {
  final entries = ref.watch(liveHistoryProvider(sessionId));
  final next = _deriveTurnNavigationItems(entries);
  final prev = _turnNavCache[sessionId];
  if (prev != null && _sameItems(prev, next)) return prev;
  // Also handle empty case where prev empty list reference should be stable.
  if (prev != null && prev.isEmpty && next.isEmpty) return prev;
  _turnNavCache[sessionId] = next;
  return next;
});

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Compact vertical rail of currently loaded Turns.
///
/// Renders a 28px wide, right-aligned column of horizontal bars:
/// - inactive bars 12×2, color [DswAliases.labelTertiary] (resting)
/// - active bar 20×2, color [DswAliases.stateBusinessPrimary]
/// Bars are vertically spaced 10px apart until the loaded set exceeds the
/// available height, then compressed to fit: `gap = count*10 <= height ? 10 : height/count`.
///
/// Hidden when fewer than two turns (React parity: compact rail without placeholder).
class TurnNavigatorRail extends ConsumerWidget {
  const TurnNavigatorRail({
    super.key,
    required this.items,
    required this.activeTurn,
    required this.onNavigate,
  });

  final List<TurnNavigationItem> items;
  final int? activeTurn;
  final void Function(TurnNavigationItem) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.length < 2) return const SizedBox.shrink();
    // Narrow viewports hide the rail like React's @container (max-width: 900px) { display: none }
    final width = MediaQuery.sizeOf(context).width;
    if (width < 900) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 400;
        final int count = items.length;
        const double inset = 6;
        // Web: 10px resting gap, rail padding 6 per end.
        final double gap = count * 10 <= availableHeight ? 10 : availableHeight / count;
        // Natural height for outer container (like --turn-natural-height)
        final double naturalHeight =
            (count - 1) * 10 + 2 * inset; // matches TurnNavigator.tsx railSize
        final double railHeight = naturalHeight.clamp(0, availableHeight).toDouble();
        // Band-clamp like React min(natural, band-64, 420)
        final double clampedHeight = railHeight.clamp(0, 420).toDouble();

        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 28,
            height: clampedHeight,
            child: Stack(
              children: [
                for (var i = 0; i < count; i++)
                  Builder(
                    builder: (context) {
                      final item = items[i];
                      final isActive = item.turn == activeTurn;
                      // Position: inset + i*gap, centered in rail like CSS top min(natural, position)
                      // For compressed case, natural position may exceed height; we cap via gap.
                      final double naturalTop = i * 10;
                      // Use min(natural, ratio) to mimic CSS `top: min(var(--natural), var(--ratio))`
                      // but with our gap logic, compressed top is i*gap, natural is i*10.
                      final double top = (gap == 10)
                          ? inset + naturalTop
                          : inset + i * gap;
                      // Enforce ratio cap for parity when count large: keep within rail
                      final double effectiveTop =
                          top.clamp(inset, clampedHeight - inset - 10).toDouble();
                      // Bar dimensions
                      final double barWidth = isActive ? 20 : 12;
                      final Color barColor = isActive
                          ? aliases.stateBusinessPrimary
                          : aliases.labelTertiary;
                      // Alternative resting color could be borderL4; task says labelTertiary vs businessPrimary
                      return Positioned(
                        top: effectiveTop,
                        right: 0,
                        child: SizedBox(
                          width: 28,
                          height: 10,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Tooltip(
                              message:
                                  '${item.prompt.isNotEmpty ? item.prompt : 'Turn ${item.turn}'}${item.response.isNotEmpty ? '\n${item.response}' : ''}',
                              waitDuration: const Duration(milliseconds: 300),
                              child: InkWell(
                                onTap: () => onNavigate(item),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: barWidth,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: barColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
