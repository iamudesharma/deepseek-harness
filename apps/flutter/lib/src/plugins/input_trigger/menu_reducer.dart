/// Menu reduction pure core — Dart port of
/// `packages/client/ui-input-trigger/src/core/menu.ts`. One group per source;
/// generation-gated settlement; empty ready groups auto-close. Zero Flutter.
///
/// Roster protocol: the `hit` event carries no source roster, so the reducer
/// cannot invent groups. Opening from a closed state the shell seeds the roster
/// with [seedGroups] and then dispatches a hit; a hit while open (query
/// refinement) resets the existing groups to pending under a new generation.
library;

import 'trigger_source.dart';

/// One menu group: one source's candidate section.
class MenuGroup {
  /// Creates a group.
  const MenuGroup({
    required this.source,
    required this.status,
    required this.items,
    this.showGroupTitle = true,
  });

  /// Source (group) name.
  final String source;

  /// Whether the group renders its title row.
  final bool showGroupTitle;

  /// `'pending' | 'ready'`.
  final String status;

  /// Settled items; empty while pending.
  final List<InputTriggerCandidate> items;
}

/// Highlight position across the flattened ready items.
class MenuHighlight {
  /// Creates a highlight.
  const MenuHighlight({required this.source, required this.index});

  /// Group (source) name.
  final String source;

  /// Item index within the group.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is MenuHighlight && other.source == source && other.index == index;

  @override
  int get hashCode => Object.hash(source, index);
}

/// A detected trigger token under the caret.
class TriggerHit {
  /// Creates a hit.
  const TriggerHit({
    required this.trigger,
    required this.query,
    required this.quoted,
    required this.position,
    required this.span,
  });

  /// Trigger char.
  final TriggerChar trigger;

  /// Text between the trigger char and the caret, live-filtered.
  final String query;

  /// True only for an open quoted `@"` token.
  final bool quoted;

  /// Token position in the draft.
  final TriggerPosition position;

  /// Token span; draftRev stamped by the caller.
  final TokenSpan span;

  @override
  bool operator ==(Object other) =>
      other is TriggerHit &&
      other.trigger == trigger &&
      other.query == query &&
      other.quoted == quoted &&
      other.position == position &&
      other.span.start == span.start &&
      other.span.end == span.end &&
      other.span.draftRev == span.draftRev;

  @override
  int get hashCode => Object.hash(trigger, query, quoted, position, span);
}

/// Closed rest state with generation 0; store initializer and test seed.
const MenuState menuClosed = MenuState(
  open: false,
  hit: null,
  generation: 0,
  groups: [],
  highlight: null,
);

/// Menu state snapshot; immutable, so unchanged reductions return [menuClosed]-
/// style identical instances that subscribers can skip by identity.
class MenuState {
  /// Creates a state.
  const MenuState({
    required this.open,
    required this.hit,
    required this.generation,
    required this.groups,
    required this.highlight,
  });

  /// Whether the menu shows.
  final bool open;

  /// The authoritative hit when open.
  final TriggerHit? hit;

  /// Monotonic per-hit generation; stale settlements are dropped.
  final int generation;

  /// One group per seeded source.
  final List<MenuGroup> groups;

  /// Current highlight or null.
  final MenuHighlight? highlight;
}

/// Menu reduction events. Source failure = silent group removal (logged).
sealed class MenuEvent {
  const MenuEvent();
}

/// New authoritative hit (null closes).
class HitEvent extends MenuEvent {
  /// Wraps the hit.
  const HitEvent(this.hit);

  /// Detected hit or null.
  final TriggerHit? hit;
}

/// One source's candidates settled for a generation.
class SourceSettledEvent extends MenuEvent {
  /// Creates the event.
  const SourceSettledEvent(
    this.generation,
    this.source, [
    this.items = const [],
  ]);

  /// Generation the fetch launched under.
  final int generation;

  /// Source name.
  final String source;

  /// Settled items.
  final List<InputTriggerCandidate> items;
}

/// One source's fetch failed for a generation (group removed silently).
class SourceFailedEvent extends MenuEvent {
  /// Creates the event.
  const SourceFailedEvent(this.generation, this.source);

  /// Generation the fetch launched under.
  final int generation;

  /// Source name.
  final String source;
}

/// Move the highlight one step in [dir] over the flattened ready items.
class MoveEvent extends MenuEvent {
  /// Creates the event (`dir`: 1 down, -1 up).
  const MoveEvent(this.dir);

  /// Step direction.
  final int dir;
}

/// Explicit close.
class CloseMenuEvent extends MenuEvent {
  /// Constant instance.
  const CloseMenuEvent();
}

