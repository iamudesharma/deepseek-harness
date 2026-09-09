# Agent Note: 远程 TLS 监听器、bearer 强制与操作员控制台

Status: implemented

[English](2026-09-06-remote-transport-auth-console.md) | 中文

## Problem

配对契约交付时没有传输层：webserver 仅明文，不存在供二维码/手动 URL 指向的 `https://` 端点；bearer/token/ticket 机制没有强制点——`authenticateRequest`、`isRemoteAuthorized` 与 WS ticket 校验在其自身测试之外无人引用。局域网客户端处于 fail-closed（浏览器围栏对无 cookie 调用者返回 401），但没有任何路径能放行它们。操作员审批同样卡住：pair 日志行引用了一个从不存在的 `dsh remote approve` 命令，而审批存储是第二个进程无法触及的进程内内存。

## Decision

主机侧远程访问现已端到端打通。`WebServer.listenTls` 以主机身份证书通过 HTTPS 提供组合路由；`remote-tls-listener` 插件在启用 `--remote` 时绑定局域网接口（配置默认 `0.0.0.0:3443`），否则休眠，明文 loopback 保持不变。connection `/api` 路由与网关 `/api/remote.mux` 升级在围栏拒绝后咨询 foundation：公开引导放行，bearer `full` 在其校验过的 ALS 上下文中按特权策略放行，一次性 ticket 放行 mux 升级，其余保持围栏拒绝。`remote-operator-console` 插件给运行进程一个纯 TTY stdin 控制台（`qr`、`approve`/`deny` 支持完整或无歧义前缀 nonce、`pending`、`devices`、`help`）及启动时二维码展示；非 TTY 主机保持休眠。Flutter 在原生端钉扎主机证书（QR 中的 `certFp` 与 `describe` 中的 `tlsFingerprint` 送入 HTTP 与 WebSocket 回调），网页端记录一次性浏览器信任步骤。

## Enforcement design

围栏仍是唯一前门，bearer 逻辑从不削弱它：带 cookie 的浏览器永不到达回退路径，无 cookie 的 loopback 行为与之前完全一致，特权策略（`credentials.*`、`host.*`、`settings.*`、`agentPreset.*`）拒绝 bearer 调用者，线路同时接受斜线或点分形式。强制落地激活了一个潜伏的策略 bug——点分词表从不匹配斜线线路端点，特权方法将被归为 safe——现已由斜线用例钉住。一次真实 `dsh web --remote` 烟囱运行又抓住第二个潜伏 bug：Flutter 以平铺 args 发送 `remote.pair`（`remote.revoke` 同），而单参数 Typert 方法取 `args.request`——配对从未可能在真机上成功。两处调用点现已包入 `request`，并由线路形状测试钉住。mux ticket 检查复用 `WsTicketStore.validate`，保留一次性与审计。`RemoteMuxClient.close` 的迭代竞态（关闭过程中 socket 丢失清空流表）在停止时崩溃；改为快照关闭，已在之前 75% 抖动的重连测试上 6/6 验证通过。

## Alternatives considered

- **第二进程 `dsh remote approve` CLI** —— 已拒绝：审批存储是进程内存，另一进程触及它需要认证的 loopback 管理通道加启动器子命令机制；stdin 控制台以零新增信任面一次解决审批、重签与巡检。
- **主端口 TLS（协议嗅探）或全站 HTTPS** —— 已拒绝：嗅探引入安全敏感的多路复用器，全站 HTTPS 破坏本地工具、监管进程与 Flutter `LocalTarget` 路径；第二监听器保持两种姿态完好。
- **默认开启 PIN** —— 已拒绝：不可猜 nonce 加显式主机审批已绑定仪式，默认 PIN 不增加安全反而拖累手动录入；操作员按仪式策略自行选用。

## Consequences

- `dsh web --remote` 启动打印可扫二维码加手动值，`qr` 可重签；仪式仍 5 分钟过期，配对仍需 30 秒配对窗口内操作员批准。
- 主机证书仅带 loopback SAN，局域网 IP 上浏览器在 SAN 完备轮换落地前显示名称失配警告；原生客户端按指纹钉扎不受影响，网页端需手动录入屏已写明的一次性信任。
- 延后：主机证书局域网 SAN、`remote.issue` 仪表盘重签端点、设备持有证明、局域网发现、React 仪表盘卡片（无明确许可 React 保持只读）。

## Verification

- `packages/host/webserver/tests/tls-listener.spec.ts`（3）：Loader 组合以生产证书材料通过 HTTPS 提供路由，坏 PEM 大声失败，重复绑定失败；既有 4 个不变通过。
- `packages/host/remote-access/tests/remote-boot.spec.ts`（3）：启用 TLS 的 Loader 组合提供 HTTPS 并报告 `tlsPort`/指纹/`configSnapshot`；关闭时保持纯 loopback 且无监听器；经启动后服务的完整配对生命周期（仪式、批准、令牌签发、设备记录、令牌校验）。
- 真机烟囱：真实 `dsh web --remote` 经 TLS 提供带指纹的 `remote.describe`，对无 bearer `session/list` 返回 401，把 `remote.pair` 路由进配对校验（本次运行抓住上述平铺 args bug）。
- `packages/host/remote-access/tests/remote-authorize.spec.ts`（13）：一元调用三态（引导、无/坏/未知/吊销/过期 bearer、特权 403、ws-ticket 403、ALS 传递）与 mux（缺/坏/重放 ticket、错 scope 403），加斜线策略钉。
- `packages/host/remote-access/tests/operator-console.spec.ts`（18）：每条命令、前缀解析、休眠模式、Loader settled 与启动失败路径、`apply` 变体；`pairing-qr.ts` 全维度 100%。
- `packages/api/gateway/tests/mux-upgrade-auth.host.spec.ts`（5）：无 foundation 时保留围栏拒绝，decline/forbidden 映射，放行时真实 TCP 101，检查器失败时 401。
- `packages/client/connection/tests/node-half.host.spec.ts`（+4）：放行执行带映射端点的分发，forbidden 跳过分发，decline 保持 401，畸形路径永不咨询 foundation。
- Flutter：`tls_pinning_test.dart`（4）钉住匹配/失配/畸形向量；`qr_payload_test.dart`（+2）与 `connection_client_remote_describe_test.dart`（+1）覆盖 `certFp`/`tlsFingerprint`；`connection_client_remote_pair_test.dart`（2）钉住 `args.request` 配对形状；`test:gui` 4201 通过，仅预存 SameSite 失败。
- `build:lib:host` 与 `typecheck:contracts-ready` 通过；新增/修改的主机文件 oxlint 干净，`verify-export-jsdoc` 无新增。
