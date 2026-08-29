# Platforms

## Matrix

| Platform | Runner | Output | Primary arch | Signing |
|----------|--------|--------|--------------|---------|
| Web | ubuntu-latest | `artifacts/web/dsh-flutter-web-*.tar.gz` + unpacked `build/` | — | — |
| macOS | macos-14 | `.app` + `.dmg` + `.zip` under `artifacts/macos/` | arm64 + x64 (universal when toolchain allows) | Developer ID via `APPLE_SIGNING_IDENTITY` |
| Windows | windows-2022 | portable `*.zip` (+ installer/MSIX hook via `WINDOWS_INSTALLER`) | x64 (ARM64 only if toolchain supports) | Authenticode via `WINDOWS_SIGN_PFX_BASE64` |
| Linux | ubuntu-22.04 | bundle `*.tar.gz` + optional `AppImage`/`.deb` via hooks | x64 | — |
| Android | ubuntu-latest + JDK 17 | `*.apk` (debug+release) + `*.aab` | — | keystore via `DSH_ANDROID_KEYSTORE_BASE64` |
| iOS | macos-14 | `.xcarchive.zip` + `.ipa` (when signed) | arm64 | certificates/profiles via Keychain |

Only enabled platforms (`platforms.<name>.enabled` in `release.yaml`) are built by `scripts/build.sh all`.

## Web

- Built via `flutter build web --wasm` with `--build-name` / `--build-number` from the manifest.
- `DSH_HOST_URL` injected via `--dart-define=DSH_HOST_URL=<url>`; when empty the app uses `Uri.base.origin` (same-host) or the in-app Connection settings.
- Production guard: `platforms.web.requireNonLocalHost: true` makes the build fail if `DSH_HOST_URL` is localhost.
- Output: `artifacts/web/` holds the compressed archive and an unpacked `build/` for smoke tests (`index.html` serves).

## macOS

- Uses the existing `macos/` platform (Flutter `macos_assemble.sh`). If `macos/` is absent, the script runs `flutter create --platforms=macos .` (portable metadata, native compile still requires macOS).
- Bundle ID from `platforms.macos.bundleId` (`ai.deepseek.dshFlutter`), display name, entitlements, hardened runtime.
- Local builds are unsigned (`CODE_SIGN_IDENTITY = "-"`); CI signs when `APPLE_SIGNING_IDENTITY` is set and verifies via `codesign --verify`.
- Notarization is a CI hook (`APPLE_NOTARIZATION_PROFILE` → `notarytool submit` + `stapler staple`). The script documents the required command so it is reproducible without hardcoding Apple endpoints.
- Packaging: `hdiutil` DMG (with `/Applications` symlink) + `ditto`/`zip` for a portable `.zip`.

## Windows

- Requires Windows runner with Visual Studio. On non-Windows runners the script creates the `windows/` metadata via `flutter create --platforms=windows` and then skips the native compile with a clear diagnostic (no silent mis-attribution of support).
- Portable zip is always produced. Installer (Inno Setup/WiX/MSIX) is an explicit hook: set `WINDOWS_INSTALLER` to a shell command that builds the installer from `build/windows/x64/runner/Release/`.
- Authenticode signing via `WINDOWS_SIGN_PFX_BASE64` + `WINDOWS_SIGN_PASSWORD` is documented but not required for local dev.

## Linux

- Requires `clang cmake ninja-build pkg-config libgtk-3-dev`. Missing deps are warned, not hidden.
- Bundle tarball is always produced. `AppImage` and `.deb` are opt-in hooks:
  - `LINUX_APPIMAGE_HOOK` or presence of `appimagetool`
  - `LINUX_DEB_HOOK` or `dpkg-deb` on Linux
  - Each builds a minimal but valid package (desktop entry + icon from `web/icons/Icon-512.png`).
- The script does not claim Linux support unless `flutter build linux` succeeds and the bundle launches structurally (executable exists).

## Android

- Debug APK is always built (CI smoke). Release APK + AAB are built with `flutter build apk/appbundle --release`.
- `applicationId` from `platforms.android.applicationId` (lowercased) patches the placeholder `com.example.*` when needed.
- Signing: when `DSH_ANDROID_KEYSTORE_BASE64` is present the script materializes `android/app/release.keystore` + `android/key.properties` (CI secrets, never committed). Otherwise debug signing is used (allowed for PR/nightly).
- Permissions verified: `CAMERA`, `READ_MEDIA_*` etc. Smoke lists `aapt2 dump permissions` when available.

## iOS

- Requires macOS runner. Missing `ios/` is materialized via `flutter create --platforms=ios`.
- `PRODUCT_BUNDLE_IDENTIFIER` placeholder `com.example.*` is patched to `platforms.ios.bundleId` when production.
- Unsigned `flutter build ios --no-codesign` is allowed locally; signed `flutter build ipa` runs when `APPLE_TEAM_ID` / `APPLE_SIGNING_IDENTITY` are present. `exportMethod` comes from `platforms.ios.exportMethod`.
- Smoke checks `Info.plist` inside the `.xcarchive` for `CFBundleShortVersionString` / `CFBundleVersion`.

## Desktop host strategy

The Flutter app is a **client-only** presentation shell. It connects to an external host at `127.0.0.1:3080` by default or to a remote host via `remote.pair` / `remote.ws-ticket` (see `apps/flutter/lib/src/core/connection/connection_target.dart`). The desktop installers **do not** bundle the `dsh web` host or Node runtime. Documentation and installer metadata state the requirement to run `dsh web` (or `npx @deepseek-ai/dsh web`) externally — no silent host-process architecture is introduced in this build work.

If a future product decision requires bundling the Harness runtime (Node + `dsh` packages), the required artifacts and launch supervision must be specified explicitly and packaged reproducibly — not by relying on the user's global `node` / `pnpm` / `dsh`.

## Icons / branding

Centralized via `branding.icons` in `release.yaml` (relative to the app repo root). Build scripts copy from:

- `apps/flutter/web/icons` → Web favicon set
- `apps/flutter/macos/Runner/Assets.xcassets` → macOS iconset
- `apps/flutter/ios/Runner/Assets.xcassets` → iOS icons
- `apps/flutter/android/app/src/main/res` → Android mipmap sets

Inconsistent platform identities are not introduced; all use the existing product branding.

## Platform-specific config

Release-specific settings are injected via `--dart-define` (never secrets):

- `DSH_HOST_URL`
- App name / version / build number via `--build-name` / `--build-number` (no need for code patching)

Secrets stay in the host/server or CI secret store and must not be passed via `--dart-define`.
