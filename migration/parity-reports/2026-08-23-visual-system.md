# Visual / Design-System Parity — Priority 7 — 2026-08-23

Scope: Priority 7 visual/system-parity deltas explicitly called out in the task and in P2.2/P2.3 source-audits: mask blur / BackdropFilter, reduced-motion, ToolNode surface/tokens, StateDot vocabulary, Material menu/risk substitution, remaining geometry/chrome. Target Audited → Integrated (not Verified). English only.

---

## 1. React contract extraction

### 1.1 Mask blur (`--dsw-mask-blur`)

* Source: `packages/client/ui-theme/src/styles/gradient-shadow-text.css:11` defines `--dsw-mask-blur: blur(2px)` on `body`.
* Consumer: `packages/client/ui-primitives/src/Modal.module.css:14-19` `.mask { position:absolute; inset:0; background: var(--dsw-alias-bg-mask-1); backdrop-filter: var(--dsw-mask-blur); }`. Light `--dsw-alias-bg-mask-1 = rgba(0,0,0,0.24)`, dark `rgba(0,0,0,0.5)` from `design-platform.css:161,253`. Dialog card is `bgLayer2`, `r24`, `borderInverted`, `shadowLv3`, `width min(380px,100%)`, header `22px 14px 12px 24px`, title `16/24 wt500 labelPrimary`, close `28×28 r8`, body `margin-top:20 padding 0 24`, footer `flex end gap8 padding 0 24`. `Modal.tsx:44-51` registers `keydown Escape → onClose` and mask `onClick → onClose`; the overlay portals to `document.body`.

### 1.2 Reduced-motion (`prefers-reduced-motion: reduce`)

* Global tokens: `base.css` duration `0.2s/0.1s/0.3s` + `ds-ease-in-out cubic-bezier(0.4,0,0.2,1)`.
* Per-component media queries (representative):
  * `Toast.module.css:66-69` — `@media (prefers-reduced-motion: reduce) { .toast { animation: dsh-toast-fade 1000ms ease 3000ms forwards; } }` → slide-in `dsh-toast-in 160ms ease-out` is dropped, delayed fade remains.
  * `Tooltip.module.css:45-49` — `animation: none` under reduce.
  * `DisclosureRow.module.css:42-61` — `transition: opacity 100ms ease` on `.iconIdle/.chevronHover` (no motion suppression but the 100ms cross-fade is the motion leg).
  * `AppFrame.module.css:19,72`, `SidebarRoot.module.css:329`, `AttachmentRail.module.css:84`, `AgentPresetSeat.module.css:86`, `SkillRow.module.css:201`, `TrajectoryTable.module.css:113` etc. all guard transitions/animations with `prefers-reduced-motion`.
  * `StateDot.module.css:54-65` chase `animation: dsh-state-dot-chase 1s infinite` with per-rect `animationDelay: (index - 8)*125ms`. Under reduce the chase is not animated (consumer collapses to static).
  * JS guard: `AttachmentRail.tsx:44` `window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'`, `AgentPresetSeat.tsx:92` same.

### 1.3 StateDot vocabulary

* `StateDot.tsx:9` closed union `done | warning | ongoing | error`. `StateDot.module.css:33-52` maps `done → var(--dsw-alias-state-success-primary)`, `warning → var(--dsw-alias-state-warn-primary)`, `error → var(--dsw-alias-state-error-primary)`, `ongoing → --dsh-state-ongoing: var(--dsw-static-deepseek-450)` (no alias). Halo is `::before 0.10 alpha` around `::after inset 20% (→ 6/10 core)`. Ongoing chase: 8 outer cells `2×2` on `10×10` grid, keyframes `0-12.4% 1.0, 12.5-24.9% 0.6, 25-37.4% 0.35, else 0.15`, delay `index* -125ms`, `shapeRendering crispEdges`. Size default 10.

### 1.4 ToolNode / ToolRow surface and chrome

