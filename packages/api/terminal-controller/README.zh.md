---
description: "控制台终端 Remote 命令：基于持久 PTY 服务的客户端终端面板，限制在单一 console 主体内，提供有界逐行发送。"
kind: "package-reference"
---

# @deepseek-ai/dsh-api-terminal-controller

[English](README.md) | 中文

## 概述

`dsh-api-terminal-controller` 把宿主的持久终端会话以生成的 `ctx.remote.terminal` 命名空间暴露给 Remote 客户端，使客户端终端面板可以打开、驱动并关闭 console 会话，走的是与其他 Remote 命名空间相同的传输。每个动词都操作同一个 console 主体——一个不拥有模型会话、对 agent 工具不可见的 `TerminalOwner`——因此 console 会话池原样继承 `ctx.terminals` 的精确所有者限制、有界发送与等待完成的清理。控制器不添加任何终端机制：已挂载的后端拥有启动、就绪与输出上限，与面向模型的工具完全一致。

## 目录

- [使用本包](#use-this-package)
- [理解实现](#understand-the-implementation)
- [进一步探索](#further-exploration)
- [模型体验](#model-experience)
- [已知限制与延期工作](#known-limitations-and-deferred-work)
- [开发备注](#dev-note)

-----

<a id="use-this-package"></a>
## 使用本包

当 Remote 客户端需要访问宿主上的 console 终端时挂载本控制器。web-app bundle 将它与 `@deepseek-ai/dsh-terminal`、`@deepseek-ai/dsh-terminal-bash` 一起组合；没有后端时 `terminal/open` 以 `terminal/unavailable` 拒绝，其余动词仍按会话不存在返回各自代码。没有 PTY 服务的组合仍能启动——此时每个动词都回答 `terminal/unavailable`（settingsController 缺 provider 模式）。授权依赖 Remote 传输：能访问 `ctx.remote.workspace` 的调用方即可访问 `ctx.remote.terminal`。

### 六个动词

| 动词 | 行为 | 结果 |
|---|---|---|
| `terminal/list` | 列出 console 主体的存活会话 | 按发布顺序的快照 |
| `terminal/open` | 通过已注册后端打开一个 console 会话 | 快照加有界 MOTD |
| `terminal/send` | 写入一行并等待就绪 | 有界 viewport、等待原因、会话状态 |
| `terminal/read` | 读取一页有界 scrollback | 保留文本与分页元数据 |
| `terminal/signal` | 向前台进程组投递一个允许的信号 | 已投递的进程组 id |
| `terminal/close` | 关闭会话并等待停稳 | 是否由本次调用关闭 |

`terminal/open` 接受可选 `type`；缺省时显式解析为第一个已注册的后端类型，没有挂载任何后端时以 `terminal/unavailable` 拒绝。发送结果携带与面向模型工具相同的等待原因（`stdin_read`、`inferred_idle`、`timeout`、`session_exit`）。

### 失败

稳定的 Remote 代码：`terminal/no-session`（未知或已关闭的 id）、`terminal/send-active`（另一个发送正占用该会话）、`terminal/unavailable`（类型没有后端、会话名被占用、主体已 dispose，或服务正在 dispose）。其余失败原样交由 Gateway 的故障映射处理。

<a id="understand-the-implementation"></a>
## 理解实现

<details>
<summary>实现细节——点击展开</summary>

控制器是 `ctx.terminals` 之上单一 `console` 主体背后的薄适配层。主体的 effect 作用域是控制器 fiber 的子插件：其 dispose 结束该主体，PTY 服务在该作用域展开期间清理 console 会话。六个动词只添加稳定的 Remote 失败映射与显式的默认后端解析；启动、发送互斥、有界读取、信号与清理都是 PTY 服务的既有行为。

| 文件 | 职责 |
|---|---|
| [`src/index.ts`](src/index.ts) | `TerminalController`：六个 Remote 动词、console 主体作用域、失败映射 |
| [`src/types.ts`](src/types.ts) | 线协议请求、结果、失败代码与会话视图再导出 |

</details>

-----

<a id="further-exploration"></a>
## 进一步探索

- [terminal 服务](../../terminal/terminal/README.zh.md)——console 动词继承的后端注册、所有者限制与清理语义。
- [terminal-bash 后端](../../terminal/terminal-bash/README.zh.md)——随附 shell 后端、其沙箱解析与 console 所有者策略行为。
- [终端子系统参考](../../../docs/subsystems/terminal.zh.md)——所有者联合与生成的 `ctx.terminals` 接口面。

<a id="model-experience"></a>
## 模型体验

无。console 面是浏览器与客户端控制状态，不注册提示词、工具或会话事件。console 会话对模型工具不可见：`terminal_list` 只列出调用 agent 自己的会话，而 console 主体不是 agent。

#### KV Cache 影响

无；console 流量不会进入任何模型请求。

<a id="known-limitations-and-deferred-work"></a>
## 已知限制与延期工作

这些限制说明 console 面何时不合适或需要运维注意。它们是当前包约束，不是积压清单。

- **每宿主一个 console 主体**——所有配对设备共享一个 console 会话池。按设备划分会话池需要 Remote 分发携带调用方身份事实，而今天的 Remote 动词都不携带。
- **仅逐行模式**——面板通过后端的有界约定驱动发送与 scrollback 页；连续按键流、PTY resize 与全屏 TUI 交互需要持久 PTY seam 尚未暴露的后端能力。
- **没有 follow 流**——输出以发送 viewport 与显式读取到达；重连安全的输出流（`workspace/follow` 模式）推迟到出现需要它的消费方。
- **cwd 由后端解释**——`terminal/open` 把请求的目录交给后端；生效的沙箱模式是部署默认值，运维应把 console 面纳入考虑来设置它。

<a id="dev-note"></a>
## 开发备注

<details>
<summary>维护者的工作上下文——点击展开</summary>

无。

</details>

**运行时不变式：** 不发布伴生入口。console 会话池是单一主体背后的 `ctx.terminals` 状态；控制器不发布独立的 lifecycle stream 或 snapshot，因此没有可供伴生检查的独立观测。
