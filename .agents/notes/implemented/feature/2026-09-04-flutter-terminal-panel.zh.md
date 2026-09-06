# Agent Note: Flutter 控制台终端面板（terminal Remote 命名空间之上）

Status: implemented

[English](2026-09-04-flutter-terminal-panel.md) | 中文

## Problem

`ctx.remote.terminal` 命名空间已有经过测试的 Host 归属方与类型化 Flutter 线协议面，但没有界面：Flutter 里唯一的终端 UI 是只读输出卡片。驱动宿主 shell 的面板需要一个保证输出保真度的模拟器、一座通往逐行模式动词的桥，以及在插件/路由组合中的位置——不能重复运行时状态，也不能在生成的描述之外发明契约。

## Decision

`plugins/terminal/` 是既定形状的 `ui-terminal` 插件：`terminal` 本地词典（中文为真源，英文键完全对齐）、会话头动作（`conversation.session.header.actions`，id 为 `terminal`，order 21，紧跟 `job-list` 条目），以及与 jobs 屏并排的 `/sessions/:sid/terminal` 路由。console 会话池是宿主全局的。桌面 shell 上该动作切换会话内停靠面板而不导航（见[停靠面板笔记](2026-09-05-in-session-terminal-dock.zh.md)）；路由仍是移动端与深链入口，其会话 id 同时界定兄弟界面一致性与新会话的 spawn 目录。

- 模拟器选用维护中的 `xterm` pub 包（v4），而非手写 VT 层：每会话一个 `Terminal` 缓冲（2000 行 scrollback）、别名映射的 `TerminalTheme` 的 `TerminalView`，按键只经 `Terminal.onOutput` 到达——视图从不在本地回显，这正是逐行模式桥所需要的。
- 桥对缝隙是显式的：可打印文本追加到待发送行并本地回显，退格删除，回车提交一次 `terminal/send` 并绘制结算 viewport，Ctrl+C 投递 SIGINT 而不提交，转义序列被吞掉（宿主没有光标寻址动词可以承载它们）。模拟器仍以完整保真度渲染每个输出字节（颜色、`\r` 进度帧）。会话退出标记页签为已结束；手动刷新读取 scrollback 尾部（尚无 follow 流，已记录）。
- `TerminalSessionsNotifier` 拥有会话池：`terminal/list` 快照保留存活缓冲，打开绘制 MOTD 并选中，关闭丢弃缓冲。失败在各会话内联展示，外加可关闭的横幅。
- commands 目录增加 `terminal` 条目，供命令面板发现。

有意延期：连续按键流、PTY resize、重连安全的 follow 流（都需要有界逐行模式缝隙尚未暴露的后端能力）；按设备划分会话池（Remote 动词不携带调用方身份）。

## Alternatives considered

- 在别名调色板上手写 VT 渲染器——拒绝：维护中的 `xterm` 包删除自有代码与测试，真正只为逐行模式缝隙定制的只有输入桥。
- 经 WebSocket 的按键/输出流——拒绝：宿主只暴露有界逐行动词；流式需要缝隙尚未暴露的后端能力，因此记录为延期而非半成品。
- 按设备划分 console 会话池——拒绝：Remote 动词不携带调用方身份，不做契约变更就无法按设备限定会话池。

## Consequences

- 输出保真度受限于桥所绘制的内容：颜色与 `\r` 进度帧完整呈现，但光标寻址按键无效，因为没有动词可以承载它们。
- 超出结算 viewport 的 scrollback 需手动读取（刷新读取尾部）；没有 follow 流，实时输出止于最后一次提交。
- 宿主全局会话池在每个设备上展示同一份页签列表；缓冲在客户端存活并跨重建保留，下一次 `terminal/list` 会向宿主不再上报的缓冲写入 `[closed on host]`。

## Verification

- `test/plugins/terminal/terminal_bridge_test.dart`（6）：MOTD 绘制与选中、输入回显加回车提交绘制 viewport、退格与方向键吞掉、Ctrl+C 只发信号不发送、退出标记、关闭/刷新缓冲处理——全部基于 scripted HTTP host。
- `test/api/connection_client_rpc_test.dart`（+6）：每个动词的信封（`args.request`）与结果形状，基于 scripted host。
- `test/plugins/terminal/terminal_plugin_test.dart`（2）：头动作顺序与拆除、词典键对齐。
- `test/plugins/terminal/terminal_screen_test.dart`（2）：空会话池自动打开（无名称、无名称输入框），opener 行再开一个无名称会话。使用应答式 fake 而非 socket：真实 `HttpServer` 往返在 `testWidgets` 的 fake-async zone 下会停滞（plain-`test` 的 scripted host 不受影响），因此 socket 覆盖按设计留在 bridge 与 rpc 测试中。
- `test/plugins/terminal/terminal_dock_test.dart`（3）：停靠面板展开、会话 cwd 自动打开、收起/展开幂等（见[停靠面板笔记](2026-09-05-in-session-terminal-dock.zh.md)）。
- `flutter analyze` 在变更文件上干净；`flutter test` 全量绿色，仅余在干净 `HEAD` 上同样失败的既有失败。
