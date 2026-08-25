# Migrated → Integrated wave for ui-primitives carriers — 2026-08-26

Scope: the five Migrated rows component.ui-primitives.{JsonTree, Tooltip, Pill, OnboardingSurface, icons}; target is Integrated only where a real composed consumer exists with evidence, under Migration Mode v1.1. English only.

## React contract extraction (consumers traced first)

JsonTree has exactly one consuming package: ui-trajectory's TrajectoryTable.tsx mounts it at :798 (RequestOptions "Request options JSON"), :836 (MessageSource), :1234 (ToolCatalog parameters), :1522/:1563 (RecordPayload "Payload JSON"/"Result JSON" with parseJsonContainer and a bare `<pre>` fallback) and :1603 (RecordSchema); GenericToolCard.tsx does not use it, so the tool-card body was rejected as a mount site.

Tooltip consumers are rail-first: SidebarRoot.tsx:159 wraps the panel-toggle button and :178 wraps New Session in Tooltip delayMs=500 (disabled={wide} when expanded — the rail-tooltip-only rule), with further consumers in MessageIconActions, StatsLine, ContextMeter, QueueDock, GoalBar and WorkspaceBrowser.

Pill has no consumer anywhere: grep over packages/client and apps/web finds `<Pill` only inside ui-primitives' own specs; the sole other match is the coverage-table text string at packages/client/connection/src/client/fixture.ts:130.

OnboardingSurface has no consumer anywhere: its only usages are in packages/client/ui-primitives/tests/onboarding-surface.client.spec.tsx; ui-conversation contains no welcome or blank-state hero and no other package mounts it.

icons/index.tsx ships the ic_ds_* outline SVG set consumed across features (GenericToolCard VARIANT_ICONS, SidebarRoot rail glyphs IconNewChatOutline16/IconPanelLeftOutline16, TrajectoryToolbar, WorkspaceBrowser).

## Changes made by this wave

trajectory_screen.dart gained _ToolCallRecord: inside an expanded turn each tool call is a DisclosureRow record whose args render as "Payload JSON" and whose settled result renders as "Result JSON" through DsJsonTree mounted initiallyExpanded (JsonTree.tsx expandTopLevel=true default), with jsonContainerOf mirroring parseJsonContainer and a mono block standing in for the bare `<pre>` fallback; the flat name+status rows this replaces carried no payload view at all.

sidebar.dart's _CollapsedRail now wraps all four controls (New session, Search sessions, Add workspace, Expand sidebar) in DsTooltip(side right, waitDuration 500ms) replacing bare Material tooltip params, matching SidebarRoot's rail-tooltip-only rule while the expanded sidebar keeps labeled controls.

DsIcons moved from barrel-only to production consumption: trajectory_screen.dart routes completed/failed turn dots through DsIcons.check/close, turn expansion chevrons through chevronUp/chevronDown and search-kind record glyphs through DsIcons.search (pending/running clocks and read/diff/bash/generic glyphs have no vocabulary match and stay Material-inline deliberately); sidebar.dart's rail consumes plus/search/chevronRight.

apps/flutter/test/widgets/migrated_integration_test.dart adds four composed-render tests: trajectory records reveal typed payload/result trees, non-JSON results fall back to the mono block, every rail control owns a DsTooltip with plate decoration equal to aliases.tooltipBg at waitDuration 500ms, and hovering New session shows the plate only after the delay window.

No shared-file surfaces owned by other agents were edited: core/session/*, live_sync, composer/input_trigger internals, brandwordmark/fish_logo/state.runtime/subagent_link are untouched.

## Per-row outcomes

Integrated (3): JsonTree — mount site trajectory_screen.dart _ToolCallRecord against React TrajectoryTable.tsx:1509-1574; visual pass rests on the composed render asserting typed leaves inside the assembled turn card, behavior pass on the same focused suite. Tooltip — mount site sidebar.dart _CollapsedRail against SidebarRoot.tsx:159/:178; visual pass asserts the token plate (tooltipBg, 500ms) on real rail controls with hover show/hide timing. icons — consumption sites in trajectory_screen.dart and sidebar.dart rail; visual honestly stays partial because Material outlines differ from ic_ds_* SVGs by documented design, behavior pass via mapping tests plus the composed render exercising mapped glyphs.

Migrated with citation (2): Pill — integration impossible today because React itself never renders this component outside its own specs (fixture.ts:130 is a coverage-table string); the effort badge and permission selector build badges from ad-hoc spans, so force-fitting would fabricate a consumer. OnboardingSurface — integration impossible today because no React surface mounts it (spec-only usage); there is no welcome hero in ui-conversation to host, and inventing a first-run flow would exceed the React contract.

## Verification

flutter analyze lib reports zero issues in both edited files (remaining errors are tool_stream.dart and composer.dart — concurrent Agent A/B work, untouched here). Focused: flutter test test/widgets/migrated_integration_test.dart test/widgets/primitives_remediation_test.dart test/widgets/primitives_p1_audit_test.dart test/widgets/visual_tool_composer_test.dart → all pass; regression: flutter test test/widgets → 117 pass, flutter test test/goldens → 31 pass. pnpm run verify-flutter-tracker --check → OK (112 items).

platformParity web/macos recorded pass on the widget-level bar: the integrated paths are pure widgets over theme tokens with no platform channels, so both targets compile and render the same tree; tests executed on the macOS host per the existing rows' evidence convention.

Pre-existing failure noted for handoff, not touched: test/plugins/ws_input/input_trigger_shortcuts_test.dart fails 5 cases (ComposerTriggerBinding semantics, foundation debug-var reset) on Agent B's in-flight composer.dart, which currently carries four analyzer errors; its import chain shares nothing with this wave's files.
