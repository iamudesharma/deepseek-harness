# Agent Note: Repo file browsing with bounded file preview

Status: implemented

## Problem

Flutter could pick workspace directories (the Miller-column browser over
`directoryPicker/list`) but never look inside a file: the host seam listed
directories only — files were skipped by contract — and no Remote verb read
file content. The plan's Phase 3 asked for repo access with preview, reusing
the filesystem policy instead of inventing a parallel seam.

## Decision

The existing directory-picking seam grows read-only file surface; nothing
new is invented:

- `DirectoryEntry` gains a required `kind: 'directory' | 'file'` stamp.
  `list` takes `options?: { includeFiles?: boolean }`; absent it lists
  directories exactly as before (React, which never sends the flag, sees
  byte-identical rows apart from the inert stamp). File rows cover regular
  files and symlinks-to-files; fifos, sockets, devices, and broken links
  stay unlisted.
- `readFile(path, options?, signal?)` joins the browse capability: one
  bounded text page (`{ path, text, truncated, totalBytes, totalLines? }`)
  with a line window (`offset`/`count`) and a page byte cap (`maxBytes`,
  never above the configured `maxReadBytes`, default 262,144). Whole lines
  only — a budget-cut trailing partial is dropped and re-read whole next
  page. The same fully-qualified fence as `list` applies; directories,
  missing paths, binary content (NUL sniff), and oversized reads answer
  `file-unreadable`. Memory stays O(page) via chunked handle reads with
  the seam's established abort/close discipline.
- `ctx.remote.directoryPicker` gains `readFile` (zod-validated options à
  la `createDirectory`, `gateway/bad-request` on violation) and passes
  `includeFiles` through `list`. Seam `file-unreadable` maps onto the
  existing `directory-picker/unreadable` wire code — no new failure
  vocabulary.
- Flutter: `WorkspacesService.listDirectory(includeFiles:)` and
  `readFile`; a repo file browser screen pushed from each workspace tile
  (directories navigate, files open a preview bottom sheet with pager and
  copy); wire-contract tests for both verbs; widget tests for navigation,
  paging, position copy, and failure retry. The pick-oriented Miller
  browser is untouched.

Consciously deferred: write operations (the seam stays read-mostly by
design — creation remains the only mutation), full-text search (belongs
to a search seam, not the picker), and syntax highlighting in preview
(plain monospace matches every other code surface).

## Verification

- Browse backend: real-tree spec plus a fault spec that mocks only the
  `open` boundary to force a post-stat EACCES (a nondeterministic input
  by policy). Per-file 100% statements/branches/functions/lines,
  including the extracted pure `probedRow` decision (platform-independent
  by construction — the Windows coverage lane cannot build a file
  symlink) and `v8 ignore` arms only for the TOCTOU short-read break and
  the abandoned-close path, each with its reason.
- Controller host spec: verb surface, options passthrough, failure
  mapping, bad-request validation that never dispatches, native-refusal.
  Per-file 100%.
- `pnpm run build:lib:host` green with regenerated Typert descriptors
  (`directoryPicker/readFile`, `includeFiles`); doc-link entries point
  the new wire types at the workspace subsystem page.
- Flutter: api-contract additions plus the file-browser widget suite
  green; analyzer clean on changed files.