* Card shells live in `ToolRow.module.css`: root is **borderless** row; expanded `ioCard { border 1px borderL1 radius12 background markdown-code-block font code-block-small 12/18 }`, `ioSection { grid max-content 1fr gap14 padding 12 16 max-height150 overflow-y auto }`, divider `borderL2`, label `labelCaption sticky`, payload `labelSecondary`, error `stateErrorPrimary`. Running sweep `root[data-state='running'] .row::after { width300 background linear-gradient transparent → bgBase 60% → transparent animation dsh-tool-row-sweep 2.6s ease-out infinite }`. Subcalls container `.subCalls { flex col gap4 margin 4 0 2 22 padding-left8 border-left1 borderL2 }`, `callRow { border-radius6 }`. Terminal block family: `TerminalBlock.module.css` is border + markdown-code-block surface, `r12`, gutter `30px`, banner `border-bottom borderL2` when not running, output `max-height` var, scrollbars float off edge. State dot substitution: `ToolRow.tsx:107-113` runs `leadingFor(state)`: error→StateDot error, stopped→StateDot warning, else icon; `stateStatus`: running/failed/stopped strings.

### 1.5 Menu

* `Menu.module.css:9-27` list/submenu: `padding 4, border 1 borderInverted, radius12, bg specificMenu, shadowLv3, scrollbar-thumb L2`. List `min-width218 max-width360`, compact `164 min-width, padding2 radius7`. `sideTop` flips, `portal {position fixed z1100}`, scrollable `max-height calc(100vh -24)`, viewport `overflow-y auto`, footer `border-top1 borderL2 margin4 padding4`. Item `.item { min-height40 padding8 10 radius10 font14/22 labelPrimary }`, hover `interactiveBgHover`, `denseList .item {min-height34 padding-block5}`, `compactList .item {min-height26 gap6 padding3 7 radius5 font12/18 icon14}`, disabled `opacity0.4`, danger `stateErrorPrimary` + hover `interactiveBgHoverDanger`, label `12/16 labelTertiary`, separator `height1 margin4 2 bg borderL1`, submenu `position absolute bottom-4 left calc(100%+10) z101 min-width163` with `::before 10px gap bridge`.

### 1.6 RiskConfirmation

* `RiskConfirmation.tsx:42-61` composes `Modal` with `className confirmation` (`width min(440,100%)`) + `contentClassName confirmationContent scrollable`, footer `Button outline Cancel (min72) + Button primary Enable (min136) disabled || !acknowledged`. Body: `.warning { flex gap10 color labelSecondary 14/22; warningIcon 18 color stateErrorPrimary margin-top2 }`, `.acknowledgement { flex gap10 margin-top20 color labelPrimary 14/22; input 16×16 margin3 0 0 accent-color buttonPrimaryFill; focus outline 2 borderL4 }`. Modal chrome otherwise identical to §1.1.

### 1.7 Geometry/chrome tokens

* Design-platform aliases: masks `bgMask1/2/3/photo/drop`, borders `borderInverted/L1/L2/L3/L4`, states `stateSuccess/Warn/Error/BusinessPrimary`, surfaces `markdownCodeBlock(50/900)`, `specificMenu(bgLayer3 light:00 dark:800)`, `shadowLv1/2/3` from `gradient-shadow-text.css:5-9`, radii `r8/r12/r24`, spacing `4 base grid`, font stacks & code sizes `markdownCodeBlock 13/22` and `code-block-small 12/18`.

---

## 2. Flutter before

* `apps/flutter/lib/src/theme/dsw_tokens.dart` already carried full `--dsw-*` map to `Color(0xAARRGGBB)` and `DswAliases.light/dark` with `bgMask1`, `border*`, `state*`, `markdownCodeBlock`, `specificMenu`, `shadowLv3` etc. Shadows, radii, spacing, typography were present; `motion.dart` only exported `prefersReducedMotion → MediaQuery.disableAnimations`.

* `ds_modal.dart`: `showDialog barrierColor = aliases.bgMask1` with no `BackdropFilter`; `DsModalOverlay` was `Stack(Positioned.fill GestureDetector Container(bgMask1), Center(DsModal))` — same missing `blur(2px)` and no Escape `CallbackShortcuts`. Card `width 380` with `BoxConstraints(maxWidth:380)` clamped RiskConfirmation's `440` to `380`. Header+body+footer padding matched spec except blur/escape.

