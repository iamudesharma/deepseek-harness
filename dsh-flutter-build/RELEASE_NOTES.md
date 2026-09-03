# Flutter v1.0.2 — settings parity, model sync, RPC error vocabulary

**Version:** 1.0.2+2 (stable, patch over 1.0.1)
**Commit:** 55948a012780b44668f602df0d9f77e267370742
**App revision:** 55948a01... (1.0.2) / Harness revision 55948a01...
**Flutter:** 3.47.0 stable (5f77625673) / Dart 3.13.0 / Node 22.23.2 / pnpm 11.7.0

## Fixes

**Settings → Inventory shows session + global plugins (React parity).**
`InventoryTab` now parses the full `pluginInventory/list` snapshot: the
Session-plugins group is open by default with an agent-preset switcher
(conditional/failed states, cross-preset match hints), and the Global group
is collapsed with failures first plus preset-provided jump links. Search
filters both groups and forces them open.

**Settings gains an Agent presets tab with host-persisted default.**
The roster management section (Built-in/Custom cards, intro, Creator-mode
drafting entry) is embedded as the fifth Settings tab. Picking a card body
writes the deployment default through `settings/update agent-presets
{default}`, so new sessions resolve it app-wide via the roster and hero
seat; per-session switching is unchanged. Shipped preset names resolve
through the locale dictionaries (English stays English; the `ptc` id is
corrected — the Host ships `standard/ptc/minimal/cordis`).

**Model catalog syncs on push events and reconnect (React parity).**
`ModelDirectory` re-reads `session/modelCatalog` on
`llm/adapters-updated`, `settings/document-updated`, and
`credentials/reference-updated`, and resets on reconnect — added models
appear, removed models leave, last-good list kept on failure with a retry
error. The Models settings provider directory reloads on the same pushes
(previously reconnect-only).

**RPC error-code union synced to the slash vocabulary.**
`workspace/not-found` (and the `session/*`, `agent-preset/*`,
`subagent/*`, `settings/*`, `directory-picker/*`, `llm/*`, `gateway/*`
families) now decode instead of throwing
`not part of the closed error-code union`. Workspace `+` session creation
reaches its designed `cwd` fallback again. Hyphen `session-not-found` is
kept for the live message-feedback path.

## Artifacts (Android/macOS/Web only — iOS/Windows/Linux deferred)

- `dsh-flutter-1.0.2+2.apk` (release, `ai.deepseek.dshflutter` 1.0.2+2)
- `dsh-flutter-1.0.2+2.aab`
- `dsh-flutter-macos-1.0.2+2.zip` + `dsh-flutter-macos-1.0.2+2.dmg` (ad-hoc hardened runtime, `ai.deepseek.dshFlutter` 1.0.2 (2))
- `dsh-flutter-web-1.0.2+2.tar.gz`
- `release-manifest.json`, `SHA256SUMS`, `RELEASE_NOTES.md`
