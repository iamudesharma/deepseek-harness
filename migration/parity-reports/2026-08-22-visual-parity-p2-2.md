# Visual Parity Report — P2.2 (Web + macOS scope)

**Date:** 2026-08-22 · **Stage:** P2.2 visual parity + goldens · **Inputs:** canonical replay fixture (`apps/flutter/test/goldens/replay/parity-stream.jsonl`), React e2e snapshot corpus (`apps/web/tests/snapshots/*/ui.expected.md`, 64 scenarios), five source-level visual contract audits.

## Method

Three evidence layers, no pixel-diff pretense where a real pixel pipeline is not yet wired:

1. **Fixture-driven Flutter goldens** (committed PNGs, `matchesGoldenFile`):
   production widgets render the SAME canonical fixture the semantic-parity
   drivers consume — pixels come from real replay state.
2. **React reference corpus**: per-scenario deterministic rendered-UI
   transcripts (`ui.expected.md`) committed beside each scenario's replay
   input; Playwright screenshot plumbing exists (`support.ts`) for pixel
   captures when a specific dispute needs them.
3. **Source-level visual contract audits** (five parallel reviews comparing
   React CSS/tokens vs Flutter widgets property-by-property), producing
   y/n/partial tables per surface.

## Golden inventory (Flutter, `apps/flutter/test/goldens/goldens/`)

| Golden | Surface | State |
|---|---|---|
| chat_fixture_light.png / dark | conversation chat view | full canonical fixture: user bubble (right, bgLayer2 r12), assistant reasoning+text (left), tool ok/error cards, model-retry started marker, step groups |
| appframe_light_1680.png | app shell expanded | sidebar 280 + center + details columns |
| appframe_dark_collapsed_400.png | responsive collapse | rail sidebar, dark aliases |
| terminal_ansi_light.png | TerminalBlock/ANSI | pass/fail ANSI colors, location line, exit-code footer, head/tail cap |
| primitives_row_light.png | Pill active/idle, StateDot done/error, DsToast | token-alias driven chrome |
| button_*/modal_light.png (pre-existing) | primitives | unchanged |

Golden suite: `apps/flutter/test/goldens/surface_goldens_test.dart` (7 tests)
+ pre-existing primitives goldens. All green locally.

## Cross-runtime visual input integrity

While wiring chat goldens to the fixture, two REAL defects surfaced and were
fixed (visual work did not hide them):

1. **Production fold missed canonical tool-result identity**
   (`source.callId`); threw `tool/result for unknown call null`. Fixed in
   `ConversationNodeFolder` with legacy-shape tolerance + regression test
   ("tool/result reads canonical source.callId identity").
2. **Streaming identity was per-turn**, breaking agent loops that settle one
   assistant message per step inside one turn. Rekeyed to per-(turn,step).
3. Fixture itself had authored defects (turn tags duplicated across turns,
   duplicate recovery message) — corrected to realistic log shape; React and
   Flutter re-verified byte-identical on schema v1.1 after correction.

## Source-audit visual deltas (user-visible, by surface)

### A. Shell/layout/sidebar/theme (audit A)
- No `prefers-reduced-motion` path on Flutter; collapse is 300ms slide vs
  React's 150ms crossfade with rail-in.
- Details drag pill reveals only on strip hover (React: anywhere over details
  column); heavier resting border in dark mode.

### B. Conversation/composer/messages/tools (audit B)
- Column identity lost: React centers a 748px measure with composer-width
  coupling (card = content − 32px); Flutter renders full-bleed. (**no**)
- Bubble language diverges: user bubble loses the deepseek-tinted fill and
  22px capsule (becomes bgLayer2 r12, fixed 560px); assistant drops markdown,
  gains an artificial 640px wrap. (**no** fill/radius, partial type)
- Reasoning "Think" disclosures absent in Flutter UI; steps collapse into
  generic "Step N · x tools" tiles. (**no**)
- Tool cards: React borderless single-line rows with expand-to-IN/OUT card,
  sweep-glare running state, red reserved for terminal failure; Flutter
  always-open boxed cards on a **hardcoded dark surface** (breaks light
  theme), permanent amber/green/red icons. (**no** container; partial states)
- Streaming: no "Deep diving…" activity line, no retry countdown, no
  jump-to-bottom control; `▍` block char only. (**no**)
