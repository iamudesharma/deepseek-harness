---
name: web-codebase-analysis
description: Use when analyzing the existing DeepSeek Harness web frontend before migration — discovers every screen, component, route, state store, API integration, theme token, animation, dialog, form, and platform-specific UI behavior to seed the Migration Tracker.
---

# Web Codebase Analysis — Frontend Analysis Skill

Deeply analyze the existing web frontend and produce the migration inventory. This is the entry skill for Migration Mode; every migration starts here.

## When to use

* Migration Mode entry (`dsh --mode migration` or `migration:analyze`)
* Before any Flutter implementation — tracker is empty or stale
* After a web feature merges — re-seed delta

## Sources of truth

* `packages/client/*` — browser half, Cordis slot system (`packages/client/AGENTS.md`, `packages/client/README.md`)
* `apps/web/src/main.ts` — thin Vite entry over `@deepseek-ai/dsh-client-web`
* `packages/client/web/src/platform.ts` — `PLATFORM_MODULES`, `PRELOADED_CLIENT_EXTERNALS`
* `packages/client/ui-layout/src/client/AppFrame.tsx` — 3-column shell contract
* `packages/client/runtime` — object layer (SessionManager, ConnectionController, `defineStore`)
* `packages/host/webserver`, `packages/host/frontend-static` — serving contract
* `docs/web-styling.md` — token system `--dsw-*`
* `migration/migration-tracker.json` — output target

## Inventory taxonomy

Every file under `packages/client/**/*.{tsx,ts,css}` and `apps/web/**/*` maps to one `category`:

| Category | Example source | Tracker id pattern |
|----------|---------------|-------------------|
| `screen` | `ui-conversation`, `ui-trajectory`, `ui-settings*` | `screen.<slot>.<entry>` |
| `component` | `ui-primitives/*`, `ui-tool/toolviews/*` | `component.<package>.<export>` |
| `route` | slot names `root`, `sidebar`, `conversation`, `details`, `shell.overlay`, `tool.call.toolview`, `conversation.chat.node` | `route.<slotName>` |
| `state` | `create*Store()` factories, `runtime` sessions, inject `hooks` | `state.<storeName>` |
| `api` | `connection/*`, `api/*` Typert RPC, `web/*` search/fetch | `api.<service>.<method>` |
| `theme` | `ui-theme/src/styles/*`, `--dsw-*` tokens, `ui-primitives` CSS Modules | `theme.<tokenGroup>` |
| `animation` | `DragHandle` rAF throttle, `ResizeObserver`, transitions | `animation.<component>` |
| `dialog` | `Modal`, `HoverCard`, `Menu` | `dialog.<component>` |
| `form` | `ModelSelect`, `Input`, `LanguageRow`, onboarding | `form.<feature>` |
| `platform` | `ui-directory-picker-native` vs `browse`, `fs` policy, clipboard | `platform.<capability>` |

## Workflow

### 1. Scan structure

```sh
find packages/client -type f -name "*.tsx" -o -name "*.ts" -o -name "*.css" | sort
ls -1 packages/client/*/src/client/*.{ts,tsx} 2>/dev/null
grep -R "ctx.slots.register" packages/client --include="*.ts" -n
grep -R "create.*Store" packages/client --include="*.ts" -n
grep -R "SlotMap\|PropsRuntime\|PropsRenderSlots" packages/client --include="*.ts" -n
```

### 2. Parse slot graph

* Read each `apply.ts` / `slots.ts` for `SlotMap` entries and `children` declarations (`packages/client/AGENTS.md:Slot and props discipline`)
* Build graph: `root → {sidebar, conversation, details, shell.overlay}` etc.
* Record `kind/scope` and `session` vs `global` scope

### 3. Parse state

* Collect every `createXXXStore()` factory (module-level forbidden; factory exported for tests)
* Record store state shape, actions, scope (shared vs entry-private)
* Record object-layer sessions: `ConnectionController`, `SessionManager`, `Session` event window

### 4. Parse APIs, theme, platform

* Typert services consumed by each plugin (`inject` face)
* CSS token inventory (`ui-theme/src/styles/*.css`, `*.module.css`)
* Platform branches (`window.innerWidth`, `ResizeObserver`, native pickers)

### 5. Emit tracker

Write `migration/migration-tracker.json` — one entry per item:

```json
{
  "id": "component.ui-primitives.Button",
  "category": "component",
  "source": "packages/client/ui-primitives/src/Button.tsx",
  "flutterTarget": "apps/flutter/lib/src/widgets/primitives/ds_button.dart",
  "status": "Analyzed",
  "dependsOn": ["theme.tokens"],
  "tests": ["packages/client/ui-primitives/tests/button.client.spec.tsx"],
  "notes": "Props: variant/size, tokens --dsw-*"
}
```

Status lifecycle: `Not Started → Analyzed → In Progress → Migrated → Tested → Verified`. Analyzer sets `Analyzed`; never advances beyond without Migration Agent.

### 6. Generate report

* `migration/analysis.md` — counts per category, dependency graph, blockers
* Console summary: total items, unmapped files, slot graph

## Output invariants

* Every `packages/client/**/*.{tsx,ts,css}` appears in tracker (zero orphan)
* Every slot name has one declaring parent and ≤N authorized children
* Every store factory is referenced by its owning `register` call
* Tracker `Analyzed` items all have `source` + `flutterTarget` + `category`

## Verification

* `migration/migration-tracker.json` validates against schema (`scripts/verify-flutter-tracker.ts` if present)
* `pnpm run test:gui` still green — analysis is read-only
