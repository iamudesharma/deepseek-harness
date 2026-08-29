# DeepSeek Harness

English | [中文](README.zh.md)

DeepSeek Harness (`dsh`) is an open-source agent harness developed by [DeepSeek AI](https://deepseek.com).

It is built on an **everything-is-a-plugin** architecture and powered by [Cordis](https://github.com/cordiverse/cordis), whose design is described in [_A Programming Paradigm for Spatiotemporal Composability_](https://arxiv.org/abs/2608.25512).

Documentation: [https://deepseek-harness.github.io/deepseek-harness/](https://deepseek-harness.github.io/deepseek-harness/)

## Developer preview

DeepSeek Harness is in _developer preview_ and iterating rapidly. **THERE WILL BE COMPATIBILITY-BREAKING CHANGES.**

Review the [safety notice](SAFETY.md) before running the project.

## Run

### Run from `npm`

Install `Node.js`, then run:

```sh
npx @deepseek-ai/dsh web
```

The command starts the Web UI at `http://127.0.0.1:3080` by default and opens it in the default browser for a local launch. An SSH launch only prints the host URL because the SSH client or editor owns the local forwarded address. Pass `--no-open` to run the server without opening a browser. See [Web UI guide](docs/user/guide/index.md).

### Run from source

To run from a repository checkout:

```sh
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness
pnpm install
pnpm run build
pnpm dsh web
```

`pnpm run build` prepares the repository artifacts. `pnpm dsh web` uses those built artifacts without rebuilding.

## Flutter app (developer preview)

The Flutter client at `apps/flutter` is a cross-platform port of the harness UI for iOS, Android, macOS and Web. It shares the same host protocol and session log as `dsh web`, rendering conversation, device pairing, and workspace surfaces natively.

### Tech stack

- **Framework**: Flutter 3.13+ / Dart 3.13, Riverpod 2.6, `go_router` for navigation and `flutter_localizations` for i18n
- **Transport**: `http` + `web_socket_channel` against the host mux/host event streams; `flutter_secure_storage` for remote bearer tokens; `connectivity_plus` for reachability; `ConnectionClient.abortEventStreams` tears down tracked channels on mobile suspend
- **UI**: Material + `flutter_markdown` for message rendering; `mobile_scanner` for QR pair, `image_picker`/`file_picker`/`desktop_drop` for attachments; `window_manager` for desktop chrome (via conditional imports so Web stays clean)
- **State**: Riverpod providers over `Connection`/`Session`/`Workspace`/`Projection` runtimes; `live_sync` folds mux/host frames into `SessionModels`/`ProjectionStore`/`TranscriptFold`/`ToolStream` with host-born session adoption and approval/question reconciliation

### Run the Flutter app

```sh
cd apps/flutter
flutter pub get
flutter run -d macos        # or: chrome, ios, android
flutter test                # unit + widget (goldens in test/goldens)
flutter analyze             # dart analyze (strict)
```

Configure the host target via in-app Settings → Connection or a `ConnectionTarget` provider override. Remote pairing is a QR handshake (`remote.pair` → `remote.ws-ticket`/`remote.refresh`) backed by `packages/host/remote-access` (`host-identity`, `device-registry`, `token-service`, `tls`) and `packages/host/remote-notifications`.

### Architecture

`lib/src/core` owns `ConnectionClient`/`ConnectionController`/`ConnectionLifecycle`, `live_sync` + `sessions_controller` + `session_models`/`projection_store`/`transcript_fold`, and the `slots`/`renderer` seam. `lib/src/plugins` mirrors the React slot graph (`conversation`, `tool`, `trajectory`, `message_feedback`, `workspace`, `model_selection`, `directory_picker`, `input_trigger`, `attachment`, `brand_official`, `settings`, `jobs`/`workflow_run`/`deliverables`/`goal` etc.) through `DshPlugin`/`SlotRegistry` instead of Cordis. Routing is `go_router` (`lib/src/routing/app_router.dart`) with a `WelcomeScreen` hero that creates blank sessions via `host_session_policy`. See `apps/flutter/README.md` for full layout, testing, and build notes.

## Community and support

- Submit feedback or bug reports through [GitHub Discussions](https://github.com/deepseek-ai/deepseek-harness/discussions).
- Add the [`dsh-plugin`](https://github.com/topics/dsh-plugin) topic to your plugin repository for discoverability.
- Join <a href="https://discord.gg/Ycq5dCaS4">DeepSeek Harness Discord community</a>.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Development

Start with the [development guide](docs/development.md) and [architecture documentation](docs/architecture.md).

For agents, follow [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE)

Third-party dependencies and their licenses are disclosed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