/// Replace the group roster with pending groups for [sources], in order.
/// Shell-side step before dispatching a hit on a fresh menu open.
MenuState seedGroups(MenuState state, List<InputTriggerSource> sources) =>
    MenuState(
      open: state.open,
      hit: state.hit,
      generation: state.generation,
      groups: [
        for (final source in sources)
          MenuGroup(
            source: source.name,
            showGroupTitle: source.showGroupTitle,
            status: 'pending',
            items: const [],
          ),
      ],
      highlight: null,
    );

MenuState _closed(MenuState state) =>
    state.open ||
        state.hit != null ||
        state.groups.isNotEmpty ||
        state.highlight != null
    ? MenuState(
        open: false,
        hit: null,
        generation: state.generation,
        groups: const [],
        highlight: null,
      )
    : state;

MenuHighlight? _firstHighlight(List<MenuGroup> groups) {
  for (final g in groups) {
    if (g.status == 'ready' && g.items.isNotEmpty) {
      return MenuHighlight(source: g.source, index: 0);
    }
  }
  return null;
}

MenuHighlight? _validHighlight(
  MenuHighlight? highlight,
  List<MenuGroup> groups,
) {
  if (highlight == null) return null;
  for (final g in groups) {
    if (g.source == highlight.source &&
        g.status == 'ready' &&
        highlight.index < g.items.length) {
      return highlight;
    }
  }
  return null;
}

List<MenuHighlight> _positions(List<MenuGroup> groups) => [
  for (final g in groups)
    if (g.status == 'ready')
      for (var i = 0; i < g.items.length; i++)
        MenuHighlight(source: g.source, index: i),
];

bool _allReadyEmpty(List<MenuGroup> groups) =>
    groups.every((g) => g.status == 'ready' && g.items.isEmpty);

/// Pure menu reducer. A hit opens a new generation over the seeded roster
/// (null hit closes); a settlement outside the current generation, the open
/// menu, or the roster is dropped; a settlement or failure leaving every group
/// ready-and-empty auto-closes; a failure silently removes the group; move
/// cycles the highlight across ready items. Stale/no-op events return the same
/// instance so store subscribers skip rebuilds.
MenuState menuReduce(MenuState state, MenuEvent event) {
  switch (event) {
    case HitEvent(:final hit):
      if (hit == null) return _closed(state);
      return MenuState(
        open: true,
        hit: hit,
        generation: state.generation + 1,
        groups: [
          for (final g in state.groups)
            MenuGroup(
              source: g.source,
              showGroupTitle: g.showGroupTitle,
              status: 'pending',
              items: const [],
            ),
        ],
        highlight: null,
      );
    case SourceSettledEvent(:final generation, :final source, :final items):
      if (!state.open || generation != state.generation) return state;
      final idx = state.groups.indexWhere((g) => g.source == source);
      if (idx < 0) return state;
      final groups = [
        for (var i = 0; i < state.groups.length; i++)
          if (i == idx)
            MenuGroup(
              source: state.groups[i].source,
              showGroupTitle: state.groups[i].showGroupTitle,
              status: 'ready',
              items: items,
            )
          else
            state.groups[i],
      ];
      if (_allReadyEmpty(groups)) return _closed(state);
      return MenuState(
        open: state.open,
        hit: state.hit,
        generation: state.generation,
        groups: groups,
        highlight:
            _validHighlight(state.highlight, groups) ?? _firstHighlight(groups),
      );
    case SourceFailedEvent(:final generation, :final source):
      if (!state.open || generation != state.generation) return state;
      if (!state.groups.any((g) => g.source == source)) return state;
      final groups = state.groups.where((g) => g.source != source).toList();
      if (groups.isEmpty || _allReadyEmpty(groups)) return _closed(state);
      return MenuState(
        open: state.open,
        hit: state.hit,
        generation: state.generation,
        groups: groups,
        highlight:
            _validHighlight(state.highlight, groups) ?? _firstHighlight(groups),
      );
    case MoveEvent(:final dir):
      if (!state.open) return state;
      final pos = _positions(state.groups);
      if (pos.isEmpty) return state;
      final hl = state.highlight;
      var at = -1;
      if (hl != null) {
        at = pos.indexWhere(
          (p) => p.source == hl.source && p.index == hl.index,
        );
      }
      final nextIdx = at < 0
          ? (dir == 1 ? 0 : pos.length - 1)
          : (at + dir + pos.length) % pos.length;
      final next = pos[nextIdx];
      if (next == hl) return state;
      return MenuState(
        open: state.open,
        hit: state.hit,
        generation: state.generation,
        groups: state.groups,
        highlight: next,
      );
    case CloseMenuEvent():
      return _closed(state);
  }
}

/// Exact-name lookup in one source's ready group; null when the group is
/// absent, not ready, or has no candidate of that name.
InputTriggerCandidate? exactMatch(
  List<MenuGroup> groups,
  String source,
  String name,
) {
  for (final group in groups) {
    if (group.source != source) continue;
    if (group.status != 'ready') return null;
    for (final item in group.items) {
      if (item.name == name) return item;
    }
    return null;
  }
  return null;
}