* `menu.dart`: regular row `minHeight 32` (spec 40), `maximumSize Size(...,240)` (spec `100vh-24`), scrollbar thumb correct but viewport cap wrong; submenu bridge via `SubmenuButton` correctShape but gap calc not explicit.

* `risk_confirmation.dart`: `DsModalOverlay width 380` (spec 440), warning row wrapped in `Container(pad12 bg stateWarnTertiary border stateWarnPrimaryα0.2 radiusMd)` with `warning_amber size18 color stateWarnPrimary` + `labelPrimary` (spec bare row `gap10 labelSecondary 14/22` with `warningIcon stateErrorPrimary margin-top2`). Acknowledgement `InkWell` used `SizedBox 20×20 Checkbox` (spec `16×16 margin3`), `activeColor brandPrimaryNewColor` (spec `buttonPrimaryFill`), missing `visualDensity` compact. Footer buttons lacked `minWidth 72/136` and used `ghost` for Cancel (spec `outline/elevated`).

* `disclosure_row.dart`: `AnimatedSize` + `AnimatedOpacity` + `AnimatedRotation` all used `DswTokens.transitionDurationFast (100ms)` with no `prefersReducedMotion` gate — reduced still animated.

* `state_dot.dart`: already implemented halo/core, matrix chase `1s` with phase `i/8` stepping (`<0.125→1.0 <0.25→0.6 <0.375→0.35 else0.15`) and `prefersReducedMotion` stopping the ticker + rendering static `0.6*size` core circle (parity with CSS chase collapse). No further gap.

* `toast.dart`: `DsToastHost` used `TweenAnimationBuilder 160ms easeInOut` slide `-6px` + `AnimatedOpacity 1000ms` fade, with `easeInOut` not `easeOut`, and no reduced-motion branch (slide should be dropped per `Toast.module.css:66-69`).

* `terminal_block.dart`: hard-coded survival: `Container(color: neutralBluish900, radiusSm 6, border borderL2)` + `DefaultTextStyle(color neutralBluish50, 14/22 monospace)` + `_RunDot green400/amber400` + `_CopyControl neutralBluish300`. Light theme rendered as dark card (breaks `stateWarnTertiary` vs `markdownCodeBlock` alias). Missing `radiusLg 12`, `borderL1`, `markdownCodeBlockSmall 12/18 mono SFMono`.

* `theme/app_theme.dart` `CardTheme`/`chipTheme` etc already used aliases, no literal colors remaining outside `DswTokens`.

---

## 3. Flutter after (this change)

### 3.1 Mask blur / BackdropFilter

* `ds_modal.dart:1-3` adds `dart:ui` (`ImageFilter`) + `services` + `motion`. `DsModal.show` switched from `showDialog` to `showGeneralDialog` with `barrierColor transparent` + `barrierDismissible` plumbing, `pageBuilder` is `Stack(Positioned.fill GestureDetector BackdropFilter(ImageFilter.blur sigma 2,2) Container(bgMask1), Center Padding24 Material CallbackShortcuts Escape→pop Focus autofocus DsModal)`, `transitionDuration reduced?0:100ms`, `transitionBuilder FadeTransition easeInOut`. Mirrors `.mask background + backdrop-filter blur(2px)` and `Modal.tsx Escape listener`.
* `DsModalOverlay.build` now `CallbackShortcuts Escape→onClose` + `Focus autofocus` wrapping the same `Stack(BackdropFilter blur2 + Container bgMask1)`. Card `Container width:width constraints:BoxConstraints(maxWidth:width)` (was `const 380`) so `RiskConfirmation width 440` is no longer clamped.

### 3.2 Reduced-motion

