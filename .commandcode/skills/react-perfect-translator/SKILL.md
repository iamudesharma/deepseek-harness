---
name: react-perfect-translator
description: Use when perfectly translating a React component/page to Flutter — harvests props, CSS Modules tokens, stores, inject faces, slot graphs, and bottom-sheet/pop-up/select triggers, then emits pixel-perfect Flutter widgets with exact token wiring and backend connections intact.
---

# React Perfect Translator

Harvests a React source file and its CSS Module graph then translates to Flutter without dropping connections.

## When to use

* Any `packages/client/ui-*/*.tsx` → `apps/flutter/lib/src/**` translation where prior stubs missed fields, selects, bottom sheets, pop-ups, or backend wiring.
* Settings, model/provider onboarding, credential flows, and any page that reads/writes via Typert.

## Sources of truth

* React file: `packages/client/<pkg>/src/client/*.tsx` + `*.module.css` + `slots.ts`/`stores.ts`/`locales.ts` + `apply.ts`
* Flutter target: `apps/flutter/lib/src/**` (must already have `DswTokens` / `app_theme`)
* Connection: `apps/flutter/lib/src/core/connection/connection_client.dart:319` + Typert `session.*`, `settings.*`, `credentials.*`, `llm.*`
* Skills delegated: `web-codebase-analysis` (graph), `css-to-flutter` (tokens), `web-component-to-flutter` (widget), `web-state-to-flutter` (store), `api-to-dart` (Typert), `platform-compatibility` (bottom-sheet vs dialog)

## Harvest (write `migration/ui-elements/<pkg>.json`)

For the React file, extract and write JSON:

```json
{
  "reactSource": "packages/client/ui-settings-models/src/client/ModelProviderRow.tsx",
  "props": {"PropsRuntime": ["useSession"], "PropsStore": ["createModelRowStore"], "PropsRenderSlots": [], "inject": ["settingsSchemaService", "credentials"]},
  "cssModules": [{"file":"ModelProviderRow.module.css","vars":["--dsw-alias-bg-layer-2","--dsw-alias-border-l2"]}],
  "store": {"name":"createModelRowStore","state":["provider","baseURL","apiKey","model","testing"],"actions":["setBaseURL","setApiKey","testConnection","save"]},
  "triggers": [{"type":"bottom-sheet","trigger":"Test button"},{"type":"pop-up","trigger":"Select model"},{"type":"select","options":"routable models"}],
  "typert": [{"method":"llm.discoverModels","payload":{"baseURL":"string","apiKey":"string"}},{"method":"credentials.set","payload":{"ref":"DEEPSEEK_API_KEY"}}],
  "slots": []
}
```

Harvest via `ts-morph` or `grep -R "PropsRuntime\|create.*Store\|ctx\.slots\|MenuAnchor\|showModal\|Select\b"` + `grep -R "--dsw-"`.

## Translate

1. **Tokens:** Every `--dsw-*` in the CSS graph must map to `DswTokens`/`DswAliases` via `css-to-flutter` — zero literals. Record the mapping in the JSON.
2. **Props:** `PropsRuntime` → `WidgetRef` `Provider` reads (`useSession` → `sessionProvider`), `PropsStore` → `NotifierProvider` (`createXStore` → `Notifier`), `inject` → constructor services + `hooks` → `StreamProvider`. No ctx in widget.
3. **Triggers:** `showModal` → `showModalBottomSheet` + `DraggableScrollableSheet` with same `radius24`/`shadowLv3`/`bgMask`; `HoverCard`/`MenuAnchor` → `MenuAnchor` with `rAF` flip via `CompositedTransformFollower`; `Select` → `DropdownMenu`/`MenuAnchor` with same `maxHeight` and keyboard nav.
4. **Typert:** Each `typert` entry becomes a `ConnectionClient` method call with `rpcId` initiator-mints. Never mock provider logic — call the real host.
5. **Emit:** `apps/flutter/lib/src/.../*.dart` + barrel export + `test/widgets/*.dart` + `migration/parity-reports/<id>.md` + tracker `Verified` only after `flutter analyze` + `flutter test` + proxy live `session.list` parity.

## Connection invariant

Every harvested `typert` method must be reachable from the emitted widget through its provider/controller — no dropped `settings.update`/`credentials.set`/`llm.models`. Verify via `grep -R "update\|credentials\|discoverModels"` in Flutter vs JSON `typert` list — zero diff.

## Anti-patterns

* Do not translate `className` to `Html` — use `ThemeExtension` + conditional branches.
* Do not replace `TextField` + `Select` with `Text` stubs.
* Do not create a second `ConnectionClient` singleton — use the one `connectionClientProvider`.
