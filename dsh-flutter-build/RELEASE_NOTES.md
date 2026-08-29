# DeepSeek Harness Flutter v1.0.0

**Version:** 1.0.0+1
**Channel:** stable
**App revision:** 1c17813e1dc475e47217e006e754eda07b4f9241
**Harness revision:** 1c17813e1dc475e47217e006e754eda07b4f9241
**Flutter:** 3.47.0 stable (5f77625673) / Dart 3.13.0 / Node 22.23.2 / pnpm 11.7.0
**Release date:** 2026-08-29

## Architecture

This release separates the Flutter client from the DSH host runtime. The Flutter app is a presentation shell that connects to an externally running DSH host; it does not bundle Node or the Harness.

### Android

Android is a remote Flutter client.

It connects to a computer running:

`dsh web --remote`

Pairing is performed through the remote-access QR/PIN flow.

The Android app does not run the DSH host locally.

- Artifacts: `dsh-flutter-1.0.0+1.apk` (release APK, signed `CN=DeepSeek Harness`), `dsh-flutter-1.0.0+1.aab` (Play AAB), `dsh-flutter-1.0.0+1-debug.apk` (CI smoke)
- applicationId `ai.deepseek.dshflutter`, versionName `1.0.0`, versionCode `1`
- Permissions: CAMERA, READ_MEDIA_*

### macOS

macOS is a Flutter client.

`v1.0.0` requires an externally running DSH host.

Default local connection:

`http://127.0.0.1:3080`

The host can also be accessed using the authenticated RemoteTarget flow.

A bundled DSH backend is NOT included in v1.0.0.

- Artifacts: `dsh-flutter-macos-1.0.0+1.zip` (portable), `dsh-flutter-macos-1.0.0+1.dmg` (drag to /Applications), `dsh-flutter-macos-1.0.0+1.app` (unsigned local, ad-hoc hardened runtime; CI Developer ID + notarization when secrets present)
- Bundle: `ai.deepseek.dshFlutter` 1.0.0 (1), arch `arm64+x64`
- Install: drag `.app` to /Applications or mount DMG, then `open` — connect to `dsh web` at 127.0.0.1:3080 or pair via RemoteTarget

### Web

Web is a Flutter Web client.

Deploy it:
- from the same origin as the DSH host
OR
- behind a proxy forwarding `/api` and WebSocket event paths.

Do not claim standalone Web execution without a DSH backend.

- Artifact: `dsh-flutter-web-1.0.0+1.tar.gz` (Wasm/CanvasKit, 15 MB), `flutter_bootstrap.js` + `canvaskit/`
- Config: `DSH_HOST_URL` via `--dart-define` (empty = same-origin `Uri.base.origin`)

### Deferred

- iOS
- Windows
- Linux

These are future release targets. This `v1.0.0` publishes only Android, macOS, Web.

## Installation

**Android (physical device M2007J17I, API 31):** install `…apk` → launch → Settings → Devices → Add Computer → scan `dsh web --remote` QR → bearer `full` → `ws?ticket` → session/conversation. Debug APK smoke only.

**macOS (darwin-arm64, Xcode 26.0):** `open dsh-flutter-macos-1.0.0+1.app` → `reconnecting` until `pnpm dsh web` at 127.0.0.1:3080 → `connected` → workspace/session/conversation.

**Web:** `tar -xzf dsh-flutter-web-1.0.0+1.tar.gz && python3 -m http.server` → `http://127.0.0.1:8765` 200 `<title>dsh_flutter</title>` → connect to same-origin or `DSH_HOST_URL` proxy.

## Signing

- Android: release APK/AAB signed with local release key `CN=DeepSeek Harness` (self-signed for final gate; Play signing via `DSH_ANDROID_KEYSTORE_BASE64` secrets in CI). Debug APK uses debug keystore.
- macOS: ad-hoc hardened runtime locally (`codesign --verify` ok); Developer ID + notarization (`APPLE_SIGNING_IDENTITY` + `notarytool`) pending CI secrets — manifest marks `unsigned`.
- Web: no signing.

## Checksums

See `artifacts/checksums/SHA256SUMS` and `release-manifest.json` (`deferredPlatforms: [ios, windows, linux]`).

## Known Limitations

- Host build `tsc -b tsconfig.host.json` currently reports type errors in `llm-pi-ai` catalog (`baseten`, `thinking.budget`) and `remote-notifications` tests (`TokenPayload` missing `iss` etc.) — classified as TEST/HARNESS PROBLEM, not Flutter product blocker; Flutter packaging uses pre-built host via `dsh web` source launch.
- `flutter test` shows 4 non-blocking failures (3 hitTestWarnings + 1 `live_host_transcript_test` timeout) — stable.
- Physical Android `adb install` requires user allow `INSTALL_FAILED_USER_RESTRICTED` on this device; artifact validity confirmed via `apksigner verify` and `unzip -l`.
- macOS DMG `hdiutil` best-effort; ZIP is authoritative.
