# DeepSeek Harness

[English](README.md) | 中文

DeepSeek Harness（`dsh`）是由 [DeepSeek AI](https://deepseek.com) 开发的开源 agent harness（智能体框架）。

它构建于**一切皆插件**的架构之上，由 [Cordis](https://github.com/cordiverse/cordis) 驱动，其设计参见论文 [_A Programming Paradigm for Spatiotemporal Composability_](https://arxiv.org/abs/2608.25512)。

文档：[https://deepseek-harness.github.io/deepseek-harness/](https://deepseek-harness.github.io/deepseek-harness/)

## 开发者预览

DeepSeek Harness 处于 _开发者预览_ 阶段，正在快速迭代。**未来将出现破坏兼容性的变更。**

运行本项目前，请阅读[安全说明](SAFETY.zh.md)。

<a id="run"></a>

## 运行

### 通过 `npm` 运行

安装 `Node.js`，然后运行：

```sh
npx @deepseek-ai/dsh web
```

该命令默认会在 `http://127.0.0.1:3080` 启动 Web UI，本机启动时还会用默认浏览器打开页面。通过 SSH 启动时只打印宿主机 URL，因为本地转发地址由 SSH 客户端或编辑器持有。传入 `--no-open` 可仅运行服务器而不打开浏览器。详见 [Web UI 指南](docs/user/guide/index.zh.md)。

<a id="run-from-source"></a>

### 从源码运行

如需从仓库源码运行：

```sh
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness
pnpm install
pnpm run build
pnpm dsh web
```

`pnpm run build` 会准备仓库产物。`pnpm dsh web` 会直接使用这些已构建产物，不会重新构建。

## Flutter 应用（开发者预览）

位于 `apps/flutter` 的 Flutter 客户端是 Harness UI 的跨平台移植，覆盖 iOS、Android、macOS 与 Web。它与 `dsh web` 复用同一套宿主机协议与会话日志，原生渲染会话、设备配对与工作区界面。

### 技术栈

- **框架**：Flutter 3.13+ / Dart 3.13、Riverpod 2.6、`go_router` 路由与 `flutter_localizations` 国际化
- **传输**：`http` + `web_socket_channel` 对接宿主机 mux/host 事件流；`flutter_secure_storage` 持久化远端 bearer token；`connectivity_plus` 感知网络可达性；`ConnectionClient.abortEventStreams` 在移动端挂起时回收被追踪的通道
- **界面**：Material + `flutter_markdown` 渲染消息；`mobile_scanner` 扫码配对，`image_picker`/`file_picker`/`desktop_drop` 处理附件；`window_manager` 负责桌面窗口（通过条件导入，Web 构建保持干净）
- **状态**：基于 Riverpod 的 `Connection`/`Session`/`Workspace`/`Projection` 运行时；`live_sync` 将 mux/host 帧折叠为 `SessionModels`/`ProjectionStore`/`TranscriptFold`/`ToolStream`，支持宿主机创建会话的接管与 approval/question 归并

### 运行 Flutter 应用

```sh
cd apps/flutter
flutter pub get
flutter run -d macos        # or: chrome, ios, android
flutter test                # unit + widget (goldens in test/goldens)
flutter analyze             # dart analyze (strict)
```

在应用内「设置 → 连接」或通过 `ConnectionTarget` provider 覆盖来配置宿主机地址。远端配对为二维码握手（`remote.pair` → `remote.ws-ticket`/`remote.refresh`），由 `packages/host/remote-access`（`host-identity`、`device-registry`、`token-service`、`tls`）与 `packages/host/remote-notifications` 提供。

### 架构

`lib/src/core` 承载 `ConnectionClient`/`ConnectionController`/`ConnectionLifecycle`、`live_sync` + `sessions_controller` + `session_models`/`projection_store`/`transcript_fold` 以及 `slots`/`renderer` 接缝。`lib/src/plugins` 通过 `DshPlugin`/`SlotRegistry` 镜像 React 的 slot 图（`conversation`、`tool`、`trajectory`、`message_feedback`、`workspace`、`model_selection`、`directory_picker`、`input_trigger`、`attachment`、`brand_official`、`settings`、`jobs`/`workflow_run`/`deliverables`/`goal` 等），而非 Cordis。路由为 `go_router`（`lib/src/routing/app_router.dart`），`WelcomeScreen` hero 通过 `host_session_policy` 创建空白会话。完整目录、测试与构建说明见 `apps/flutter/README.md`。

## 社区与支持

- 通过 [GitHub Discussions](https://github.com/deepseek-ai/deepseek-harness/discussions) 提交反馈或 bug 报告。
- 为你的插件仓库添加 [`dsh-plugin`](https://github.com/topics/dsh-plugin) 话题，便于被发现。
- 欢迎加入 DeepSeek Harness 企微群：扫码添加企微小助手并填写入群问卷，完成后小助手会邀请你入群。

<table>
  <thead>
    <tr>
      <th align="center">企微小助手</th>
      <th align="center">入群问卷</th>
      <th align="center">微信公众号</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center"><img src="https://cdn.deepseek.com/harness/readme/community-wecom-assistant.png" alt="DeepSeek Harness 企微小助手二维码" width="180" height="180"></td>
      <td align="center"><a href="https://trtgsjkv6r.feishu.cn/share/base/form/shrcnIt5twSVdLGD52KJBckGCgg"><img src="https://cdn.deepseek.com/harness/readme/community-wecom-survey.png" alt="DeepSeek Harness 入群问卷二维码" width="180" height="180"></a></td>
      <td align="center"><img src="https://cdn.deepseek.com/harness/readme/community-wechat-official-account.png" alt="DeepSeek Harness 团队微信公众号二维码" width="180" height="180"></td>
    </tr>
  </tbody>
</table>

## 参与贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.zh.md)。

## 开发

请先阅读[开发指南](docs/development.zh.md)与[架构文档](docs/architecture.zh.md)。

面向 agent：请遵循 [AGENTS.md](AGENTS.md)。

## 许可证

[MIT](LICENSE)

第三方依赖及其许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
