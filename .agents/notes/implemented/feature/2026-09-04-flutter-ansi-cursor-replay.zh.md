# Agent Note: Flutter 以完整光标重放渲染 ANSI 工具输出

Status: implemented

## Problem

Flutter 的 ANSI 渲染器（`plugins/conversation/ui/ansi_span.dart`）是 React
解析器（`packages/client/ui-primitives/src/ansi.ts`）的一个诚实子集：SGR 颜色
可用，但光标移动 —— 回车、退格、行内擦除 —— 被清洗掉了，tab 与宽字符不推进
列，调色板是一张私有的 Tailwind 风格色表而非 React 映射的设计系统 token。
另有两个面更落后：`DsTerminalBlock` 剥掉全部 ANSI 序列只渲染纯文本
（"color rendering is a recorded gap"），而工具插件的 `BashToolCard` 对原始
输出文本完全不做 ANSI 处理 —— React 的 bash toolview 却是通过 `TerminalBlock`
渲染已解析 span 的。于是 `1%\r2%\r…100%` 这样的进度行在会话卡片里渲染成串联
的帧，在 terminal block 里是被剥掉后的文本，在 bash 卡片里是原始转义序列。

## Decision

`widgets/primitives/ansi.dart` 现在是唯一的 ANSI 归属，忠实移植 `ansi.ts`：
剥离 OSC 与非 CSI 转义、逐行光标重放到列缓冲（回车、退格、erase-in-line
`K` 的 0/1/2 模式、tab 停位填充空白、宽字符 spacer 列、零宽字符附着、结尾
CRLF 丢弃）、按参照实现的属性关闭符语义折叠 SGR 状态，并把 run 解析到
`AnsiColors` —— 即 React 的 `TOKEN_BY_BASIC_RGB` 所映射的 token 调色板
（`label-primary`、`label-tertiary`、各 state 别名与静态 `blue400`），并保留
同一条规则：自带背景色的 run 保留字面 ANSI 颜色对。Reverse 交换已解析的
颜色对；下划线与删除线共享一个槽位且后声明者胜出；blink 与垂直光标寻址被
无效果地消费 —— 与 React 完全一致。

- `parseAnsiLines` 对齐 React API（每行输出一个 `AnsiLine` 的 `AnsiSpan`）；
  `ansiToSpan` 把各行拼进一棵可选择的 span 树供整块调用方使用。
- `DsTerminalBlock` 逐行渲染解析后的带样式行 —— 已记录的颜色缺口关闭 ——
  head/tail 截断现在按重放后的行数计算。
- 会话工具行与工具插件的 `BashToolCard` 都消费共享渲染器；`ansi_span.dart`
  被删除，调色板因此只有一个归属。
- `plugins/` 的跨面导入只到达 `widgets/primitives`，与 React 赋予
  `ui-primitives` 的共享原语角色一致。

有意不移植：完整终端模拟器。本次重放覆盖单张输出卡内的逐行光标移动；
alternate screen、scroll region 与全屏 TUI 重绘仍在范围之外，与 React 的
解析器一致。交互式实时终端面板（超出本变更）需要真正的模拟器，已在
terminal-controller 计划下跟踪。

## Verification

- `test/plugins/conversation_render_test.dart` 钉住移植后的契约：token 映射、
  装饰、reverse、扩展颜色、重放用例（`100%\rOK` → `OK0%`、擦除模式、
  宽字符对空白化、tab 空白、跨行 SGR 线程）。
- `test/widgets/primitives_p1_audit_test.dart` 与
  `test/goldens/surface_goldens_test.dart` 已为带样式行更新；terminal 与
  chat-fixture 金样按 token 映射色重录（视觉变化是有意的：ANSI 颜色现在
  在原本被剥掉的地方渲染出来了）。
- `flutter analyze` 在变更文件上干净；`flutter test` 全量绿色，仅余在干净
  `HEAD` worktree 上同样失败的既有 connection/cache 失败。
