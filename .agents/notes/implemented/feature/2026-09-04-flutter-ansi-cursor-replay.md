# Agent Note: Flutter renders ANSI tool output with full cursor replay

Status: implemented

## Problem

The Flutter ANSI renderer (`plugins/conversation/ui/ansi_span.dart`) was an
honest subset of the React parser (`packages/client/ui-primitives/src/ansi.ts`):
SGR colors worked, but cursor movements — carriage return, backspace,
erase-in-line — were sanitized away, tabs and wide characters advanced no
column, and the palette was a private Tailwind-style color table instead of the
design-system tokens React maps onto. Two other surfaces were further behind:
`DsTerminalBlock` stripped every ANSI sequence and rendered plain text
("color rendering is a recorded gap"), and the tool plugin's `BashToolCard`
rendered raw output text with no ANSI processing at all, while React's bash
toolview renders `TerminalBlock` with parsed spans. A progress line such as
`1%\r2%\r…100%` therefore rendered as concatenated frames in the conversation
card, stripped text in the terminal block, and raw escapes in the bash card.

## Decision

`widgets/primitives/ansi.dart` is now the one ANSI home, a faithful port of
`ansi.ts`: OSC and non-CSI escapes stripped, per-line cursor replay into a
column buffer (carriage return, backspace, erase-in-line `K` modes 0/1/2,
tab stops as blanks, wide-character spacer columns, zero-width attachment,
trailing-CRLF drop), SGR state folding with the reference attribute-closer
semantics, and runs resolved against `AnsiColors` — the token palette
React's `TOKEN_BY_BASIC_RGB` maps to (`label-primary`, `label-tertiary`, the
state aliases, and static `blue400`), with the same rule that a run painting
its own background keeps the literal ANSI pair. Reverse swaps the resolved
pair; underline and strikethrough share one slot with the later declaration
winning; blink and vertical cursor addressing are consumed without effect,
exactly as in React.

- `parseAnsiLines` mirrors the React API (one `AnsiLine` of `AnsiSpan`s per
  output line); `ansiToSpan` joins the lines into one selectable span tree
  for whole-block callers.
- `DsTerminalBlock` renders the parsed styled lines per row — the recorded
  color gap is closed — with the head/tail cap now counting replayed lines.
- The conversation tool row and the tool plugin's `BashToolCard` both consume
  the shared renderer; `ansi_span.dart` is deleted, so the palette has one
  home.
- `plugins/` cross-surface imports reach only `widgets/primitives`, matching
  the shared-primitive role React gives `ui-primitives`.

Consciously not ported: a full terminal emulator. The replay covers per-line
cursor movement within one output card; alternate screens, scroll regions,
and full-screen TUI redraw remain out of scope, matching React's parser.
The interactive live-terminal panel (beyond this change) will need a real
emulator and is tracked under the terminal-controller plan.

## Verification

- `test/plugins/conversation_render_test.dart` pins the ported contract:
  token mapping, decorations, reverse, extended colors, replay cases
  (`100%\rOK` → `OK0%`, erase modes, wide-pair blanking, tab blanks,
  cross-line SGR threading).
- `test/widgets/primitives_p1_audit_test.dart` and
  `test/goldens/surface_goldens_test.dart` updated for styled rows; the
  terminal and chat-fixture goldens re-recorded with token-mapped colors
  (visual change is intentional: ANSI colors now render where they were
  stripped).
- `flutter analyze` clean on changed files; full `flutter test` green except
  the pre-existing connection/cache failures that also fail on a clean
  `HEAD` worktree.
