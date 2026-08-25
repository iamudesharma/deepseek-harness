# Parity report — 2026-08-23 drag-drop + attachment (platform.drag-drop, platform.ui-attachment)

## Scope
- `platform.drag-drop` — `Audited → Integrated`
- `platform.ui-attachment` — `Integrated` (parity upgraded)
- Related: `screen.conversation` hero/composer slot (unchanged Verified)

## React contract extracted
- Source: `packages/client/ui-attachment/src/client/ComposerAttachments.tsx` + `AttachmentRail.tsx` + `DropOverlay.tsx` + `labels.ts` + `ImageLightbox.tsx`
- Owner: `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx` (limits, canAcceptDrop) + `service.ts` (draftAttachments + previewUrl) + `contract/slots.ts` (ComposerAttachment shape)
- Contract:
  - `ComposerAttachment = { kind:'image', id: DraftAttachmentId, file: File, previewUrl: string }` — `id: crypto.randomUUID()`, `previewUrl: URL.createObjectURL(file)`
  - Owner props: `attachments, canAcceptDrop, onAddImages(files=>string|null), onRemoveImage(id), dropLimits {count,size}`
  - `canAcceptDrop = !locked && !machineBusy && addImages!=undefined` (InputBar line 467)
  - Document listeners: `dragenter` (Files type → preventDefault, depth++, dragActive=true), `dragover` (preventDefault, dropEffect copy/none by gate), `dragleave` (clamped decrement, viewport-leave reset), `drop` (preventDefault, reset, if canAcceptDrop then onAddImages([...files])), `dragend` reset
  - Pre-check order in `intakeImages` (InputBar 440): mediaTypes → `addImages` defer to authoritative (format error), then `count` (staged+incoming > maxImagesPerMessage), then `per-file size`, then `total` (staged sum + incoming sum > maxMessageImageBytes); authoritative host check repeats at submit for bypassers; rejection via toast
  - `DropOverlay` visual: fixed inset 0, z 1000, `pointer-events:none`, frosted `bg-mask-drop` + blur, illustration (tilted cards, blocked variant), title `dropTitle` / `dropBlocked`, desc `dropDesc` with `count,size` when accepting; body portal
  - `AttachmentRail` visual: 64px cards (16px radius, border l2 thin, cover img), hover-revealed 18px remove (contrast fill/inverted, opacity 0→1, coarse→1), paging arrows overlaid at 4px inwards (24px circle, border, shadow lv2, input-major bg), hidden scrollbar (`scrollbar-width:none`, `::-webkit-display:none`), wheel `deltaY`→horizontal with `LINE`/`PAGE` normalization and 60px clamp, ResizeObserver recomputes edges, smooth paging `clientWidth-64` min 200, grow → `scrollLeft=max`, edges slack 1px
  - `ImageLightbox` presentation: full mask `bgMaskPhoto`, dialog centered, swipe/next/prev, close, name, 900x700 constraint
  - Limits display: `imageSizeText(bytes)` → `NMB` integer or 1-decimal; `dropLimits = {count:maxImagesPerMessage, size:imageSizeText(maxImageBytes)}`

## Flutter implementation
- Unified model: `ComposerAttachment` owned by `features/conversation/composer_controller.dart` (`id` stable DraftAttachmentId `att-<micros>-<seq>`, `name`, `path`, `mimeType`, `size`, `previewUrl`). Equality: non-empty `id` → id equality; empty (legacy const fixtures) → name+path fallback so existing tests keep passing. Factory `ComposerAttachment.create` generates id+previewUrl (=path). Re-exported from `features/attachment/attachment_provider.dart` → no second type.
- Controller: `composerControllerProvider` family (per session) `addAttachments` (dedupe via equality), `removeAttachmentById`, `removeAttachmentAt`, `clearAttachments`. Staging service `AttachmentStagingService` retained for WS-surfaces but now imports same type; its `add` dedupes by `id`.
- Drag-drop seam: `platform/drag_drop.dart` `DroppedFile {name,mimeType,size,path}` (web `DataTransfer.files` vs macOS `XFile` unified), `ImageLimits {mediaTypes,maxImagesPerMessage,maxImageBytes,maxMessageImageBytes}`, `DragDropController extends ChangeNotifier` (depth `_depth`, gate `_canAcceptDrop`, limits, `stagedCount` + `stagedTotalBytes`). Methods: `configure`, `dragEntered`/`dragLeft`/`reset`, `dropped` (format check → defer to `onAddImages` authoritatively, else `_preCheck` → count/per-file/total(staged+incoming) → `onRejected` vs `_forward`). `limitsText` → `Up to N images, each under S`. Vendor: `desktop_drop ^0.6.1` unified via `DropTarget` (`onDragEntered/Exited/Done/Updated`) — widget wraps whole conversation via `DocumentDropScope`.
- Intake: `plugins/conversation/ui/composer.dart: intakeComposerImages` mirrors `InputBar.intakeImages` order plus staged-total (`staged.fold + files.fold`), creates `ComposerAttachment.create(name,path,mimeType,size,previewUrl:path)`.
- Wiring: `ConversationScreen` owns `DragDropController` per session, `_configureDropGate` post-frame sets `canAcceptDrop = !running` (locked via session missing covers `locked`), `stagedCount` and `stagedTotalBytes` from `composerControllerProvider`; `didUpdateWidget` recreates controller on session switch. `DocumentDropScope` wraps both hero and column (`DropTarget` → `Stack` with `Positioned.fill(DropOverlay)`). `onAddImages` reads current `composerControllerProvider` at drop time.
- Rail: `widgets/attachment_rail.dart` `AttachmentRail` (ScrollController edge recomputation 1px slack, growth-jump to max, wheel `PointerScrollEvent.dy→dx` with 60 clamp, horizontal `ListView.separated` 10 gap, hidden scrollbar, `LayoutBuilder` resize observer, paging `viewport-64` clamp 200 smooth 280ms cubic). `_RailItem` 64×64 `InkWell→Ink` with border+overlay, cover `Image.network` for http/blob/data else placeholder `Icon(image_outlined)` — native path placeholder deferred to `dart:io` seam (no `dart:io` import on web). Hover `MouseRegion` drives `AnimatedOpacity` 200ms; remove via `InkWell → addAttachment id` (nullable `onRemove` hides control when locked/sending). Arrows `_ArrowButton` (filled input-major, border l2, shadow via elevation).
- Lightbox: `AttachmentLightbox` dialog `Colors.black 0.92`, constrained 900×700, `Image.network` for web URLs else placeholder container `bgLayer2` + name, close `IconButton`, bottom name label.
- Composer: `ConversationComposer` replaces `Wrap` filename chips with `AttachmentRail` (padding bottom `spaceSm`), `onOpen` → `showDialog AttachmentLightbox`, `onRemove` → `removeAttachmentById(id||name)` when `enabled && !isSending` else null (removes control). Picker `_pickImages` via `file_picker` feeds same `intakeImages` path. `onRejected` → `SnackBar`.
- Overlay: `plugins/attachment/ui/drop_overlay.dart` `IgnorePointer` + `Semantics liveRegion` + `Container bgOverlay 0.72` centered column with `_DropIllustration` (stacked 44×44 rotated cards + center 45×44, colors 9CE5ED/679EFE/3964FE vs tertiary/warn when disabled, icons `block`/`add_photo_alternate`), `Text` title 16/600 + limits 14 secondary.
- Limits provider: `plugins/attachment/attachment_limits.dart` + `platform/drag_drop.dart` `ImageLimits` share (current duplicated — next sweep can collapse to one import).
- Known gap: native file thumbnail real bytes not shown (placeholder icon) because web-safe build cannot import `dart:io` `File`; deferred to conditional `Image.file` seam.

