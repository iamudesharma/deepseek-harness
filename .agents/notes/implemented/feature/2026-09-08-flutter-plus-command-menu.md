# Agent Note: Flutter session command (`+`) menu parity

Status: implemented

English | [中文](2026-09-08-flutter-plus-command-menu.zh.md)

## Problem

React's conversation composer has a `+` button (`InputBar.tsx:465-478`)
that opens the session command menu — the Host catalog (`compact`,
`export`, `feedback`, `goal`, `permission`, `plan`) plus the client-owned
`/model` row — with name + description rows. Flutter's composer had no `+`
trigger: commands were reachable only by typing `/`. The Host catalog rows
therefore had no visible entry point, `/model` had no menu row at all (zero
client contributions registered), and `/export` executed without ever
downloading the ZIP the Host prepared.

## Decision

- `InputTriggerController.toggleLauncherSource()` ports React
  `toggleSource`: a synthetic leading hit (empty query, collapsed caret
  span with live `draftRev`) seeds exactly one source's groups and fetches
  its candidates. Picks reuse the ordinary source callback and sink
  pipeline; the next `track()` clears the launcher and re-detects, exactly
  like React, so typing after a launch falls back to detection. Unknown
  sources and a second toggle dismiss.
- The composer gains a `+` button as the first tool-row child (React's
  position), tooltip `input.commands` (`Commands`/`指令`), disabled while
  the composer is disabled/sending or before trigger activation. It focuses
  the field, then toggles post-frame so a focus-driven selection change
  cannot clear the launcher the same frame it opens. The draft is never
  mutated by opening.
- `/model` registers as a client contribution over the session's shared
  `ModelDirectory` (the composer seat's store), with options flattened from
  groups, failure rows that reject on pick, and `onSelect` settling through
  `directory.select`. The description snapshots the `model` locale at
  registration, like React. A same-named Host row would collide and fail
  loud at candidate synthesis, never shadow.
- `/export` downloads through an export-aware executor wrapper: an admitted
  bare `/export` also GETs `/api/session.export` (same cookie/bearer fence
  as every `/api/*` caller, `?token=` stripped) and saves the ZIP through
  the platform save sheet (`FilePicker.saveFile` — native dialog on
  desktop, save/share sheet on mobile, download on web). Argued lines stay
  on the Host usage-error path; download failures report through
  `onExportError` (wired to toasts in the app composition) without failing
  the admitted command outcome; a cancelled sheet is benign.
- `/compact`, `/feedback`, `/goal`, `/plan`, and argued `/permission`
  needed no new code: the `+` menu lists the live Host catalog rows and
  picks flow through the existing claim/detached decision tables with the
  existing canonical RPC (`commands/execute`).
- Bare `/permission` opens the picker shell through a `command.decorate`
  port: `CommandUiService` gained a decorations registry consulted only for
  bare menu-picks/enters over resolvable Host rows (argued lines keep the
  claim path). Options come from a `PermissionSnapshotCache` mirror that
  `live_sync` feeds beside every `permissionSelectProvider` write (the
  projection is Riverpod state, unreachable service-side); the
  `danger-full-access` row carries the seat's `confirm.*` risk gate, and
  settling posts the same `/permission <preset>` line with Host refusals
  thrown into the shell error strip.

## Alternatives considered

**Insert `/` into the draft on `+` tap.** Reuses detection with zero
controller changes, but leaves a stray `/` when the menu is dismissed
without picking — React's launcher never mutates the draft.

**Duplicate the menu model for the launcher.** Rejected: two models would
need joint invalidation for catalog refreshes, highlight sync, and
dismissal. The synthetic-hit toggle reuses one model.

**Gate `/model` availability on subagent sessions.** React hides the row
for continuable children via `subagentAddress`. The Flutter composer seat
has no such gate and summaries are Riverpod state unreachable from the
service-layer contribution; gating only the menu row would make the two
surfaces disagree. Both surfaces share the directory and its errors, so a
subagent pick fails loudly through the same RPC path instead.

**Read the picker options from the settings scope.** The scope describes
the global new-session default, not the session — the wrong source. The
live projection mirror carries the per-session truth.

## Consequences

- The `+` menu lists exactly what typing `/` lists (Host catalog plus
  contributions), with Host-owned descriptions verbatim and no hardcoded
  command names.
- `ModelSelectionPlugin` now injects `commandUi`, so plugin activation
  orders it after `ui-commands` (service-dependency order, like cordis
  fibers). `PermissionPresetsPlugin` declares the same edge for its
  decoration.
- `CommandsPlugin` accepts an optional `onExportError`; existing
  constructions are unaffected.
- New tests: launcher toggle unit tests, `/model` contribution tests,
  permission decoration tests, export service/wrapper tests, `+` button
  widget tests, plus the pre-existing slash/contract suites which pass
  unchanged.
