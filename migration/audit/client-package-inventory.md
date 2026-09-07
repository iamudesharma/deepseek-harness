# Client Package Inventory

Audited 2026-08-21 from `packages/client/README.md`, `packages/client/AGENTS.md`, and `ls packages/client/`.

Every `packages/client/*` package with its npm name, responsibility, and key exports. All browser-half packages participate in at least one slot; no feature package imports another feature implementation — composition goes through slots and services.

| Package | Repo path | One-line responsibility |
|---|---|---|
| `dsh-client-connection` | `packages/client/connection` | HTTP + dual WS downlinks, `ConnectionController` reconnect machine, `hostDescription` generation scope. |
| `dsh-client-runtime` | `packages/client/runtime` | React-free object layer: session/workspace runtimes, conversation assembler, projection store. |
| `dsh-client-web` | `packages/client/web` | Browser shell boot; seeds `PLATFORM_MODULES` / `PRELOADED_CLIENT_EXTERNALS`. |
| `dsh-client-hmr` | `packages/client/hmr` | Dev-only HMR invalidation of dynamic client entries. |
| `dsh-client-locale` | `packages/client/locale` | Host-backed `zh/en` preference via `SettingsScope['locale']`; typed dictionaries. |
| `dsh-client-ui-theme` | `packages/client/ui-theme` | Host-backed `light/dark/system` preference; `--dsw-*` token styles. |
| `dsh-client-ui-primitives` | `packages/client/ui-primitives` | Pure React atoms: controls, markdown, JSON inspectors, icons. |
| `dsh-client-ui-layout` | `packages/client/ui-layout` | Shell `AppFrame` (3-column), `ctx.layout` drag handles. |
| `dsh-client-ui-sidebar` | `packages/client/ui-sidebar` | Sidebar root (brand, workspace browser, settings, footer). |
| `dsh-client-ui-workspace` | `packages/client/ui-workspace` | Workspace picker + directory-flow holes. |
| `dsh-client-ui-conversation` | `packages/client/ui-conversation` | Chat flow, composer, input zones (~20 slots). Highest complexity. |
| `dsh-client-ui-tool` | `packages/client/ui-tool` | Tool call-tree + keyed `tool.call.toolview` per-tool views. |
| `dsh-client-ui-attachment` | `packages/client/ui-attachment` | Fills `conversation.input.attachments` / `message.images`. |
| `dsh-client-ui-commands` | `packages/client/ui-commands` | Global command directory cache; `popupSelect` for `/`. |
| `dsh-client-ui-input-trigger` | `packages/client/ui-input-trigger` | `/` and `@` trigger pipelines → `conversation.input.overlay` menu. |
| `dsh-client-ui-skill` | `packages/client/ui-skill` | Skill reference source + skill tool rows. |
| `dsh-client-ui-reference` | `packages/client/ui-reference` | Unified `@file` / `@session` reference resolvers. |
| `dsh-client-ui-subagent` | `packages/client/ui-subagent` | Child transcript + parent/child navigation. |
| `dsh-client-ui-jobs` | `packages/client/ui-jobs` | Background job indicators. |
| `dsh-client-ui-goal` | `packages/client/ui-goal` | Goal tracker view. |
| `dsh-client-ui-trajectory` | `packages/client/ui-trajectory` | Step/turn trajectory view. |
| `dsh-client-ui-plan` | `packages/client/ui-plan` | Plan-mode state + review surfaces. |
| `dsh-client-ui-deliverables` | `packages/client/ui-deliverables` | Deliverable list + diff presentation. |
| `dsh-client-ui-agent-preset` | `packages/client/ui-agent-preset` | Agent preset picker + selection state. |
| `dsh-client-ui-model-selection` | `packages/client/ui-model-selection` | Model/provider selection + availability indicators. |
| `dsh-client-ui-permission-presets` | `packages/client/ui-permission-presets` | Permission preset picker. |
| `dsh-client-ui-settings` | `packages/client/ui-settings` | Settings shell + section routing. |
| `dsh-client-ui-settings-general` | `packages/client/ui-settings-general` | General settings section. |
| `dsh-client-ui-settings-models` | `packages/client/ui-settings-models` | Model/provider config section. |
| `dsh-client-ui-settings-plugins` | `packages/client/ui-settings-plugins` | Plugin inventory + section hosts. |
| `dsh-client-ui-settings-plugin-inventory` | `packages/client/ui-settings-plugin-inventory` | Per-plugin settings inventory. |
| `dsh-client-ui-message-feedback` | `packages/client/ui-message-feedback` | Message feedback actions. |
| `dsh-client-ui-renderer` | `packages/client/ui-renderer` | React binding of slot data (`createSlotRenderer`, `SessionProvider`). |
| `dsh-client-ui-slots` | `packages/client/ui-slots` | Pure slot core: `SlotMap`, `register()`, renderer host. |
| `dsh-client-modules` | `packages/client/modules` | Client module registry + `__DSH_BOOT__` boot graph. |
| `dsh-client-ui-directory-picker-browse` | `packages/client/ui-directory-picker-browse` | In-app Miller directory browser flow. |
| `dsh-client-ui-directory-picker-native` | `packages/client/ui-directory-picker-native` | Native OS directory picker flow. |
| `dsh-client-ui-brand-official` | `packages/client/ui-brand-official` | Fills generic brand slots with official marks. |

## Flutter disposition

- Every `ui-*` package maps to a Flutter feature widget or screen under `apps/flutter/lib/src/features/`.
- `connection`, `runtime`, `ui-slots`, `modules` are non-widget services mapped to `apps/flutter/lib/src/core/` or capability registries.
- `hmr` is dev-only `not-applicable`.
- `ui-brand-official` fills a generic `BrandSlot` via `DshBrandProvider`.

## Sources

- `packages/client/README.md`
- `packages/client/AGENTS.md`
- `packages/client/runtime/README.md`
- `packages/client/connection/README.md`
- `packages/client/ui-primitives/src/index.ts`
- `packages/client/ui-slots/src/index.ts`
- `packages/client/ui-slots/src/store.ts`
- `packages/client/ui-slots/src/renderer.ts`
- `packages/client/web/src/platform.ts`
- `packages/client/modules/src/index.ts`
- `packages/extensions/cordis-client-runner/README.md`
- `packages/extensions/ui-cordis/README.md`
