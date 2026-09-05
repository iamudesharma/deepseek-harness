---
description: "Console terminal Remote commands: client terminal panels over the persistent PTY service, fenced to one console principal with bounded line-mode sends."
kind: "package-reference"
---

# @deepseek-ai/dsh-api-terminal-controller

English | [中文](README.zh.md)

## Summary

`dsh-api-terminal-controller` exposes the host's persistent terminal sessions to Remote clients as the generated `ctx.remote.terminal` namespace, so a client terminal panel can open, drive, and close console sessions over the same transport every other Remote namespace rides. Every verb operates one console principal — a `TerminalOwner` that owns no model session and is invisible to agent tools — so the console pool inherits `ctx.terminals`' exact-owner fencing, bounded sends, and awaited cleanup unchanged. The controller adds no terminal mechanics: the mounted backend owns spawning, readiness, and output bounds, exactly as it does for the model-facing tools.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Further Exploration](#further-exploration)
- [Model Experience](#model-experience)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

-----

<a id="use-this-package"></a>
## Use this package

Mount this controller when a Remote client should reach a console terminal on the host. It requires `ctx.terminals` with a mounted backend (compose `@deepseek-ai/dsh-terminal-bash`); without a backend, `terminal/open` rejects with `terminal/unavailable` and every other verb still answers its closed-session codes. Authorization rides the Remote transport: a caller that may reach `ctx.remote.workspace` may reach `ctx.remote.terminal`.

### The six verbs

| Verb | What it does | Result |
|---|---|---|
| `terminal/list` | Lists the console principal's live sessions | Snapshots in publication order |
| `terminal/open` | Opens one console session through a registered backend | Snapshot plus bounded MOTD |
| `terminal/send` | Writes one line and waits for readiness | Bounded viewport, wait reason, session status |
| `terminal/read` | Reads one bounded scrollback page | Retained text with pagination metadata |
| `terminal/signal` | Delivers one allowed signal to the foreground process group | Delivered process-group id |
| `terminal/close` | Closes the session and waits for quiescence | Whether this call closed it |

`terminal/open` takes an optional `type`; when absent it resolves explicitly to the first registered backend type and rejects with `terminal/unavailable` when none is mounted. Send results carry the same wait reasons the model-facing tools report (`stdin_read`, `inferred_idle`, `timeout`, `session_exit`).

### Failures

Stable Remote codes: `terminal/no-session` (unknown or already-closed id), `terminal/send-active` (another send owns the session), and `terminal/unavailable` (no backend for the type, a taken session name, a disposed principal, or the service is disposing). Every other failure passes through the Gateway's fault mapping unchanged.

## Further Exploration

- [terminal service](../../terminal/terminal/README.md) — backend registration, owner fencing, and cleanup semantics the console verbs inherit.
- [terminal-bash backend](../../terminal/terminal-bash/README.md) — the shipped shell backend, its sandbox resolution, and console-owner policy behavior.
- [Terminal subsystem reference](../../../docs/subsystems/terminal.md) — the owner union and the generated `ctx.terminals` surface.

<a id="understand-the-implementation"></a>
## Understand the implementation

<details>
<summary>Implementation details — click to expand</summary>

The controller is a thin adapter over `ctx.terminals` behind one `console` principal. The principal's effect scope is a child plugin of the controller's fiber: its disposal ends the principal, and the PTY service tears the console sessions down during that scope's unwind. The verbs add only the stable Remote failure mapping and the explicit default-backend resolution; spawning, send exclusivity, bounded reads, signals, and cleanup are the PTY service's existing behavior.

| File | Responsibility |
|---|---|
| [`src/index.ts`](src/index.ts) | `TerminalController`: the six Remote verbs, console principal scope, failure mapping |
| [`src/types.ts`](src/types.ts) | Wire requests, results, failure codes, and the session-view re-exports |

</details>

-----

<a id="model-experience"></a>
## Model Experience

None, as the console surface is browser-and-client control state and registers no prompt, tool, or session event. Console sessions are invisible to model tools: `terminal_list` lists only the calling agent's sessions, and the console principal is not an agent.

#### KV Cache effect

None; console traffic never reaches a model request.

<a id="known-limitations-and-deferred-work"></a>
## Known Limitations and Deferred Work

These limitations describe when the console surface is not the right fit or needs operator awareness. They are current package constraints, not a backlog.

- **One console principal per host** — all paired devices share one console session pool. Per-device pools need a caller-identity fact on Remote dispatch, which no Remote verb carries today.
- **Line mode only** — the panel drives sends and scrollback pages through the backend's bounded contract; continuous keystroke streaming, PTY resize, and full-screen TUI interaction need backend capabilities the persistent PTY seam does not expose.
- **No follow stream** — output arrives as send viewports and explicit reads; a reconnect-safe output stream (the `workspace/follow` pattern) is deferred until a consumer needs it.
- **cwd is backend-interpreted** — `terminal/open` passes the requested directory to the backend; the sandbox mode in force is the deployment default, so operators should set it with a console panel in mind.

<a id="dev-note"></a>
## Dev Note

<details>
<summary>Working context for maintainers — click to expand</summary>

None.

</details>

**Runtime invariant:** no invariant companion is published. The console pool is `ctx.terminals` state behind one principal; the controller publishes no independent lifecycle stream or snapshot, so there is no diverging observation for a companion to check.
