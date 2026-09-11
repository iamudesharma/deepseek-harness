# Parity report: message-row spacing + below-text (2026-09-10)

Source: `@react-perfect-translator` harvest of the assistant message
footer, Produced card, To-dos bar, stats seat, and composer placeholder.
React is the behavioral reference; only Flutter files changed.

## React references

- `packages/client/ui-chat/src/client/chat/MessageIconActions.tsx:82-113`
  + `MessageIconActions.module.css:5-31,57-69` — actions row flex, gap
  8px; action 28px, padding 6, radius 28, tertiary; clock 13px/24px
  tertiary nowrap (`.timeStart` adds `padding-right:12px`, `.timeEnd`
  none — the row gap spaces it).
- `packages/client/ui-chat/src/client/chat/TurnTailNodeView.tsx:38-66` +
  `TurnTailNodeView.module.css:1-8` — root column gap 16px,
  `.actions{margin-left:-6px}`.
- `packages/client/ui-deliverables/src/client/ProducedFiles.tsx:38-88` +
  `ProducedFiles.module.css:3-37` — root grid (label + lane, col-gap
  8px, margin-top 16px, 13px/22px), label tertiary, lane row-gap 6px,
  file links (gap 5px, link color, weight 500).
- `packages/client/ui-conversation/src/client/skeleton/TodoPanel.tsx:88-120`
  + `TodoPanel.module.css:1-32` — body column gap 8, padding 6px 12px;
  header gap 10; title 13/24 w500.
- `ConversationRoot.module.css:281` — `.composerStack{gap:6px}` between
  the input-dock zone and the composer bar.
- `packages/client/ui-conversation/src/client/locales.ts:16,180` —
  `placeholder.default` EN/ZH.
- `packages/client/ui-chat/src/client/apply.ts:155-158` —
  `conversation.composer.dock` mounts `StatsLine`.

## Flutter changes

| File | Change |
|---|---|
| `chat_view.dart` | `_MessageIconActions` gaps 6→8 (×3); turn-tail `Wrap` spacing/runSpacing 2→8; clock 12px→13px, height 20/12→24/13, dropped `Padding(left:4)`; produced→actions gap 4→16 |
| `produced_files_row.dart` | Label 12/w600/caption → 13/22 tertiary regular; label→chips and chips→folder gaps 8→6 |
| `todo_panel.dart` | Outer bottom 8→6 (stack gap) |
| `locales.dart` | Added `placeholder.default` EN + ZH |
| `column.dart` | Active composer passes `hintText: t('placeholder.default')`; fixed false `StatsPills` comment |
| `session_stats_pills.dart` | Corrected headers: pills/dialogs are Flutter-originated over `StatsLine` figures; no React `StatsPills.tsx`/`TimePill`/`UsagePill` exists |

## Tests

- Updated: `conversation_test` (hint text + dictionary seeding for two
  bare-scope tests), `mobile_conversation_test` (hint text + `en` pin in
  `pumpSessionWithHistory`), `mobile_goldens_test` (tap `TextField`
  instead of hint copy), `todo_panel_alignment_test` (6px bound).
- Green: `conversation_test`, `todo_panel_alignment`,
  `deliverables_plugin_test`, `file_preview_test`, trajectory suites,
  `live_sync_test`, replay.
- Pre-existing on clean HEAD (verified via worktrees, untouched): 8
  `chat_view_matrix`, 3 `chat_view_scroll`, 3 `mobile_conversation`
  (stale `'Thinking'` assertion — React `message.think` is `'Think'`),
  13 `mobile_goldens` (toolchain pixel drift 2.5–17%). The longer hint
  adds ~0.7pp pixels on composer-visible goldens.

## Open gaps (Gatekeeper calls)

1. ~~Stats pills vs `StatsLine`~~ Resolved 2026-09-10: the dock now mounts
   `SessionStatsLine` (the React `StatsLine` port) with all groups; the
   pills widget and its dialogs were deleted.
2. ~~Produced card chrome + pill chips~~ Resolved 2026-09-10: the row is
   now the chromeless React grid (label left, plain link text, band
   thresholds, tertiary folder action).
3. `_MessageIconActions` 4th action is Share-instub vs React Branch/fork
   (turn-tail row already forks correctly).
