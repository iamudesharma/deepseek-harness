# Agent Note: Flutter trajectory requests, subtools, timeline detail

Status: implemented

English | [中文](2026-09-05-flutter-trajectory-requests-subtools.zh.md)

## Problem

The trajectory follow-up to the ledger/inspector note left four React behaviors undeferred-no-longer: request inspection (Options/Usage/Timing per request), nested `code-dispatch` subtool rows, timeline TTFT-split rendering with rich tooltips, and collapsed-turn histogram summaries. The ledger still hardcoded `1 step · N tool calls` for every collapsed turn, timeline tooltips read `kind · ok|error`, and header rows carried no request accumulation.

## Decision

All four derive from the same history fold, matching the React sources named per item.

- Subtools (`trajectory-tool-definition.ts` edge rules): `tool/code-dispatch-start` and `tool/code-dispatch` (`{parentCallId, subCallId, name, arguments, content?, isError?}`) fold into `subtool` rows after their parent with args, joined result preview, error flags, and call→result durations. Edge guards mirror `acceptsEdge` (no self-parenting, first parent wins, ancestor-cycle rejection, 256 depth ceiling); orphans without a parent row drop as unreachable-from-root, as in React.
- Requests (`TrajectoryView.tsx` numbering, `REQUEST_TABS`): `request/header` order numbers requests session-globally; each header row accumulates tool/subtool counts, input/output/cache usage sums, error/running state, and wall span over its range, and inspects via Summary (Status, Request #, Provider, Model, counts, prompt preview link), Options (config JSON), Usage (Input/Cached/Output), and Timing (request wall span) tabs.
- Timeline (`timeline.ts`, `TrajectoryTimeline.tsx` tooltips): spans carry recorded start, duration, and validated TTFT/decoding detail; assistant spans render the TTFT fraction solid over a translucent decoding remainder, and tooltips read `KIND / start → end / Total ms · TTFT ms · Decoding ms` from locale templates.
- Collapsed turns (`layout.ts groupDescription`): wall span from row starts (tools contribute start plus own duration) plus first-seen tool histogram (`bash×6`), falling back to the tool count only when no times exist.
- Assistant rows now stamp step-start→message wall time (React `durationSeconds`), so Timing Total and timeline spans cover the step; user/context rows stamp zero duration per `inputCellDetail`.

## Alternatives considered

**Render orphan subtools as top-level tools.** Lost: React never renders children unreachable from a root; inventing a parent would fabricate hierarchy the log does not contain.

**Number requests by turn instead of header order.** Lost: React numbers session-globally by request start; turns and requests are independent buckets (one turn can span requests after compaction).

**Show TTFT splits in sequence mode.** Lost: equal-width mode carries no wall times by design; the split needs recorded spans, so it renders in timed modes only.

## Consequences

The reporting session folds one request (`#1`, opencode provider, 40 tools, 62K/25K tokens, wall span) with zero subtools (no dispatch events logged locally; synthetic tests cover the shape). No local session carries `code-dispatch` traffic yet, so subtool rendering is contract-covered but live-unverified.

## Testing

- `trajectory_ledger_parity_test.dart`: 5 new cases (dispatch fold, orphan drop, cycle drop, request numbering plus cumulative usage, TTFT span detail) — 17 pass.
- Full trajectory set (`trajectory_ledger_test`, `trajectory_plugin_test`, `trajectory_fold_test`): 48 pass.
- Real-log probe (session `00b22885`, removed): request stats and zero-TTFT absence confirmed.
- `flutter analyze` on both trajectory library files: 0 errors, 0 warnings.
