# 2026-08-28 — Visual Integration Pass: Composer / Hero / Anchoring / Details

Agent V (COMPOSER / HERO / VISUAL-INTEGRATION). React source under
`packages/client/*` is the authority; every change cites the React line it
mirrors. English-only report; one line per paragraph.

## Item (a) — "Standard mode" and "workspace-write" floating at window top-right

Root cause: both chips were registered into the session header actions list.
`permission_presets_plugin.dart` registered `PermissionSeat` into
`conversation.session.header.actions` (id `permission-seat`), and
`agent_preset_plugin.dart` registered only the header label into the same list.
React has no permission seat in any header: ui-conversation's InputBar renders
the access control inline inside the tool row (`InputBar.tsx:509-511`,
mounted at `.modes` `InputBar.tsx:711-714`), and `ui-permission-presets`
registers only the `/permission` command decoration and a settings row
(`ui-permission-presets/src/client/index.ts:120-141`). The agent-preset chip
("Standard mode") belongs to the hero workspace row:
`AgentPresetSeat` registers into `conversation.hero.agentPreset`
(`ui-agent-preset/src/client/index.ts:165-169`), rendered by ConversationRoot
right after the workspace slot (`ConversationRoot.tsx:122`); only the read-only
label rides the header (`index.ts:170-177`, order -10).

Changes:

- `plugins/permission_presets/permission_presets_plugin.dart`: header seat
  registration removed (inject list narrowed to `['connection','locale']`);
  the projection-fed chip presentation stays in
  `ui/permission_seat.dart` and is mounted by the composer itself.
- `plugins/conversation/ui/composer.dart`: tool row mounts `PermissionSeat`
  inline as its first control, exactly where React renders PermissionSelect.
- `plugins/agent_preset/agent_preset_plugin.dart`: second registration added —
  `conversation.hero.agentPreset` → new compact `AgentPresetHeroSeat`
  (`ui/agent_preset_hero_seat.dart`, port of React `AgentPresetSeat.tsx`;
  roster-empty renders nothing like React `!ready → null`).
- `plugins/conversation/conversation_plugin.dart`: declared the
  `conversation.hero.agentPreset` hole (single/root — React contract
  `slots.ts:211`) and `conversation.input.plan` (single/session — React
  composer-bar children, apply.ts).
- The header label keeps its header slot but lives INSIDE the 44px
  `SessionHeaderView` row bounds (`session_header.dart` renders the hole
  inside the fixed-height Row); no overlay outside app chrome exists anymore.

What floats where now: nothing floats. Access = composer tool row; Plan =
composer tool row; agent-preset chip = hero workspace row (blank sessions);
read-only preset label = 44px session-header row when the summary carries a
preset.

## Item (b) — Composer tool row missing access and plan

Root cause: the Flutter tool row was `[attach] … [model][send]`; access sat in
the header (see item a) and plan rode `ConversationController.registerDock`,
rendered by `DocksRow` BELOW the card — React renders the plan chip inside the
tool row via the `conversation.input.plan` seat (`ui-plan index.ts:52-53`;
mount site `InputBar.tsx:713`).

Changes:

- `plugins/plan/plan_plugin.dart`: re-registered from the dock seam to
  `ctx.slots.inject('conversation.input.plan', …)`; inject list narrowed to
  `['slots','locale']`.
- `plugins/plan/ui/plan_chip_dock.dart`: builder renamed `buildPlanDock` →
  `buildPlanSeat`; doc updated to cite the React seat.
- `plugins/conversation/ui/composer.dart`: tool row order is now **access,
  plan, attach(+input.left), spacer, input.right, model, send** — mirroring
  React DOM order with the model seat immediately before send
  (`InputBar.tsx:695-758`; trailing group `rightItems → model → ContextMeter →
  stop? → send`; the ContextMeter/stop slice has no Dart port yet).
