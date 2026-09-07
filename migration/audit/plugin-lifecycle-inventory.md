# Plugin Lifecycle Inventory

Audited 2026-08-21 from `packages/client/modules/`, `packages/extensions/`, `packages/client/hmr/`, and the client plugin-loading agent note.

## Boot graph

- Host serves a `__DSH_BOOT__` graph enumerating client plugin bundles; the browser shell consumes it at boot.
- `ClientModuleRegistry` (node half) scans `dsh.client` manifests and serves `/plugins/<id>/client.js`.
- Sources: `packages/client/modules/src/index.ts`, `packages/client/modules/src/client/manifest.ts`

## Plugin loading & lifecycle

- Lazy dynamic imports materialize each plugin module; plugins register contributions through cordis effects (`ctx.effect()` / `ctx.on()`); teardown disposes registrations.
- `cordis-client-runner` executes plugin definitions against a browser cordis runtime; `ui-cordis` provides the UI-facing cordis bindings.
- Sources: `packages/extensions/cordis-client-runner/`, `packages/extensions/ui-cordis/`

## HMR

- Dev-only SSE channel invalidates/prefetches dynamic client entries on rebuild. No production role.
- Disposition for Flutter: `not-applicable` — replaced by Flutter hot reload/restart; recorded via tracker row with reason.
- Source: `packages/client/hmr/`

## Flutter replacement model

```
React:  __DSH_BOOT__ graph → CJS module loader → lazy bundles → plugin lifecycle
Flutter: host capabilities → capability registry → lazy feature initialization → dispose-safe registration
```

Feature registration must remain effect-based (register returns disposer) so the capability registry mirrors cordis teardown semantics.

## Sources

- `packages/client/modules/src/index.ts`
- `packages/client/modules/src/client/manifest.ts`
- `packages/extensions/cordis-client-runner/README.md`
- `packages/extensions/ui-cordis/README.md`
- `packages/client/hmr/README.md`
- `.agents/notes/implemented/architecture/2026-07-23-client-plugin-loading-model.md`
- `packages/client/AGENTS.md`
