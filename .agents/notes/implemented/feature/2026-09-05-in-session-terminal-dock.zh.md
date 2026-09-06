# Agent Note: 会话内终端停靠面板与会话目录自动挂载

Status: implemented

[English](2026-09-05-in-session-terminal-dock.md) | 中文

## Problem

控制台终端面板此前以整页路由呈现：会话头动作总是离开当前对话跳转，打开会话时还要提示输入可选名称，并在部署工作区根目录新建宿主会话——从来不在聊天会话所在的目录。会话内的用户必须离开对话、想一个名字，最后仍然落到错误的目录。

## Decision

会话头的终端动作改为切换停靠在对话栏底部、composer 之上的终端面板（`TerminalDock`），不再导航。移动 shell（宽度 <768）保留整页路由——固定高度的停靠面板在手机上放不下。

- 展开停靠面板时自动在拥有该面板的聊天会话工作目录（`SessionSummary.cwd`，经由既有 `terminal/open` 的 `cwd` 参数传入，宿主无需改动）打开一个无名称控制台会话。会话池已有时原样展示；再次展开不会成倍新增会话（`TerminalSessionsNotifier.ensureOpen`）。面板隐藏时不产生任何 spawn。
- 客户端打开一律不带名称：宿主注册表铸造身份，页签标签回退到未命名字符串。路由的 opener 行同样移除了名称输入框。
- 整页路由、页签条、工具栏与模拟器视图经 `ui/terminal_views.dart` 与停靠面板共享。路由仍是移动端与深链入口，同样会对空会话池自动打开。

有意延期：把用户在控制台运行的命令写进会话日志，让模型能看见并执行。模型可见输入需要会话事件（模型可见 ⟺ 已记录），因此这需要专门的事件契约——是后续工作，而非静默缺失。

## Alternatives considered

- 保留路由为唯一入口并预选默认名称——拒绝：仍然离开对话，且仍然在工作区根目录而非会话目录打开。
- 按聊天会话 id 划分终端会话池——拒绝：console 会话池按契约是宿主全局的（`console` owner），按设备的调用方身份已是终端面板笔记中记录过的延期项（[终端面板笔记](2026-09-04-flutter-terminal-panel.zh.md)）。

## Consequences

- 会话池保持宿主全局：同一宿主上的两个聊天会话共享页签列表，停靠面板原样展示。自动打开以第一次展开面板的会话 cwd 为目标，因此 cwd 匹配按展开计，而非按页签计。在另一文件夹重新打开面板会复用同一会话池并显示之前会话的输出——点 × 关闭页签即可丢弃。
- 若会话 cwd 在 console 沙箱根之外，宿主 spawn 失败并落入停靠面板的内联错误横幅；没有向工作区根的静默回退。
- Ctrl+C 即使在前台发送尚未返回时也会发信号（此前 busy 守卫吞掉它且工具栏按钮被禁用，长命令无从停止）。Ctrl+L 清空可见显示并保留未提交的输入行；其余控制键仍由行模式桥接吞掉。
- 工具栏状态按忙闲区分：仅在前台发送进行中才显示动画圆点加“运行中”；空闲 shell 显示静态圆点加“就绪”，页签圆点一致。此前所有存活会话永远追逐“运行中”，看起来像命令卡死。
- `ls` 分栏按宿主 pty 宽度（160 列）排布，较窄的模拟器视图会换行；用 `ls -1` 每行一项。常驻前台命令（`npm run dev`）会占据行模式发送直到退出——Ctrl+C 可停；常驻服务应放后台。

## Verification

- `test/plugins/terminal/terminal_dock_test.dart`（3）：隐藏时什么也不渲染、什么也不 spawn；展开时以会话 cwd 自动打开无名称会话并显示在头部；收起控件折叠面板，再次展开不会重新打开。
- `test/plugins/terminal/terminal_screen_test.dart`（2）：空会话池自动打开（无名称、无名称输入框），opener 行再开一个无名称会话。
- `test/plugins/terminal/terminal_bridge_test.dart`（+2）：前台发送尚未返回时 Ctrl+C 仍投递 SIGINT；Ctrl+L 本地清屏、保留未提交行、不产生宿主调用。
- `test/plugins/terminal/terminal_dock_test.dart`（+1）：工具栏空闲读“就绪”、忙时读“运行中”、关闭读“已退出 (0)”。
- `flutter analyze` 在变更文件上干净；终端相关套件绿色；`test/widgets/conversation_test.dart test/plugins` 与干净树一致（既有失败相同，净新增四个通过测试）。