- DocksRow now shrinks to nothing when it has neither docks nor queued rows
  (React's dock renders null when empty).

## Item (c) — `/` menu opening far right of the composer

Root cause (two parts): the zero-size anchor box riding the overlay-anchor
strip was CENTERED horizontally by HoleOutlet's default-centered Column, so
every anchored surface computed its position from the card's horizontal center;
and both overlays (`input_menu_anchor.dart`, `popup_select_overlay.dart`)
computed a one-shot `localToGlobal` offset instead of tracking the anchor.
React anchors ONE surface to the card's top-left corner:
`.overlayAnchor { inset: 0 0 auto; height: 0 }` (`InputBar.module.css:113-117`)
with `.menu { bottom: calc(100% + 4px); left: 0 }`
(`MenuView.module.css:7-16`), height clamped to the space above
(`useAnchoredMaxHeight`).

Changes:

- `plugins/input_trigger/ui/input_menu_anchor.dart`: anchor is now a
  `CompositedTransformTarget` (LayerLink); the open menu is a
  `CompositedTransformFollower` (targetAnchor topLeft ↔ followerAnchor
  bottomLeft, offset −4px) so it follows resize/scroll/reflow without
  rebuilds; opens upward ALWAYS (React has no downward flip); maxHeight =
  design cap 320 clamped to the space above the card; maxWidth clamped to the
  card width (React `min(537px, 100%)`); single OverlayPortal instance kept;
  menu rows use GestureDetector (no InkWell focus steal — React combobox
  pattern keeps focus in the textarea).
- `plugins/commands/ui/popup_select_overlay.dart`: same follower treatment
  for the popupSelect shell (shared anchor surface; `/` and `@` keep one
  menu instance each through their existing single controllers).
- `plugins/conversation/ui/composer.dart`: overlay-anchor strip inset changed
  spaceMd → 0 (card-wide, matching React `inset: 0`) and wrapped in leading
  `Align` so anchor boxes sit at the card's left edge, not centered.

Verified Web + macOS share the same widget path (single Flutter composition).

## Item (d) — hero dead space / composer relationship

Root cause: `_HeroPhase` was an Expanded centered Column ABOVE a permanently
bottom-pinned composer — two disconnected regions with dead space between.
React keeps ONE resident skeleton: header outside the scrollport, transcript +
composer seat inside it; the hero phase centers the whole stack (hero chrome +
workspace row + composer card) via `.root[data-phase='hero'] .scrollBody {
justify-content: center }` with `.composerHero { padding-bottom: 32px }`
(`ConversationRoot.module.css:309-325,356-359`), and hides header chrome while
blank (`ConversationSession.tsx:72-77`).

Changes (`plugins/conversation/ui/column.dart`):

- Header + divider render only in the active phase (blank hides chrome).
- Active phase unchanged in posture: ChatView fills, DocksRow + composer below
  (sticky-footer equivalent).
- Hero phase: LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight)
  + centered Column containing headline (`conversation.hero.brand.mark`),
  workspace row (`conversation.hero.workspace` + `conversation.hero.agentPreset`
  side by side, left inset 20 per `.heroWorkspaceRow`), gap, and the RESIDENT
  `ConversationComposer` — one stack, vertically centered with the 32px foot
  pad, glow backdrop behind. No full-height dead-space column remains.
- Center-column measure token: composer card cap 780 = chat content width 748 +
  2×16 clearance (React `--dsh-chat-content-width: 748px` /
  `--dsh-composer-card-max-width: calc(748px + 32px)`,
  ConversationRoot.module.css:22-24); the composer's existing
  `maxWidth: 780` ConstrainedBox carries this value.

## Item (e) — fake "Details / Close" panel

Root cause: `app_router.dart` passed a hardcoded `_DetailsPlaceholder` as the
details slot content AND `LayoutState.details` defaulted to `kDetailsDefault`
(360) so the track booted OPEN. React boots the layout store CLOSED
(`stores.ts:50` init `details: 0`), gates column width on a non-blank current
session (`AppFrame.tsx:94-97`, width arg at :142), and renders the strict
details entry EMPTY when there is nothing to show (`AppFrame.tsx:188-191`).
The real occupant is ui-conversation's DetailsPanel (apply.ts:444-451), which
has no Dart port yet — nothing can call openDetails.

Changes:

- `routing/app_router.dart`: placeholder class deleted; `details: null` (frame
  falls back to nothing; track stays collapsed at width 0).
- `features/layout/layout_controller.dart`: `LayoutState.details` defaults to
  0 (cites stores.ts init); `openDetails` keeps `kDetailsDefault` for the
  future real panel.

## Evidence artifacts

Goldens (new): `test/goldens/visual_integration_goldens_test.dart` —
- `goldens/composer_hero_shell.png` — blank-session hero shell.
- `goldens/composer_tool_row.png` — active composer with access+plan+model+send.
- `goldens/composer_slash_menu.png` — `/` menu anchored above the card.

Contract tests (extended): `test/integration/composer_contract_test.dart` —
tool-row ORDER via widget positions, seats-inside-card bounds, workspace chip
absent from the active-session composer, `/` menu rect hugging the field's
left/top edges, plus all prior assertions kept passing.

Debug-run capture note: Marionette screenshot capture of live menus was NOT
feasible in this environment window (concurrent locale/sidebar work kept the
debug build non-compiling at capture time); goldens + widget-position
assertions stand in as the accepted evidence path per task §5.

Known concurrent-work interference (not owned here): features/sidebar/**,
runtime_services locale providers, and localized copy moved under this pass;
test copy assertions were made structure-based where localization landed
mid-flight (permission dialog, tooltips).
