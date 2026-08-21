# Platform Inventory

Audited 2026-08-21 from `packages/client/web/`, directory-picker packages, clipboard usage, and composer intake paths.

The React client is web-only (`dsh.client.platform: 'web'`); there is no `kIsWeb`-style branching inside `packages/client` — platform differences are resolved at bundle composition time. Flutter must introduce explicit web/macOS abstraction.

## Surfaces

| Surface | React mechanism | Source | Flutter disposition |
|---|---|---|---|
| Clipboard write | `navigator.clipboard.writeText` with `execCommand('copy')` fallback | `packages/client/ui-primitives/src/clipboard.ts` | `Clipboard.setData`; formats: plain text only today |
| Paste files (images) | `clipboardData.items` partition in composer | `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx:409` | paste intent + `image_picker` |
| Drag-drop images | drop handler in attachments slot | `packages/client/ui-attachment/src/client/index.ts` | `DropTarget` (web) / file drop (macOS) |
| Directory pick (web) | in-app Miller browser flow | `packages/client/ui-directory-picker-browse/src/client/flow.ts` | Flutter web: port Miller browser |
| Directory pick (native) | host `pickDirectory` RPC → OS chooser | `packages/client/ui-directory-picker-native/src/client/flow.ts`, `packages/client/runtime/src/client/contract/workspaces.ts:41` | macOS: `file_selector` |
| Picker selection model | bundle composition chooses browse vs native per deployment | `packages/bundle/web-app/cordis.patch.yml` | Flutter: runtime platform switch or same bundle model |
| Image limits | projection `imageLimits` (mediaTypes, maxImagesPerMessage, maxImageBytes, maxMessageImageBytes) | `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx:440` | shared validation helper |
| Keyboard shortcuts | DOM key handling in InputBar/composer | `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx` | `Shortcuts`/`Actions` + macOS menu accelerators |
| Text selection/copy of references | structured reference expansion before `setData('text/plain')` | `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx:381`, `packages/client/ui-conversation/src/client/input/facade.ts:82` | selectable text + custom copy intent |
| External URLs | browser navigation (implicit) | n/a | `url_launcher` both platforms |
| Window behavior | browser-managed | n/a | macOS: `window_manager` |
| Deep links / history | browser URL bar (shell-level) | `packages/client/web/src/boot.ts` | go_router deep links; macOS: none today |
| Scroll/hover/focus | CSS/DOM defaults | throughout | explicit Focus/Hover regions |

## Gaps to decide during migration

1. Browse-vs-native picker: keep bundle-composition model or collapse into one runtime-switched widget.
2. Clipboard rich formats: React client is plain-text only; keep parity, do not invent rich formats.
3. Browser history/deep links have no macOS equivalent — record as `not-applicable` for macOS rather than fake.

## Sources

- `packages/client/ui-primitives/src/clipboard.ts`
- `packages/client/ui-conversation/src/client/skeleton/InputBar.tsx`
- `packages/client/ui-conversation/src/client/input/facade.ts`
- `packages/client/ui-attachment/src/client/index.ts`
- `packages/client/ui-directory-picker-browse/src/client/flow.ts`
- `packages/client/ui-directory-picker-browse/src/client/DirectoryBrowser.tsx`
- `packages/client/ui-directory-picker-native/src/client/flow.ts`
- `packages/client/runtime/src/client/contract/workspaces.ts`
- `packages/client/web/src/boot.ts`
- `packages/client/web/src/platform.ts`
