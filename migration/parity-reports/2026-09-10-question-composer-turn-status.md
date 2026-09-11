# Parity report: question composer + turn status (2026-09-10)

Source: `@react-perfect-translator` harvest of
`packages/client/ui-user-questions/src/client/` (QuestionComposer,
PlanReviewPanel, draft-store, locales, both module CSS files) and
`packages/client/ui-chat/src/client/chat/ChatView.tsx` + module CSS
(`TurnStatus`). Flutter-only changes; React untouched.

## 1. Live turn status ("Deep diving…")

React (`ChatView.tsx:172-209`, `.turnStatus` / `.turnStatusClock`):

- A flow row inside the `.column` (`align-self: flex-start`, max-width
  `--dsh-chat-content-width`), not a viewport-edge label.
- Strong 14px label in brand blue with a 1.8s gradient shimmer sweep
  (`background-size: 250%`, position 100% → 0%).
- Elapsed clock after 15s: 13px/20 caption, tabular numerals, 8px left
  margin, anchored to the running turn's `turn/start`.

Flutter (`chat_view.dart`):

- The row now renders through the same `Center` +
  `ConstrainedBox(maxWidth: 748)` wrapper as every node row and is
  left-aligned inside it (previously `Padding(horizontal: 4)` at the
  list edge with a spinner + italic gray text).
- `_TurnStatus` is a stateful row: 26px, `DswTokens.deepseek500/200`
  shimmer via `ShaderMask` + `GradientTransform` (static color under
  reduce-motion), 1s ticker, `turn/start` anchor, clock at ≥15s reusing
  the existing `_formatRunDuration`.
- Locale: `chat.deepDiving` added to the conversation dictionaries
  (zh `深度求索中...`, en `Deep diving...`, mirroring ui-chat's locale).

Test: `chat_view_scroll_test.dart` "running turn status stays inside
the message column" pins the column alignment + no spinner.

## 2. Question composer (generic flow + plan review)

React (`QuestionComposer.tsx` + `QuestionComposer.module.css`,
`PlanReviewPanel.tsx` + CSS, `draft-store.ts`, `locales.ts`):

- Frame `6px / clearance+16 / 10px`, card max-width 748, max-height
  `min(60vh, 520)`, radius 20, input-major surface, panel elevation.
- Header: eyebrow 11/16 tertiary, title 16/22 w500, minimize chevron +
  cancel X on a 24px icon-button grid; minimized collapses to the
  header strip.
- Options: 40px rows, radius 12, hover/selected surface, border-l2 when
  selected; 20×20 radius-6 number seat (single) or 14×14 radius-4
  checkbox (multi) with foreground check; label 14/24 w500, recommended
  badge (accent fill / info ink) split from the label, description
  14/24 tertiary.
- Custom row: same geometry with a pencil seat (single) or checkbox
  (multi); inline auto-growing field (6-line cap), focus/typed lifts to
  the selected look; optionless requests get the framed block field.
- Footer: pager (`‹ n / m ›`) + feedback + Skip (outline) /
  Next|Submit|Submitting… (primary), 12px gaps; incomplete and
  unanswered validation with auto-jump to the first incomplete page.
- Plan review: warn strip with dot, scrollable plan body, and
  discuss / refuse / approve actions.
- Drafts live in a session-scoped store keyed by the pending request.

Flutter (`question_node_card.dart`, rewritten):

- Ported widget-for-widget with DsButton (`elevated` = web outline,
  `primary`, `ghost`) and the existing theme tokens; every border slot
  of the answer fields is pinned off because the shared
  `inputDecorationTheme` (outline + fill) would otherwise leak onto the
  transparent rows.
- State: `_index` + per-question drafts (selected/custom/skipped),
  reset per request rpcId; controllers per question id; choose
  auto-advances single-select pages, skip marks and advances (last page
  submits), custom replaces a single-select choice on the wire while
  multi-select keeps checked labels; local settle + error retention as
  before.
- Narrow widths (<420) drop the footer actions to their own
  right-aligned row — a phone card cannot hold pager + feedback + two
  buttons; React's ≤720 media query keeps one row because DOM buttons
  shrink text.
- Keys kept for tests (`question-card`, `option-<id>-<label>`,
  `question-submit`, `question-cancel`) plus `question-prev/next/skip/
  minimize` and `plan-approve/decline/discuss`.

Tests: `question_flow_paging_test.dart` (recommended split, paging +
skip-submits, custom replaces selection, multi-select keeps labels);
`question_submit_close_test.dart` updated to the DsButton primary;
`approval_plane_test.dart` batch + plan-review (keyed tap);
`mobile_conversation_test` question flow passes with the responsive
footer.

## Known gaps / notes

- Draft persistence: React keeps drafts in a session-scoped store that
  survives remounts; Flutter keeps them in card state (reset only per
  request key). Recorded in the tracker note.
- The transcript `question` chat-node mount remains a Flutter extra
  (React registers only the composer-chain entry).
- Mobile goldens (`mobile_question.png`, `mobile_approval.png`) already
  fail from pre-existing drift; the question card image changes and
  needs a deliberate re-record by its owner.
- `chat_view_matrix` (8) + `chat_view_scroll` (3) + `chat_goldens` (12)
  failures reproduce identically on clean HEAD (verified via worktree):
  test-font/extent and animation-phase drift, not this change.
