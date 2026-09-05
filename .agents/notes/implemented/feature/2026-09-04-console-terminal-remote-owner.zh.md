# Agent Note: 控制台终端经由 console 主体到达 Remote 客户端

Status: implemented

## Problem

持久 PTY 缝隙（`ctx.terminals`）端到端都是精确 Agent 范围：服务以注册的 Agent 为键管理会话，后端从所有者的会话解析沙箱策略并据此限制沙箱模式变更，而消费方（`tool-terminal` 以及持久 `bash` 与 `pwsh` shell 工具）转发执行中的 agent。客户端终端面板——React 参考从未有过的终端能力——因此没有合法的所有者：不存在为"驱动 shell 但没有模型会话"的面准备的所有者种类，也没有任何 Remote 命名空间暴露终端动词。把 console 硬塞进一个合成 Agent 会污染以会话为键的 agent 注册表，并把 console 会话泄漏进模型面。

## Decision

`TerminalSessionService` 接受可辨识的 `TerminalOwner` 联合，不再接受裸 `Agent`：`agent` 所有者包装确切存活的 `Agent`（存活性取决于注册表条目），`console` 所有者是没有模型会话的客户端终端主体，自带 effect 作用域（存活性取决于该作用域的 dispose）。限制比较的是拥有的权威对象——agent 所有者取 `Agent`，console 所有者取主体对象——而不是包装器，因此所有权在包装器重建后仍然成立，强度与此前完全一致。`tool-terminal` 保留稳定的按 agent 包装器（WeakMap 缓存），因为它的限制基于身份比较。

- `terminal-bash` 按所有者种类分支：agent 所有者从其会话解析沙箱策略并保留沙箱模式限制；console 所有者以无 agent 方式解析，落到部署默认模式与配置的 workspace 根，且不安装限制，因为不存在属于它的、可改变模式的会话。
- `packages/api/terminal-controller` 是新的 Remote 归属方：`ctx.remote.terminal` 携带 `list/open/send/read/signal/close`，每个动词都操作每宿主唯一的 `console` 主体。主体的 effect 作用域是控制器 fiber 的子插件，因此控制器 dispose 时经由 PTY 服务既有的所有者清理路径拆除其会话。PTY 失败映射到稳定的 Remote 代码（`terminal/no-session`、`terminal/send-active`、`terminal/unavailable`）；未知会话、发送占用、后端缺失路径由 host spec 钉住。
- 控制器与其它控制器并排组合进 `bundle/web-app`。它不发布 TS 客户端面——尚无浏览器消费方——因此 Flutter 直接消费线协议契约，未来 React 采用时读取同一份 `./types` 投影。

有意延期并记录在控制器 README 中：按设备划分的 console 池（今天的 Remote 动词不携带调用方身份）、连续按键流与 PTY resize（当前缝隙是有界逐行模式的后端约定）、重连安全的 follow 流。

构建中的一个发现一并记录：仓库生成的 tsconfig 别名只覆盖裸说明符，暴露公开 `/types` 子路径的包需要手写 `/*` 条目（directory-picker 有，`dsh-terminal` 没有）。缺了它，Typert 分析器把 `@deepseek-ai/dsh-terminal/types` 解析到陈旧的 `lib/` 构建产物而非 `src/`，导出查找随之失败。修复是一行手写别名，沿用既有模式。

## Verification

- `packages/terminal/terminal/tests/service.spec.ts`：agent 套件在包装后的所有者下原样通过，另有 console 测试覆盖 spawn/send/signal/read 限制、外来主体拒绝、作用域 dispose 拆除与 dispose 后 `OWNER_NOT_LIVE`。
- `packages/terminal/terminal-bash/tests/index.spec.ts`：console 所有者 spawn 钉住无 agent 策略（部署默认模式、配置的根、无 `sessionId`）与主体的 `DSH_SESSION_ID` 环境；agent 路径测试现包装所有者。
- `packages/api/terminal-controller/tests/terminal-controller.host.spec.ts`：命名空间与方法面（`remoteMethods`）、open→list→read→send→signal→close 全往返、稳定失败码、重名拒绝、作用域 dispose 拆除。
- `pnpm run build` 全绿，新 Remote 命名空间的 Typert 产物已生成。
