# Agent Note: Flutter syncs its RPC faces to the React wire contract

Status: implemented

## Problem

A React↔Flutter parity audit (2026-09-04) found the Flutter client calling wire
faces that do not exist, skipping faces React depends on, and diverging from
React inside live streaming:

- `ConnectionClient.workspaceList()` posted `workspace/list`, but
  `WorkspaceController` serves only the `workspace/follow` baseline plus
  increments — every call 404'd, and `selection_restore.dart` swallowed the
  failure, so persisted workspace selections were never validated.
- The two `session/fork` call sites sent different argument shapes
  (`{sessionId, atSeq}` in chat, a bare `agentId` in the sidebar), and
  `session/rename` sent `agentId` where the host request field is `sessionId`.
- Faces React uses had no Flutter caller at all:
  `session/canOpenWorkspacePath`, `session/openWorkspacePath`,
  `settings/replace`, `settings/openSettingsDocument`, and
  `subagents/list|prompt|interruptByParent`. The deliverables row therefore
  had no host opener gate, the settings screen no document action, and
  subagent child traffic had no route to its parent-authority faces.
- Live assistant streaming fused reasoning and text deltas into one buffer,
  so the streaming view collapsed the distinction React's `PartialAssistant`
  keeps.
- `RemoteMuxClient.close()` iterated `_streams.values` while awaiting inside
  the loop; a concurrent generation could mutate the map during that await
  and crash the suspend path with concurrent modification (observed as 13
  failures in `app_lifecycle_matrix_test.dart`).

## Decision

`ConnectionClient` carries typed faces for every listed endpoint, each
matching the host request schema and pinned by scripted-host wire tests in
`test/api/connection_client_rpc_test.dart`: `forkSession`, `renameSession`,
`workspaceArchiveSession`, `settingsReplace`, `settingsOpenDocument`,
`canOpenWorkspacePath`, `openWorkspacePath`, `subagentList`, `subagentPrompt`,
`subagentInterrupt`.

- `workspaceList()` is retired: it throws `UnsupportedError` naming the
  `workspaceListProvider` follow baseline instead of posting a 404.
  `selection_restore.dart` validates persisted workspace ids against that
  baseline and treats a persisted id that matches only the synthetic
  `kWorkspaceOptions` fallback as missing, so stale ids can never resurrect.
- The sidebar and chat fork sites both call `forkSession`; the sidebar rename
  calls `renameSession`; the sidebar archive calls
  `workspaceArchiveSession`. Argument shapes are single-sourced.
- `settingsReplace` unwraps through `_unwrapNamespaceView`, which returns the
  complete `SettingsNamespaceView` (`ns`, `value`, `revision`) without the
  legacy `value`-layer collapse, because the returned revision is what the
  next write's `expectedRevision` fence reads.
- `DeliverablesScreen` polls `canOpenWorkspacePath` through
  `canOpenHostPathProvider` and routes the open handoff through
  `openWorkspacePath`; the mount-site `canOpenPath` prop ORs with the poll.
  React's `isLoopback` half of the gate has no Flutter analog: the opener
  capability is a host-desktop fact and the open runs host-side either way.
- The settings General tab renders the `openDocument` action only after
  `settings/describe` answers `hasDocument`, collapses concurrent gestures
  behind one in-flight open, and reports failure with the localized
  `openDocument.error` line; the `openDocument`/`openDocument.error` keys
  that were documented as ported but missing are now in both dictionaries.
- `ConversationController.sendToSubagent` and `interruptSubagent` are the
  parent-authority faces for addressed children. `subagent_link.dart`
  records the address-derivation policy: child `mode` and parent
  availability come from `subagents/list`, never from session summaries, so
  child prompts and stops route through these faces only at call sites that
  hold the address; the child surface stays read-only until the
  descriptor-backed selection workstream carries the address through
  navigation.
- `messagesFromHistory` buffers reasoning and text deltas separately and
  flushes them as distinct `AssistantBlock`s (`reasoning` before `text`);
  the plain-text face stays the prose only. The final `assistant/message`
  path is unchanged.
- `RemoteMuxClient.close()` iterates copies of `_waiters` and `_streams`
  before its awaits.

## Alternatives considered

**Keep the raw `callMethod` shapes at each call site.** Lost: the audit's
fork-site divergence came from exactly that — two call sites inventing
envelopes independently. One typed face per endpoint gives the scripted wire
tests a single authority.

**Auto-route child sends inside `ConversationController.send` by looking up
the parent from session summaries.** Lost: a summary carries parentage but
not `mode`, and routing a one-shot child through `subagents/prompt` would
produce `subagent/not-resumable` failures the addressed-client design
prevents by construction. The explicit address-holding call sites keep the
descriptor gate honest.

**Unwrap `settings/replace` through `_unwrapValue` like its sibling write
faces.** Lost: `_unwrapValue` strips one `value` layer for the historical
wrapper shape, which would also strip the namespace view's own `value` and
drop `ns`/`revision` with it. The siblings tolerate the collapse because
their callers re-`describe` after every write; the replace face exists for
its revision.

**Fix the lifecycle-matrix failures beyond the close-copy.** Deferred: the
remaining handshake failures reproduce at HEAD (verified in a clean worktree
at `daa8c5aeae`) and live in surfaces with in-flight edits; the close-copy
fix alone moved that file from 13 failures to 9.

## Consequences

The Flutter client now speaks every wire face React speaks, the dead 404
path and its swallowed failure are gone, and stale persisted selections
clear instead of validating against synthetic data. Three product defects
shipped in committed code are fixed alongside: `session/page` `records`
entries were unwrapped one level past the `HistoryEntry` shape (so
`loadOlder` silently no-opped against real hosts), the legacy dot-path
`hostDescribe` fallback dissolved 401/403 into the empty compat stub (so a
rejected bearer could never reach `needsReauth`), and the directory-picker
probe popped the host's native OS dialog from a remote device (remote
callers now resolve `browse` without a probe). Fourteen previously failing
tests across the audited suites now pass: the `session/list` envelope
expectation, six devices-navigation cases, the three `sendMessage` image
payload fixtures, the three `updateQueue` payload fixtures, the 401
propagation case, the remote-picker case, and the cursor tests
(`session_page_fix`) once the records rewrap landed. The reasoning split has
its own unit test; the restore fallback rule has its own test.

The remaining failures are all one class: the connection-handshake tests
(`connection_generation_test` ×2, `app_lifecycle_matrix_test` ×8) wait for a
`$events`/`remote.mux` `ready` frame the current scripted fixtures never
send, so generations never reach `connected`. They reproduce identically at
HEAD (verified in a clean worktree at `daa8c5aeae`) and sit in
`connection_controller.dart` / `live_sync.dart` / `_LifecycleHost`, all
carrying in-flight edits — their controller-vs-fixture contract is the
owning workstream's call, not this sync's. The generated parity inputs
(`migration/upstream-sync/parity.json`, `flutter-impact.json`) still report
the pre-fix verdicts and need their next regeneration run to reflect this
change.