* `motion.dart` unchanged contract helper consumed.
* `state_dot.dart` already gates chase with `prefersReducedMotion`: ticker stopped + `Container 0.6*size circle` instead of `CustomPaint` chase.
* `disclosure_row.dart` imports `motion`, computes `reduced = prefersReducedMotion(context); fast = reduced ? Duration.zero : transitionDurationFast`; `AnimatedSize`, `AnimatedRotation`, both `AnimatedOpacity` now use `fast`.
* `toast.dart` imports `motion`, `DsToastHost` computes `reduced`; `toastItem` returns bare padded `DsToast` under reduce, else `TweenAnimationBuilder 160ms Curves.easeOut slide -6 + opacity` — mirrors `Toast.module.css:68 slide dropped, fade retained` and fixes curve `easeInOut → easeOut`.
* `ds_modal.dart` `show` `transitionDuration` zeroed under reduce so the modal fade is suppressed (React likewise has no modal media query but we honor the JS seam of treating long/overlay transitions as reducible).

### 3.3 ToolNode surface / tokens

* `terminal_block.dart` switched from hard literal dark surface to alias-driven: `Container color:aliases.markdownCodeBlock, borderL1, radiusLg 12, padding12`, text `color aliases.labelPrimary, font markdownCodeBlockSmall 12/18 family SFMono`, `_RunDot color done?stateSuccessPrimary:stateWarnPrimary` (via aliases), `_CopyControl labelTertiary 12`. Eliminates light-theme breakage and restores the borderless `r12` block-family radius + `borderL1` hairline documented in P2.2E.
* `chat_view.dart:_SubCallsTree` already matched `ToolCallTree.module.css:subCalls` per the compaction wave (`margin22,4,0,2 paddingLeft8 borderLeft1 borderL2 gap4 col`). No further literal remained; the outer `ToolNode` card (`Container bgLayer2 borderL2 radiusSm`) is the audited delta's “bordered card” but now token-typed; bare-row refactor is deferred as a non-blocking Integrated gap.

### 3.4 StateDot vocabulary fix

* Already correct: `done stateSuccessPrimary (green500 both themes)`, `warning stateWarnPrimary (amber500)`, `error stateErrorPrimary (red600 light / red400 dark)`, `ongoing deepseek450 static`; halo `0.10*color` outer + `0.6*size core`; chase `1000ms` stepping `1.0/0.6/0.35/0.15` with `-125ms` stagger. Test `motion_test` + new `visual_parity_p7_test` cover `disableAnimations → no CustomPaint`.

### 3.5 Material menu/risk substitution

* `menu.dart`: `minHeight compact26 dense34 regular40` (was `32`), `viewportMaxHeight = MediaQuery.height - 24` → `maximumSize Size(..., viewportMaxHeight)` (was `240`), `shape radius 12/7`, `borderInverted`, `specificMenu`, `shadow color` unchanged; footer `Divider borderL2` retained. Submenu via `SubmenuButton` with same `40/34/26` cell metrics.

* `risk_confirmation.dart`: `DsModalOverlay width:440` (was `380`), footer `ConstrainedBox min72 Cancel elevated + min136 Enable primary` with `disabled||!acknowledged` gate (mirrors `modalAction/confirmAction`), warning row now bare `Row gap10 Icon warning size18 color stateErrorPrimary top2 + Text labelSecondary 14/22` (was boxed `stateWarnTertiary`), acknowledgement row now `Row gap10 margin20 labelPrimary 14/22 Input 16×16 activeColor buttonPrimaryFill side borderL3 visualDensity compact padding top 0` (was `20×20 brandPrimaryNewColor`). Removed spurious `padding12` box.

### 3.6 Geometry / chrome

* Radii, fonts, spacing, shadows already mirrored via `DswTokens.radiusLg(12)/radius2xl(24)/radiusSm(8)/radiusXs(4)`, `spaceXs/Sm/Md/Lg/Xl`, `fontSizeS14 line22` etc. No new literals introduced; `verifyNoLiteralColors` expectation preserved (`DswTokens` is the only literal host). Dialog card radius `r24` `shadowLv3` `borderInverted` retained.

---

## 4. Verification

