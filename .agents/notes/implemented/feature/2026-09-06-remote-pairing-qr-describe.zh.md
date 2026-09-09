# Agent Note: 远程配对二维码签发与免认证主机描述

Status: implemented

[English](2026-09-06-remote-pairing-qr-describe.md) | 中文

## Problem

Flutter 远程配对只有二维码消费端、没有主机生产端：`AddComputerScreen` 提示用户运行 `dsh web --remote` 并扫描二维码，但主机端没有任何代码签发配对仪式或渲染 `dsh://pair` 载荷，因此唯一可用的路径是手工抄写操作员能找到的 `hostId`/`nonce`/`PIN`。手动录入进一步放大了缺口：它发送 `hostPublicKey: 'placeholder'`，跳过了二维码路径强制执行、并在 `remote.pair` 之后重新校验的主机钉扎保证。

## Decision

主机在 `packages/host/remote-access/src/pairing-qr.ts` 拥有二维码签发：`issuePairingQr` 签发 `PairingStore` 条目（nonce、可选 PIN、TTL），返回校验后的载荷及其 `dsh://pair?data=base64url(json)` URI、JSON 形式和过期时间；`encodePairingQrPayload`/`decodePairingQrPayload` 与 Flutter `QrPayload` 执行相同的字段校验，该模块从包入口导出。新增的免认证 `remote.describe` 端点仅返回公开主机身份（`hostId`、`hostPublicKey`），使手动 URL 录入在配对前钉扎主机；认证中间件将其与 `remote.pair` 同等对待（公开、无需 bearer）。Flutter 侧，`ManualEntryScreen` 在 nonce/PIN 步骤之前调用 `remote.describe` 填充主机 ID 与公钥字段（占位密钥不再上路），`ConnectionClient.remoteDescribe` 为类型化接口，`QrPayload.toQrUri` 与主机编码器互为镜像，配对每次尝试生成一个随机的 32 字节设备密钥，并使用带平台标签的显示名。

## Host QR wire

载荷为 `{baseUri, hostId, hostPublicKey, nonce, pin?, exp, displayName?}`，两侧执行相同的模式（43 字符 base64url `hostId`、UUID `nonce`、6 位数字 `pin`、整数 `exp` 在解码时对时钟检查）。`issuePairingQr` 接受 live `PairingStore`、base URI、主机身份和仪式选项（`withPin`、默认 5 分钟的 `ttlMs`、`displayName`、`now`/生成器测试接缝）；过期时间为 `now + ttlMs` 而非存储条目的时钟，两者按构造保持一致。

## Alternatives considered

- **主机自行渲染二维码图片（终端 ascii / 网页仪表盘卡片）** —— 已拒绝：图片渲染属于表现层，而缺失的是两侧共享的仪式到载荷契约；URI/JSON 形式独立地解除了 CLI、仪表盘与 Flutter 工作的阻塞，渲染后续跟进且无契约风险。
- **复用 `host.describe` 获取手动录入身份** —— 已拒绝：该端点在主机侧已退役（Flutter 控制器将其视为机会性调用，`404` 时继续），而 `remote.describe` 与配对契约一同版本化，且恰好携带手动录入所需的两个公开字段。
- **手动录入中 `hostPublicKey` 可选、信任 `pair` 响应** —— 已拒绝：这把钉扎推迟到首次建联之后，首次交换中的 MITM 将无法察觉；先取 `describe` 使手动录入与扫码等价。

## Consequences

- 手动录入现在先钉扎后配对：失配或恶意主机在确认屏即被拒绝，与扫码行为一致，占位密钥旁路已消除。
- `remote.describe` 按设计为公开面（仅密钥材料，无令牌或设备数据）；特权策略保持不变，其余 `remote.*` 端点仍需 bearer `full`。
- 本记录撰写时延后：主机二维码渲染、Flutter TLS 指纹展示、局域网发现/mDNS、设备持有证明。主机二维码渲染（ASCII 加手动块）与 TLS 指纹 plumbing 已在[传输/认证/控制台记录](2026-09-06-remote-transport-auth-console.zh.md)落地；局域网发现、设备持有证明、局域网 SAN、React 仪表盘仍开放。

## Verification

- `packages/host/remote-access/tests/pairing-qr.spec.ts`（20）：构建/编码/解码往返（URI、JSON、裸 base64url）、各种畸形、过期、默认与 PIN/TTL/显示名/自定义生成器签发、`describe`+`pair` 免认证、`describe` 返回 live 主机身份；`pairing-qr.ts` 语句/分支/函数/行 100%。
- `apps/flutter/test/features/devices/qr_payload_test.dart`（5）：JSON 解析、`toQrUri` 往返、裸 base64url、过期与畸形拒绝。
- `apps/flutter/test/api/connection_client_remote_describe_test.dart`（2）：`remoteDescribe` 请求 `/api/remote/describe` 并返回身份；缺字段抛 `FormatException`。
- `pnpm run build:lib:host` 重新生成带 `describe` 的 `lib/typert.host.js` / `lib/typert.remote-client.js`；`typecheck:contracts-ready` 通过；新增/修改的两个主机文件 oxlint 干净。
