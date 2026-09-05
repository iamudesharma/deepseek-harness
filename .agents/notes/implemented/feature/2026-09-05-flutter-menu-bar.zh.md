# Agent Note: 原生应用菜单栏（macOS）

Status: implemented

## Problem

Flutter Mac 应用没有原生菜单栏：视图切换、命令面板与控制台终端只能在
会话头与界面控件里找到，Mac 用户在菜单栏里找不到它们。Swift 侧
（`MainFlutterWindow.swift`）是 stock 实现，动原生代码意味着 entitlement
与 Pod 变更；纯 Dart 的 `PlatformMenuBar` 在 macOS 上渲染为真正的应用
菜单，在其它平台上是惰性的，正好满足"只加 Flutter 代码"的约束。

## Decision

`widgets/layout/menu_bar.dart` 的 `DshMenuBar` 包住桌面 `AppFrame`（移动
shell 不受影响）：View 菜单（Toggle Sidebar，⌥⌘S；Command Palette，⌘K）
与 Terminal 菜单（Open Console Terminal、Background Jobs）。菜单只表面化
既有能力——路由跳转与 `layoutProvider.toggleSidebar()`，不发明新行为；
无当前会话时会话级入口禁用而非隐藏。快捷键选择避开 composer 文本键：
⌘K 在纯文本框中无意义（Slack 同款快速切换先例），⌥⌘S 避开 ⌘B 的加粗
冲突；终端入口故意不设快捷键，以免从 xterm 焦点抢走按键。

有意延期：全局热键（需要新依赖与系统权限）、Dock 角标/通知（需要原生
代码或 `flutter_local_notifications` 的 entitlement 与 Pod 变更）、⌘`
终端召唤（会与 xterm 焦点冲突）。

## Verification

- `test/widgets/menu_bar_test.dart`：菜单结构（View/Terminal）、终端
  入口标签、有会话时启用、无会话时禁用、内容透传。
- `flutter analyze` 在变更文件上干净。