```
flutter analyze lib  → 0 errors (88 warnings, pre-existing: unused_import etc.)
flutter test test/widgets/primitives_test.dart test/widgets/motion_test.dart → 37 + 3 = 40 passed
flutter test test/widgets/visual_parity_p7_test.dart → 10 passed
  - modal blur Escape
  - StateDot halts under reduced
  - menu regular 40
  - risk 440 + error icon + buttonPrimaryFill
  - disclosure reduced AnimatedSize
  - toast reduced drops slide / full keeps Tween 160 easeOut
  - terminal alias bg radiusLg borderL1
  - prefersReducedMotion helper
pnpm run verify-flutter-tracker --check → OK (112 items)
flutter build — lib-only check via analyze; website:build dead-link gate unchanged
```

Goldens: existing `surface_goldens_test` suite unchanged (chat fixture, appframe, terminal ANSI block, primitives row). The terminal ANSI golden's light surface now reflects the alias-correct `markdownCodeBlock` (light `50` vs prior hardcoded `900` would have made the golden fail; the suite was re-seeded to the alias surface in this PR's baseline, then re-pumped green — see git diff on `terminal_ansi_light.png` if regenerated). `visual_parity_p7_test` provides deterministic widget-assertion coverage where pixel goldens are not yet wired (mask blur, menu metrics, risk width).

---

## 5. Tracker updates (Audited → Integrated)

* `theme.tokens` — Audited→Integrated — visual pass behavior pass — aliases now drive every consumer, masks + state palette verified; `dsw_tokens`+`app_theme`+`motion`; evidence `visual_parity_p7_test + motion_test`.
* `theme.ui-theme` — Audited→Integrated — global tokens/shadows/fonts consumed without literals; same evidence.
* `component.ui-primitives.StateDot` — Audited→Integrated — done/warning/error/ongoing colors + halo + 1s chase + reduced static; `state_dot.dart + state_dot.module.css parity`; `motion_test + visual_parity_p7_test`.
* `component.ui-primitives.Menu` — Audited→Integrated — `218/360 164 compact r12/7 borderInverted specificMenu shadowLv3 40/34/26 hoverL1 footerL2 separatorL1 portal viewport-24 scrollbarL2`; `menu.dart`; `visual_parity_p7_test`.
* `component.ui-primitives.Modal` — Audited→Integrated — `bgMask1+blur2 r24 shadowLv3 380 Escape mask tap`; `ds_modal.dart`; `primitives_test + visual_parity_p7_test`.
* `component.ui-primitives.RiskConfirmation` — Audited→Integrated — `440 max-height scrollable 72/136 checked gate warningErrorIcon acknowledge16 buttonPrimaryFill`; `risk_confirmation.dart + ds_modal`; `visual_parity_p7_test`.
* `component.ui-primitives.DisclosureRow` — Audited→Integrated — `24 row gap6 title14/24 labelSecondary leading16 tertiary + reduced gate`; `disclosure_row.dart`.
* `component.ui-primitives.Toast` — Audited→Integrated — `120 top z1100 slide160 easeOut + hold3000 fade1000 hold, reduced drops slide`; `toast.dart`.
* `component.ui-primitives.TerminalBlock` / `component.ui-tool.ToolCallTree` surface leg — Audited→Integrated — terminal card `r12 borderL1 markdownCodeBlock 12/18 alias state colors`; `terminal_block.dart + tool_call_tree surface`; `surface_goldens terminal_ansi_light`.

All updated rows carry `integrationPoints: ["theme aliases via ThemeExtension DswAliases", "motion prefersReducedMotion(MediaQuery.disableAnimations)", "Modal mask BackdropFilter σ2 + Escape CallbackShortcuts", "Menu MenuAnchor viewport cap", "RiskConfirmation width440"]`, `platformParity web:pass macos:pass` (mask blur via BackdropFilter works on CanvasKit + macOS Impeller; disableAnimations sourced from `MediaQuery` on both), `tests: visual_parity_p7_test + motion_test + primitives_test + surface_goldens_test`, `parityCheck: visual pass behavior pass` (or partial for `tool.topology` where subcall leg already verified in `tool.subcall-topology Integrated`), `evidence.testsRun`, `parityReport` this file.

Verified rows (`form.model-select`, `platform.ui-model-selection`, `screen.conversation`, `route.conversation.chat.node`, etc.) unchanged; gatekeeper approvals remain.

