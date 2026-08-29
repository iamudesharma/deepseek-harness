# dsh_flutter

[English](README.md) | 中文

DeepSeek Harness（`dsh`）的 Flutter 移植——与 `dsh web` 复用同一套宿主机协议、会话日志与插件接缝，原生渲染于 iOS、Android、macOS 与 Web。

## 概述

`apps/flutter` 在 Flutter 上镜像 React Web 客户端（`packages/client/*`）：Riverpod 运行时消费宿主机的 mux/host 事件流，基于 slot-registry 的插件壳组合界面，`go_router` 驱动路由。宿主机仍是唯一事实来源；应用作为展示壳将帧折叠为 `SessionModels`/`TranscriptFold`，并通过类型化 RPC 网关提交轮次。

近期里程碑：基于 `flutter_gen_ai_chat_ui` 的会话（thinking/tool 渲染与 follow-threshold 滚动）、移动端挂起时 `ConnectionClient.abortEventStreams` 对被追踪 WebSocket 的回收，以及 `host-remote-access`/`remote-notifications` 的二维码配对与票据化 WebSocket 接线。

## 环境要求

- Flutter 3.13+ / Dart 3.13（`flutter --version`）
- 已从源码构建的宿主机 `dsh`（仓库根目录 `pnpm run build`）或可达的 `npx @deepseek-ai/dsh web` 端点
- macOS 桌面：Xcode 15+ 与 CocoaPods；Web：Chrome/Edge

## 项目结构

```text
apps/flutter/
  lib/src/
    core/           # connection, session, slots, renderer, services, bootstrap
      api/          # frames, rpc_envelope, host_description
      bootstrap/    # app_plugins (PluginHost wiring, ShellServices)
      connection/   # ConnectionClient, ConnectionController, Lifecycle, Target, SecureTokenStore
      session/      # live_sync, sessions_controller, session_models, projection_store, transcript_fold, host_session_policy
      slots/        # SlotRegistry (declaration + authorization)
      renderer/     # SlotOutlet
    features/       # cross-cutting UI state: sidebar, locale, conversation, tool, workspace, jobs etc.
    plugins/        # DshPlugin mirrors of React slots: conversation, tool, trajectory, message_feedback, workspace, model_selection, directory_picker, input_trigger, attachment, brand, settings, jobs/workflow
    routing/        # app_router (go_router) + WelcomeScreen hero
    theme/          # AppTheme, Appearance, ThemeRuntime
    widgets/        # layout AppFrame, primitives (hover_card, json_tree, fish_logo...)
  test/
    goldens/        # golden images + fixtures
    connection/     # pairing, devices, remote_target, update_queue generation tests
    plugins/        # chat_view matrix, scroll, mobile_conversation
    session/        # tool_stream, host_session_policy
```

## 核心子系统

- **连接**：`ConnectionClient`（类型化 Typert RPC、WS 票据流 `remote.pair`/`remote.ws-ticket`/`remote.refresh`、对 `_trackedEventStream` 的 `abortEventStreams` 集合）、`ConnectionController`/`ConnectionLifecycle`/`ConnectivityHandler`、`SecureTokenStore`（Web 与移动端分支）
- **会话**：`live_sync` 将 mux/host 帧折叠为 `SessionModels`/`ProjectionStore`/`TranscriptFold`/`ToolStream`（assistant `chunk` → `partialToolCalls`）、`host_session_policy` 抽取 `isWorkspaceAttachFailure`/`adoptHostBornSession`，question 优先于 approval 的 pending 归并
- **Slot 与插件**：`SlotRegistry` + `SlotOutlet`/`HoleOutlet`；`DshPlugin` 按工具名注册 `ConversationController.renderers`、`ToolPresentationRegistry` 的按工具卡片，以及账本条目（`conversation`、`conversation.composer.dock`、`workspace` 等）
- **路由**：`app_router.dart`（`WelcomeScreen` hero 创建空白会话，`selectedWorkspaceProvider` → `createSession`）、`WorkspacesMobile`/`SessionsMobile`/`Devices` 与配对界面（`qr_payload`、`pin_entry`、`host_confirm`）

## 运行

```sh
cd apps/flutter
flutter pub get
flutter run -d macos        # chrome | ios | android
flutter run -d chrome --dart-define=DSH_HOST=http://127.0.0.1:3080
```

在应用内「设置 → 连接」配置宿主机，或通过 provider / `--dart-define` 覆盖 `ConnectionTarget`。远端模式复用与宿主机 `remote-access` 插件共享的单一 device-registry 文件。

## 配对与远端接入

基于唯一未鉴权端点的二维码握手：

1. 移动端：设备 → 添加电脑 → 扫描 `dsh web --remote` 二维码（`hostId`、`deviceId`、`displayName`、`devicePublicKey`、`nonce`、可选 PIN）
2. `remote.pair` → bearer `full` token → `remote.ws-ticket`（scope `ws`）用于票据化 mux/host WebSocket → `remote.refresh` 轮换；挂起时 `abortEventStreams` 关闭 mux/host 套接字
3. 宿主机在 `WebSocketDownlinks` 中强制校验（`wsTickets.validate`、hostId 匹配、重放/吊销检查）及 `remote-notifications` 推送注册

见 `packages/host/remote-access/src/*`（`host-identity`、`device-registry`、`token-service`）与 `docs/superpowers/specs/2026-08-21-migration-rework-v1.1-design.md` 中的 tracker/skill 约定。

## 测试

```sh
flutter test                          # all unit/widget
flutter test test/connection          # connection generation / pairing
flutter test test/session/tool_stream_test.dart
flutter test test/goldens --update-goldens   # refresh goldens after intentional UI change
flutter analyze                        # strict, noImplicitAny
dart format --set-exit-if-changed lib test
```

Goldens 位于 `test/goldens/goldens`（按组件）与被忽略的 `test/goldens/failures`（永不提交）。业务逻辑保留在 `core/{session,connection,slots}`——展示组件为纯 `PropsRuntime` 风格输入，无需启动完整壳即可渲染。

## 构建

```sh
flutter build macos
flutter build web --wasm   # CanvasKit/Wasm for Web
flutter build apk --release
flutter build ios --release
```

桌面 Web 通过条件导入使用 `window_manager` 与 `file_picker`，同一份代码可在 `web` 上构建而不会引入桌面符号。主题 token 为 `--dsw-*` 的 CSS 等价物，映射到 `lib/src/theme` 的 `ThemeData`/`ColorScheme`。

## 相关文档

- 根目录 `README.md` — `npx @deepseek-ai/dsh web` 快速开始与架构链接
- `docs/architecture.md` — 插件/宿主机/RPC 不变量
- `docs/superpowers/plans/2026-08-21-migration-rework-v1.1.md` — 迁移重做 v1.1 计划（tracker、skills、gate）
- `packages/host/remote-access/README.md` / `packages/host/remote-notifications/README.md` — 宿主机侧配对与推送原语
