# Agent Note: Flutter inspector ticker and narrow header overflow

Status: implemented

English | [中文](2026-09-05-flutter-inspector-ticker-overflow.zh.md)

## Problem

Opening a trajectory inspector row whose tab count differed from the previous selection crashed: `_DetailsPaneState` mixed `SingleTickerProviderStateMixin` with `didUpdateWidget` dispose-and-recreate of its `TabController`, so the second ticker creation threw and every later frame cascaded (`slot == null`, lifecycle, use-after-dispose). Separately, the session-header preset label overflowed its Row by ~88px in narrow (~24px) header slots at small window widths.

## Decision

- `_DetailsPaneState` uses `TickerProviderStateMixin`, which permits the one live ticker the tab-count switch recreates; locale-free tab ids (prior note) keep controller creation out of `initState` reads.
- `AgentPresetHeaderLabel` measures its slot with `LayoutBuilder`: under 64px it renders a lightly-padded icon (tooltip preserved), otherwise icon plus ellipsized name.

## Alternatives considered

**Reuse one TabController across tab-count changes.** Lost: `TabController.length` is immutable; variable tab sets per row kind require recreation, which only needs the multi-ticker mixin.

**Clip the preset label with ClipRect.** Lost: clipping hides the overflow error but still paints a cut-off name; collapsing to the icon keeps an intentional narrow-width presentation.

## Consequences

Inspector row switching no longer throws; narrow headers show the preset icon with its hint tooltip instead of striped overflow.

## Testing

- `agent_preset_plugin_test.dart`: new 24px-slot widget case asserts zero exceptions, icon present, name absent — 18 pass.
- Trajectory fold suites unchanged: 48 pass.
- `flutter analyze` on both touched files: 0 errors, 0 warnings.
