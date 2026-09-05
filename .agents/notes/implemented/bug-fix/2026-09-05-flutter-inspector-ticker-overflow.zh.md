# Agent Note: Flutter 检查器 ticker 与窄头部溢出

Status: implemented

[English](2026-09-05-flutter-inspector-ticker-overflow.md) | 中文

## Problem

打开标签数与上次不同的轨迹检查器行时崩溃：`_DetailsPaneState` 把 `SingleTickerProviderStateMixin` 与 `didUpdateWidget` 中销毁重建 `TabController` 混用，第二个 ticker 创建即抛错，后续每帧连锁（`slot == null`、生命周期、释放后使用）。另，会话头部预设标签在小窗口约 24px 槽位向右溢出约 88px。

## Decision

- `_DetailsPaneState` 改用 `TickerProviderStateMixin`，允许标签数切换时重建唯一的活跃 ticker；无区域设置的标签 id（前一笔记）使控制器创建不读 `initState`。
- `AgentPresetHeaderLabel` 以 `LayoutBuilder` 量槽位：64px 以下渲染轻内边距图标（保留提示），否则图标加省略名称。

## Alternatives considered

**跨标签数复用同一个 TabController。** 不可行：`TabController.length` 不可变；按行类型变化的标签集必须重建，只需多 ticker mixin。

**以 ClipRect 裁剪预设标签。** 不可行：裁剪止住报错但仍绘制截断名称；窄宽收为图标是有意的展示。

## Consequences

检查器切换行不再抛错；窄头部显示预设图标加提示，不再出现条纹溢出。

## Testing

- `agent_preset_plugin_test.dart`：新增 24px 槽位组件用例，断言零异常、图标在、无名称——18 项通过。
- 轨迹折叠套件不变：48 项通过。
- 两个触及文件 `flutter analyze`：0 错误 0 警告。