4. Stale `'Thinking'` mobile assertion vs React `'Think'`.

## Addendum: duplicate-key root cause (same session, `r<uuid>` twins)
The `[chatView] dropping duplicate node key r…` flood on
`session-313d…` was two `ModelRetryNode`s with one `retryId`. Root
cause: the `llm/retry` upsert in `conversation_nodes.dart` searched
only top-level `_nodes`, but while a step group is open the attempt
lives in `_groupChildren` — the repeat event missed and `_append`
twinned it into the same open group (the assistant-settle path
already searched both). Fixed by making the retry/`retry-started`
correlation group-aware (replace in group + `_rebuildOpenGroup`),
mirroring the assistant pattern; `retry-started` now also marks
in-group attempts. The list-side `dedupeByKey` stays as a guard, and
its debug log fires once per key per session (`_loggedDupKeys`,
cleared on session switch). Regression test:
`conversation_nodes_test.dart` — repeat `llm/retry` in an open group
yields one `rr-dup`; verified it fails on clean HEAD with
`['rr-dup', 'rr-dup']`.

## Addendum: dock stats + produced row rewritten to the React renders
The first pass kept the Flutter-originated `SessionStatsPills` and the
produced chip card. A second reactor-perfect pass replaced both:

- `conversation.composer.dock` now mounts `session_stats_line.dart`
  (the existing `StatsLine.tsx` port): one plain centered text line,
  groups `counts | LLM · tool | TTFT · tok/s | cache hit | input ·
  output tokens`, projection-first (`sessionStats`/`tokenUsage`) with
  the window fold as fallback. `session_stats_pills.dart` and its
  dialog tests were deleted. The empty-state gate and composer bounds
  (`Padding(16,0,16,8)`, max 780) are unchanged.
- `produced_files_row.dart` now mirrors `ProducedFiles.tsx` and its
  module CSS: chromeless grid (`Produced` label left, 8px column gap,
  16px top margin), nowrap file lane (8px gaps), plain
  link-colored text buttons (14px category glyph, 5px gap, basename,
  dotted underline on hover, full path tooltip + `Open {name}`
  semantics), tertiary remainder text, and the tertiary
  `Show in folder` action. The CSS container-query bands became
  `producedShownBand` thresholds (>687/>583/>479/>375/>271 → 6/5/4/3/
  2/1 candidates), replacing the wrap-to-two-rows chip card.

Tests: `session_stats_line_test.dart` gains projection-driven group
assertions and the malformed-projection fallback;
`deliverables_plugin_test.dart` re-targets the six-link band with a
1000px surface (the fixed-width test font makes `Produced` 106px, which
left the default 800px lane at 686px — one pixel inside band five).
Both tracker rows were demoted Verified → Migrated pending gatekeeper
re-review; probe renders confirmed the two-row grid and the single-line
stats row.

## Addendum: transcript trailing scroll space (live diagnosis)

The 2026-09-10 report from the running macOS app showed ~690px of
scrollable blank under the last message. A live render-tree dump
(`ext.flutter.debugDumpRenderTree` over the running app's VM service)
identified 43 trailing list rows, each 16px and containing only
`SizedBox.shrink` — text-less assistant step messages (`a-turn3-step*`)
from tool-only steps. The fold keeps them seq-less on purpose
(`conversation_nodes.dart` `hasVisible`) so they sorted after the turn
tail (order key `1 << 30`) while the row container (12px) and node
padding (4px) still rendered each as a blank row.

Fixes in `chat_view.dart`:

1. `chatNodeHasVisibleContent(node)` — markup-less assistant rows and
   structural markers are dropped from the list up front, so no row
   padding survives them. Regression test:
   `chat_view_scroll_test.dart` "tool-only steps add no blank rows and
   keep the tail pinned" compares two histories differing only by the
   empty step messages (extents must match; fails 82 vs 162 without the
   guard, verified).
2. List bottom padding `80 + 8` → `16`: the "composer height reserve"
   is a leftover from an overlay-composer design — in this layout the
   composer is a sibling below the list, and React ChatView pads 16px
   on both vertical sides.

Verified live after hot reload: the scroll offset sits exactly at
`maxScrollExtent`, zero 16px rows remain, and the tail's footer lands
~18px above the To-dos bar (React's ~16px chat padding + row gap).
