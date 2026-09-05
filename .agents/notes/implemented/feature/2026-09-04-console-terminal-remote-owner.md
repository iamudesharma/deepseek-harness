# Agent Note: The console terminal reaches Remote clients through a console principal

Status: implemented

## Problem

The persistent PTY seam (`ctx.terminals`) was exact-Agent scoped end to end: the service keyed sessions by registered Agent, the backend resolved the sandbox policy from the owner's session and fenced sandbox-mode changes against it, and the consumers (`tool-terminal` plus the persistent `bash` and `pwsh` shell tools) forwarded the executing agent. A client terminal panel — the terminal capability the React reference never had — therefore had no legal owner: there was no owner kind for a surface that drives a shell without a model session, and no Remote namespace exposed any terminal verb at all. Forcing the console through a synthetic Agent would have polluted the session-keyed agent registry and leaked console sessions into model surfaces.

## Decision

`TerminalSessionService` accepts a discriminated `TerminalOwner` union instead of a bare `Agent`: `agent` owners wrap the exact live `Agent` (liveness is the registry entry), and `console` owners are client terminal principals with their own effect scope and no model session (liveness is that scope's disposal). Fencing compares the owning authority — the `Agent` for agent owners, the principal object for console owners — never the wrapper, so ownership survives wrapper re-creation and stays exactly as strong as before. `tool-terminal` keeps stable per-agent wrappers (a WeakMap cache) because its fencing is identity-based.

- `terminal-bash` branches per owner kind: an agent owner resolves the sandbox policy from its session and keeps the sandbox-mode fence; a console owner resolves agentlessly to the deployment default mode and the configured workspace root, and installs no fence because no session of its exists whose mode could change.
- `packages/api/terminal-controller` is the new Remote owner: `ctx.remote.terminal` with `list/open/send/read/signal/close`, every verb operating one `console` principal per host. The principal's effect scope is a child plugin of the controller's fiber, so controller disposal tears its sessions down through the PTY service's existing owner-cleanup path. PTY failures map onto stable Remote codes (`terminal/no-session`, `terminal/send-active`, `terminal/unavailable`); unknown-session, active-send, and unavailable-backend paths are pinned by the host spec.
- The controller composes in `bundle/web-app` beside the other controllers. It publishes no TS client face — no browser consumer exists yet — so Flutter consumes the wire contract directly and any future React adoption reads the same `./types` projections.

Consciously deferred and recorded in the controller README: per-device console pools (Remote verbs carry no caller identity today), continuous keystroke streaming and PTY resize (the bounded line-mode backend contract is the current seam), and a reconnect-safe follow stream.

## Verification

- `packages/terminal/terminal/tests/service.spec.ts`: the agent suite passes wrapped owners unchanged, plus a console test covering spawn/send/signal/read fencing, foreign-principal rejection, scope-disposal teardown, and post-disposal `OWNER_NOT_LIVE`.
- `packages/terminal/terminal-bash/tests/index.spec.ts`: a console-owner spawn pins the agentless policy (`deployment default mode`, configured root, no `sessionId`) and the principal's `DSH_SESSION_ID` env; the agent-path tests now wrap owners.
- `packages/api/terminal-controller/tests/terminal-controller.host.spec.ts`: namespace and method surface (`remoteMethods`), the full open/list/read/send/signal/close roundtrip, stable failure codes, duplicate-name rejection, and scope-disposal teardown.
- `pnpm run build` green including the Typert artifacts for the new Remote namespace.
