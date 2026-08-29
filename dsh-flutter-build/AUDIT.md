# Audit — Flutter App + Harness + Build Reference

Date: 2026-08-29
Scope: Pre-build audit per spec §1

## A. Flutter Application Repository (`apps/flutter`)

- **pubspec.yaml**: `dsh_flutter` `1.0.0+1`, SDK `^3.13.0`, `uses-material-design: true`
  Dependencies: `flutter_riverpod 2.6.1`, `go_router 14.8.0`, `http`, `web_socket_channel`, `file_picker`, `image_picker`, `window_manager 0.4.0`, `shared_preferences`, `markdown`, `flutter_markdown`, `url_launcher`, `desktop_drop`, `flutter_secure_storage`, `mobile_scanner`, `connectivity_plus` (see `pubspec.lock` 1300+ lines, Flutter `>=3.44.0`, Dart `>=3.13.0 <4.0.0`)
- **pubspec.lock**: Pinned; `flutter pub get` drift checked by `bootstrap.sh`
- **Platform folders**:
  - `android/` — exists, `build.gradle.kts` (`namespace com.example.dsh_flutter`, `applicationId com.example.dsh_flutter`, `minSdk flutter.minSdkVersion`, `compileSdk flutter.compileSdkVersion`, JDK 17, `signingConfig debug` for release)
  - `ios/` — exists, `Runner/Info.plist` (`CFBundleIdentifier $(PRODUCT_BUNDLE_IDENTIFIER)`, `NSCameraUsageDescription` for QR pairing, `CFBundleShortVersionString $(FLUTTER_BUILD_NAME)`), `Runner.xcodeproj` (`PRODUCT_BUNDLE_IDENTIFIER com.example.dshFlutter` placeholder, `PRODUCT_NAME dsh_flutter`)
  - `macos/` — exists, `Runner/Configs/AppInfo.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER ai.deepseek.dshFlutter`, `PRODUCT_NAME dsh_flutter`, `PRODUCT_COPYRIGHT`), `Runner/Info.plist` (`CFBundleIdentifier $(PRODUCT_BUNDLE_IDENTIFIER)`), entitlements `DebugProfile.entitlements` / `Release.entitlements` (sandbox + network client/server + JIT), `Podfile` present
  - `windows/` — **missing** before audit → created via `flutter create --platforms=windows` (now `windows/CMakeLists.txt`, `windows/runner/*`, `windows/flutter/CMakeLists.txt`)
  - `linux/` — **missing** before audit → created via `flutter create --platforms=linux` (now `linux/CMakeLists.txt`, `linux/runner/*`)
  - `web/` — exists, `web/index.html`, `web/manifest.json`, `web/icons/Icon-192.png` etc., `web/favicon.png`
- **analysis_options.yaml**: `include: package:flutter_lints/flutter.yaml`, `custom_lint`, excludes `build/** android/** ios/** web/** windows/** macos/** linux/**`
- **.metadata**: `revision 4cf24164269a... channel stable`, `project_type: app`, platforms `root, android, ios` (now updated to include windows/linux after `flutter create`)
- **Icons**: `web/icons/Icon-*.png`, `macos/Runner/Assets.xcassets/AppIcon.appiconset`, `ios/Runner/Assets.xcassets/AppIcon.appiconset`, `android/app/src/main/res/mipmap-*`
- **Signing**: No committed certificates/keystore; `android/key.properties` absent, `ios` signing via Automatic/Manual with `CODE_SIGN_IDENTITY "-"`, pending CI secrets
- **Env**: `DSH_HOST_URL` via `String.fromEnvironment('DSH_HOST_URL')` in `connection_controller.dart`; `LocalTarget 127.0.0.1:3080` default, remote via `remote.pair` QR
- **Scripts**: `flutter pub get` / `flutter analyze` / `flutter test` / `flutter build <platform> --release --build-name --build-number --dart-define`
- **Tests**: `flutter test` (927+ pass, 4 known warnings/timeouts on integration), `flutter analyze` 409 issues (infos/warnings, exit 0)
- **App IDs**: `android com.example.dsh_flutter` (placeholder), `ios com.example.dshFlutter`, `macos ai.deepseek.dshFlutter` (production)
- **Host connection**: Client-only — expects external `dsh web` at `127.0.0.1:3080` or remote host via ticketed WebSocket (no bundled Node/pnpm/dsh runtime)
- **Build commands**: `flutter build web --wasm`, `flutter build macos`, `flutter build apk/appbundle`, `flutter build ios --no-codesign` / `build ipa`
- **Desktop runtime**: No `window_manager` bundling of host process; presentation shell only

## B. Harness Repository Dependency

- **Revision**: `1c17813e1dc475e47217e006e754eda07b4f9241` (HEAD at audit), clean working tree check via `bootstrap.sh`
- **Package manager**: `pnpm 11.7.0` (`packageManager` field), `pnpm-lock.yaml` present, `pnpm install --frozen-lockfile` gated in `--strict`
- **Node**: `^22.19.0 || >=24.0.0`, actual `22.23.2`
- **Build**: `pnpm run build` (`tsx scripts/build.ts` → `tsc -b` + `tsdown`), `pnpm run build:lib:host|client`
- **dsh web launch**: `pnpm dsh --profile headless "task"` or `dsh web` via `node --import tsx/esm apps/cli/src/bin.ts`; Flutter connects via `ConnectionClient` WS RPC to `dsh web --remote` endpoint
- **Desktop bundling**: Not required / not currently supported — packaging docs state external host requirement; bundling would need explicit Node+Harness artifact spec

## C. Reference `dsh-desktop` Architecture (used as separation pattern only)

- Externalized build/release tooling, pinned upstream revisions, reproducible packaging, artifact generation, desktop distribution, release automation — adopted as `release.yaml` + `bootstrap.sh` + per-platform `build-*.sh` + `checksum.sh` + `release-manifest.mjs` + CI matrix. No Electron fork copied into Flutter.

## Decision: Desktop Host Strategy

**A — remote/local client only.** Determined from `connection_target.dart` + `connection_controller.dart` + `SecureTokenStore` + `add_computer_screen.dart` (`dsh web --remote` QR). No local host lifecycle to bundle. If bundled-host variant is later required, it must be specified as reproducible Node+Harness artifacts with supervision, not a silent global dependency.