## Decisions
- Kept `desktop_drop` unified (no `flutter_dropzone`): supports web+macOS via `DropTarget` with scale correction; document-level via full-screen wrapping rather than global `document` listeners — matches React's document semantics for conversation viewport.
- Unified `ComposerAttachment` in `composer_controller.dart` (session-scoped source) and re-exported from `attachment_provider.dart` to satisfy requirement of single model; dedupe keeps legacy fallback to avoid breaking const fixtures while real drops dedupe by stable id.
- Preserved `AttachmentStagingService` for existing WS-surface tests but made its type unified; migration can deprecate after WS-surface consumers move to session provider.
- `stagedTotalBytes` added to controller because React total check includes existing draft sizes; previous Flutter impl ignored it.
- `ImageLimits` duplicated across `platform/drag_drop.dart` and `attachment_limits.dart` — left for next sweep to collapse; behavior identical.
- `dart:io` excluded from rail to keep `flutter build web` clean; native `Image.file` deferred.

## Tests
- `test/platform/drag_drop_test.dart` (21 cases):
  - depth counter / reset / clamp
  - blocked gate silent
  - accepted gate forwards+resets
  - pre-check order format→count→size→total
  - count includes stagedCount
  - per-file size
  - total includes incoming and staged+incoming (new: stagedTotalBytes 80+80>150)
  - null limits defer
  - intake stages with generated id+previewUrl, unique ids, total with staged, within budget stages
  - unified model: unique ids, legacy const dedupe fallback, id dedupe
  - DropOverlay: enabled invites + shows limits, disabled names block + hides limits, IgnorePointer true
- `test/widgets/attachment_rail_test.dart` (5):
  - renders one card per attachment
  - single-click invokes onOpen
  - remove invokes onRemove (via close icon)
  - when onRemove null no close icon
  - lightbox placeholder when no preview
- `test/unit/composer_controller_test.dart` (existing, 25+)
- `test/plugins/ws_surfaces/ws_surfaces_plugins_test.dart` (attachment staging dedupe etc.)

## Verification
- `flutter analyze lib` — 0 errors (90 warnings/info, 0 errors)
- `flutter test test/platform/drag_drop_test.dart test/widgets/attachment_rail_test.dart` — 26 pass
- `flutter build web --release --dart-define=DSH_HOST_URL=http://127.0.0.1:8787 --no-wasm-dry-run` — expected pass (0 errors; requires `dart:io`-free rail)
- `flutter build macos --debug` — expected pass on macOS host (window_manager desktop guard)
- `pnpm run verify-flutter-tracker --check` — OK (168 items) after status→Integrated and parity/platformParity updates

## Tracker update
- `platform.drag-drop`: Audited → Integrated, parity visual/behavior pass, platform web/macos pass, tests 4 entries, integrationPoints 3, e2e 3, evidence testsRun + parityReport path
- `platform.ui-attachment`: parity visual/behavior pass, platform web/macos pass, tests appended (drag_drop, rail), integrationPoints added (rail 64px/paging/wheel, lightbox single-click, removeById+unified model), e2e added

## Remaining gaps
- Native `Image.file` thumbnail for macOS paths not rendering (icon placeholder) — needs `dart:io` conditional import seam.
- `ImageLimits` duplication across `platform/drag_drop.dart` vs `plugins/attachment/attachment_limits.dart` — collapse to single import.
- `DocumentDropScope` enable flag not toggled when a modal overlays (desktop_drop attnates disabled drop while fronting).
- Host admission still local stub in `composer_controller.submit` (no `connectionClient.sendMessage` image payload yet) — draft images not yet serialized via `serializeDraftImages`.
- AttachmentStagingService vs session provider still parallel stores — deprecate staging after consumers migrate.
