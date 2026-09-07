# Commands / input / reference / user-questions remediation — 2026-08-25 (Agent B)

Scope: the two Audited rows in the commands/input/reference/user-questions ownership area that still needed work — `platform.keyboard-shortcuts` and `dialog.hoverCard`. All 50 remaining Audited rows were re-checked by id first: none belongs to ui-commands, ui-reference, or ui-user-questions (those screens are already Integrated), so this report covers the composer/input interaction rows actually in scope. One line per paragraph.

## Ownership check

The Audited list contains no row whose React source lives under `packages/client/ui-commands`, `ui-reference`, or `ui-user-questions`; `screen.ui-input-trigger` is Integrated with fixed evidence and was left untouched per instruction. The only other HoverCard row, `component.ui-primitives.HoverCard`, targets `apps/flutter/lib/src/widgets/primitives/hovercard.dart`, which does not exist on disk — the real file is `hover_card.dart`; that primitives-family row was flagged for its owning agent, not edited.

## dialog.hoverCard → Integrated

Real implementation verified at `apps/flutter/lib/src/widgets/primitives/hover_card.dart`: `DsHoverCard` ports `HoverCard.tsx` + `HoverCard.module.css` with delayed open, 8px right-side placement, reachable card across a 100ms grace gap, viewport flip when out of right-side room, disable-suppresses/closes-immediately, and a copy affordance calling `onCopy`; it is mounted in the sidebar on workspace header rows and session rows (disabled while menu open or dragging). Default dwell was aligned 400ms → 500ms to match the React default `openDelayMs = 500` as traced in `migration/parity-reports/2026-08-24-workspace-completion.md`; nothing else referenced the old default.

New focused suite `apps/flutter/test/widgets/hover_card_test.dart` (8 tests) asserts: open only after the full dwell; close after the grace once anchor and card are both left; resting on the card cancels the close; placement flips left of the anchor near the right viewport edge (probed behaviorally through real hit testing); disabled suppresses opening and closes an open card immediately; copy row fires `onCopy` only when `copyText` is set. These widget assertions back `visual: pass` without a golden; goldens remain a Verified-stage want.

Tracker deltas: status Audited → Integrated, parityCheck visual/behavior pass with runtime/streaming/reconnect not-applicable, tests[] set to the new suite path, integrationPoints recorded for both sidebar mounts and the primitives export, evidence.testsRun/parityReport filled. platformParity stays web/macos missing — the widget is single-codebase and host-tested only, and no dedicated Web/macOS run was performed this pass.

## platform.keyboard-shortcuts → stays Audited (partial), target corrected

flutterTarget corrected from the non-existent `apps/flutter/lib/src/platform/keyboard_shortcuts.dart` to the real carrier seam `apps/flutter/lib/src/plugins/conversation/ui/conversation_shortcuts.dart`. Implemented and now tested: Enter submits via the column-mounted seam, Escape cancels the turn, Shift+Enter never matches the submit activator (native newline falls through to the field), and undo/redo activators ride Cmd on Apple hosts versus Ctrl (+Ctrl+Y) elsewhere, mirroring React's uniform `metaKey || ctrlKey` check; the composer additionally binds Cmd/Ctrl+Enter to its accelerated `_SubmitIntent`, and the mounted `InputKeyboardProducer` arbitrates ArrowUp/Down/Enter/Escape while the trigger menu is open.

Real defect found and fixed en route: the duplicated redo tables matched bare Shift+Z (typing a capital Z) on both platform branches because each dropped its accelerator requirement; activators are now defined once in `conversation_shortcuts.dart` (`undoActivators`/`redoActivators`) and consumed by `input_trigger_shortcuts.dart`, every variant accelerator-bound, with a regression assertion in the new test.

Honest gaps keep the row at partial/Audited: `InputTriggerShortcuts` is not mounted anywhere, so Cmd/Ctrl+Z|Y stays inert end-to-end (controller and stack are unit-tested only); chip Backspace/Delete occurrence deletion is not ported; empty-draft accelerated Enter queue-steer and the Enter repeat guard are not ported. Tracker deltas: flutterTarget corrected, parityCheck behavior partial (visual not-applicable), platformParity left missing pending real host verification, tests[] reduced to the three real suites, integrationPoints and gaps recorded, evidence.testsRun/parityReport filled.

## Commands executed

```
flutter analyze lib                                  → 0 errors (pre-existing warnings in other agents' files only)
flutter test test/widgets/hover_card_test.dart       → 8/8
flutter test test/plugins/conversation_render_test.dart → 6/6
flutter test test/plugins/ws_input                   → 39/39
pnpm run verify-flutter-tracker --check              → OK (112 items)
```