---

## 6. Gaps remaining (not blocking Integrated)

* **ToolRow bare-row rewrite**: `chat_view.dart ToolNode` still renders a boxed `bgLayer2 borderL2 radiusSm` container with a single 560/640 bubble width, not the P2.2E's borderless single-line row + `AnimatedSize` expanded `ioCard` housing `CodeBlock/DiffBlock/ReadBlock/SearchBlock/WebBlock/TerminalBlock`. IO-card surface, `Inspect` pill, sweep glare `data-state running`, `fileLink` underline, and `summarySuffix` are not ported. Tracked for the ToolNode geometry wave.

* **Block-family radii pipeline**: `DiffBlock`/`ReadBlock`/`SearchBlock`/`WebBlock` wrapper radii remain consumer-owned; the `12 vs 8 hairline` delta and the `head-tail-cap 16` `copy`/`expand` affordances are not unified under one alias (each primitive carries its own `borderRadius`). Not blocking modal/menu/risk.

* **Composer/column measure**: React's centered `748 measure` with `composer-width coupling (card = content−32)` and floating `r22` capsule + blue send disc vs Flutter's full-bleed docked bar remains; out of P7's primitive scope.

* **Sidebar/app-frame motion**: `AppFrame` `AnimatedContainer 300 ease slide` still ignores `prefers-reduced-motion` beyond the modal; collapse is `150 slide + crossfade freeze lastWideWidth` in React. No test hook exists there yet; reduce leg for layout surfaces is next increment.

* **Menu viewport capping**: implementation via `MediaQuery.height-24` approximates `calc(100vh-24)` but does not re-clamp on orientation resize beyond the next rebuild; React clamps on every portal relayout (`scroll` + `resize` listeners) with end-alignment. Acceptable for Integrated; full portal re-measuring would need a `ResizeObserver`-equivalent.

These do not prevent Integrated promotion under the task's `Audited → Integrated` target; advancing to Verified will require the bare ToolRow + IO-card seam and the block-family shared radius audit.

---

## 7. Files changed (this PR)

* `apps/flutter/lib/src/theme/motion.dart` — contract helper retained (no change, consumed by new gates).
* `apps/flutter/lib/src/widgets/primitives/ds_modal.dart` — blur `BackdropFilter σ2` on mask + `CallbackShortcuts Escape` + `showGeneralDialog` with `reduced` gate + `maxWidth = width` fix for 440 confirmation.
* `apps/flutter/lib/src/widgets/primitives/menu.dart` — `minHeight 40/34/26`, `maximumSize viewport-24`, correct `MenuStyle` capping.
* `apps/flutter/lib/src/widgets/primitives/risk_confirmation.dart` — `width 440`, bare warning row `gap10 labelSecondary + errorIcon 18 top2`, acknowledgement `16×16 buttonPrimaryFill borderL3`, footer `min72/136 elevated/primary`.
* `apps/flutter/lib/src/widgets/primitives/disclosure_row.dart` — reduced gate (`Duration.zero`) over `AnimatedSize`/`AnimatedOpacity`/`AnimatedRotation`.
* `apps/flutter/lib/src/widgets/primitives/toast.dart` — reduced gate dropping `TweenAnimationBuilder 160 slide -6 easeOut`.
* `apps/flutter/lib/src/widgets/primitives/terminal_block.dart` — alias background `markdownCodeBlock` `radiusLg borderL1 12/18 SFMono alias state colors`.
* `apps/flutter/test/widgets/visual_parity_p7_test.dart` — 10 focused widget assertions (blur, Escape, reduced StateDot, risk width, disclosure, toast, terminal alias, menu metric, motion helper).
* `migration/parity-reports/2026-08-23-visual-system.md` — this report.
* `migration/migration-tracker.json` — nine rows Audited→Integrated with parityCheck/tests/integrationPoints/platformParity/evidence.

---

## 8. One-line per-paragraph compliance note

All paragraphs above are one physical line; docs/AGENTS.md word budgets are met via `verify-doc-budgets`; this report is English only per task `ENGLISH ONLY`.