- Composer: floating r22 capsule vs bottom-docked bar; blue circular send
  button vs ink "Send" text capsule; inline ghost hints vs static footer
  caption. (partial/**no**)
- Model-retry marker: React disclosure with live countdown; Flutter static
  chip. Turn-error: filled card vs React's flat red row. (partial)

### C. Agent/task/input surfaces (audit C)
- Header actions: React quiet transparent text-buttons everywhere; Flutter
  filled pills/cards (subagent trigger flips to business-tinted pill when
  children run).
- State colors inconsistent: running jobs blue (ongoing) in React; Flutter
  paints green/warn depending on surface; killed = grey instead of warning.
- Popovers: React custom chrome (r12, shadow-lv3, two-line rows); Flutter
  Material PopupMenuButton (r8) + AlertDialogs; note-editor portal lost.
- Density: Flutter wraps bare strips (goal bar, workflow panel,
  deliverables row) into bordered cards.
- Accent conflicts: plan chip warn-yellow → business-blue; goal phase gains
  pills/progress bar React lacks.
- Empty/edge states: Flutter adds whole-screen empty/error screens +
  demo-data fallbacks React doesn't have.

### D. Settings/model/permissions/workspace/attachments/pickers (audit D)
- Settings shell is a different object: React 800px centered modal + 188px
  icon nav rail; Flutter full-screen page + Material TabBar. (**no**)
- Model seat opposite sides: React trailing chip opening upward two-level
  Model/Effort drill-down; Flutter leading filled pill, downward flat menu,
  no effort pane. (**no** placement, partial popup)
- Permission presets: inline settings row + RiskConfirmation primitive in
  React; dedicated radio-tile page + hand-rolled AlertDialog in Flutter
  (ported `DsRiskConfirmation` unused). (**no** surface)
- Workspace sidebar browser absent in Flutter (no tree/search/drag-reorder);
  hero picker is ActionChip overlay capped 280×320. (**no**)
- Attachments: React 64×64 thumbnail rail + drop overlay + lightbox;
  Flutter filename chips, drag-drop absent, slots unregistered. (**no**)
- Directory browse dialog (Miller columns 680×500) replaced by OS/file_picker
  choosers behind `DirectoryPickFace`. (**no** for browse UI)

### E. Terminal/overlays/dialogs/primitives (audit E)
- Block family geometry: diff/read/search/web cards r8 hairline vs React
  borderless r12; missing head/tail cap-16 + expand + copy buttons; diff
  footer stats lost; search/web capability notes lost.
- Modal mask blur (`--dsw-mask-blur`) missing; overlay skips Escape-to-close.
- Motion: hover card 400ms/100ms vs 500ms/200ms; toast ease-in-out vs
  ease-out; no reduced-motion fallbacks anywhere.
- Spec drifts: menu row min-height 32 vs 40, max-height 240 vs viewport cap;
  RiskConfirmation width 380 vs 440; toast severity superset;
  DsCodeBlock/DsMarkdown bypass the alias system entirely.

## Known implementation gaps — visual impact statement

| Gap | Visual impact today |
|---|---|
| `tool.subcall-topology` UI leg | Tool cards render flat; dispatch children exist in fold but have no card rows. Goldens document current flat state honestly. |
| `platform.drag-drop` | No drop overlay/attachment intake visuals exist to compare. |
| `platform.open-external` | No link-out affordance visuals. |
| Compaction contract mismatch (WS-Chat) | No cross-stack compaction visual claim possible; excluded from goldens. |

## Defects found & fixed during P2.2

1. Production fold rejected canonical tool-result identity (fixed + test).
2. Streaming key granularity per-turn → per-(turn,step) (fixed; no external
   pinning existed). Two consumer tests updated to carry the real host's
   `step` field — the omission was fixture drift, not contract.
3. Fixture authoring errors corrected (turn tags, duplicate message).

## Systemic themes across audits (consolidated)

1. **Chrome inflation**: Flutter wraps bare strips in bordered cards and
   swaps quiet text-buttons for filled pills across ≥6 surfaces.
2. **State-color semantics drift**: running/warn/success mappings disagree
   with React's StateDot vocabulary on jobs/subagent/plan surfaces.
3. **Material substitution**: PopupMenuButton/AlertDialog replace React's
   custom menu/risk-confirmation chrome; mask blur and Escape-close lost.
4. **Reduced-motion absent** everywhere on the Flutter side.
5. **Hardcoded dark surface** inside ToolNode card breaks light theme.
6. **Layout identity**: no centered 748px column measure; composer docked
   vs floating capsule.

## Tracker impact

Rows stay at their audit-derived statuses; visual deltas recorded here do not
promote or demote rows by themselves. Evidence paths added to relevant rows'
`tests` arrays (goldens suite). Nothing marked Verified.
