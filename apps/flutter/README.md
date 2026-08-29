# dsh_flutter

English | [中文](README.zh.md)

Flutter port of DeepSeek Harness (`dsh`) — the same host protocol, session log and plugin seams as `dsh web`, rendered natively for iOS, Android, macOS and Web.

## Overview

`apps/flutter` mirrors the React web client (`packages/client/*`) on Flutter: Riverpod runtimes consume the host mux/host event streams, a slot-registry plugin shell composes screens, and `go_router` drives navigation. The host remains the source of truth; the app is a presentation shell that folds frames into `SessionModels`/`TranscriptFold` and submits turns through the typed RPC gateway.

Recent milestones: `flutter_gen_ai_chat_ui` backed conversation with thinking/tool rendering and follow-threshold scroll, `ConnectionClient.abortEventStreams` for tracked WebSocket teardown on mobile suspend, and `host-remote-access`/`remote-notifications` wiring for QR pairing and ticketed WebSockets.

## Requirements

- Flutter 3.13+ / Dart 3.13 (`flutter --version`)
- Host `dsh` built from source (`pnpm run build` at repo root) or a reachable `npx @deepseek-ai/dsh web` endpoint
- For macOS desktop: Xcode 15+, CocoaPods; for Web: Chrome/Edge

## Project layout

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

## Key subsystems

- **Connection**: `ConnectionClient` (typed Typert RPC, WS ticket flows `remote.pair`/`remote.ws-ticket`/`remote.refresh`, `abortEventStreams` set for `_trackedEventStream`), `ConnectionController`/`ConnectionLifecycle`/`ConnectivityHandler`, `SecureTokenStore` (web vs mobile)
- **Session**: `live_sync` folds mux/host frames → `SessionModels`/`ProjectionStore`/`TranscriptFold`/`ToolStream` (assistant `chunk` → `partialToolCalls`), `host_session_policy` extracts `isWorkspaceAttachFailure`/`adoptHostBornSession`, question-beats-approval pending reconciliation
- **Slots & plugins**: `SlotRegistry` + `SlotOutlet`/`HoleOutlet`; `DshPlugin` registers `ConversationController.renderers` per tool name, `ToolPresentationRegistry` for per-tool cards, and ledger entries (`conversation`, `conversation.composer.dock`, `workspace` etc.)
- **Routing**: `app_router.dart` (`WelcomeScreen` hero creates blank sessions, `selectedWorkspaceProvider` → `createSession`), `WorkspacesMobile`/`SessionsMobile`/`Devices` and pairing screens (`qr_payload`, `pin_entry`, `host_confirm`)

## Run

```sh
cd apps/flutter
flutter pub get
flutter run -d macos        # chrome | ios | android
flutter run -d chrome --dart-define=DSH_HOST=http://127.0.0.1:3080
```

Configure the host in-app at Settings → Connection, or override `ConnectionTarget` via provider / `--dart-define`. Remote mode uses the single device-registry file shared with the `remote-access` host plugin.

## Pairing & remote access

QR handshake over the only unauthenticated endpoint:

1. Mobile: Devices → Add Computer → scan `dsh web --remote` QR (`hostId`, `deviceId`, `displayName`, `devicePublicKey`, `nonce`, optional PIN)
2. `remote.pair` → bearer `full` token → `remote.ws-ticket` (scope `ws`) for ticketed mux/host WebSockets → `remote.refresh` for rotation; `abortEventStreams` closes mux/host sockets on suspend
3. Host enforcement in `WebSocketDownlinks` (`wsTickets.validate`, hostId match, replay/revocation checks) and `remote-notifications` push registration

See `packages/host/remote-access/src/*` (`host-identity`, `device-registry`, `token-service`) and `docs/superpowers/specs/2026-08-21-migration-rework-v1.1-design.md` for the tracker/skill contract.

## Testing

```sh
flutter test                          # all unit/widget
flutter test test/connection          # connection generation / pairing
flutter test test/session/tool_stream_test.dart
flutter test test/goldens --update-goldens   # refresh goldens after intentional UI change
flutter analyze                        # strict, noImplicitAny
dart format --set-exit-if-changed lib test
```

Goldens live in `test/goldens/goldens` (per-component) and `test/goldens/failures` is ignored (never commit). Business logic stays in `core/{session,connection,slots}` — presentation widgets are pure `PropsRuntime`-style inputs so they render without a booted shell.

## Build

```sh
flutter build macos
flutter build web --wasm   # CanvasKit/Wasm for Web
flutter build apk --release
flutter build ios --release
```

Desktop Web uses conditional imports for `window_manager` and `file_picker` so the same code builds for `web` without desktop symbols. Theme tokens are `--dsw-*` CSS analogues mapped to `ThemeData`/`ColorScheme` in `lib/src/theme`.

## Related docs

- Root `README.md` — `npx @deepseek-ai/dsh web` quickstart and architecture link
- `docs/architecture.md` — plugin/host/RPC invariants
- `docs/superpowers/plans/2026-08-21-migration-rework-v1.1.md` — migration rework v1.1 plan (tracker, skills, gate)
- `packages/host/remote-access/README.md` / `packages/host/remote-notifications/README.md` — host-side pairing and push primitives
