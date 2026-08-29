# Architecture

## Separation of concerns

This build repository is the distribution seam for the Flutter client. It does not own product code.

```
deepseek-harness/            # app/runtime repo (source of truth for product)
  apps/flutter/              # Dart, plugins, conversation/mobile/desktop/Web UI
  packages/*/*               # Harness runtime (session, mux, RPC, plugins)
  pnpm-lock.yaml, etc.

dsh-flutter-build/           # distribution repo (source of truth for releases)
  release.yaml               # authoritative manifest (pinned revisions + toolchain)
  VERSION                    # semver (mirrors release.version)
  scripts/                   # deterministic bootstrap / build / verify / release
  .github/workflows/         # CI matrix + release automation
  artifacts/                 # generated, gitignored (web/macos/windows/linux/android/ios + checksums + manifest)
  docs/                      # release-process, platforms, signing
```

When consumed inside the monorepo (current layout), `scripts/bootstrap.sh` resolves `app.path` relative to the parent of `dsh-flutter-build/`. When consumed standalone (external clone), `bootstrap.sh --fetch` clones the pinned `app.repository` / `harness.repository` revisions into `.sources/app/` + `.sources/harness`.

## Build manifest

`release.yaml` (`formatVersion: 1`) pins:

- `app` + `harness`: `repository` + `revision` (full SHA) + `path`
- `release`: `version` (semver) + `buildNumber` + `channel` + optional `prerelease`
- `toolchain`: Flutter channel/version + Dart/Node/pnpm versions (+ Node range)
- `platforms.*`: per-platform enablement and metadata (bundleId, applicationId, arch, deployment targets, signing expectations)
- `branding.icons`: centralized icon sources
- `artifacts`: output dir + archive format
- `update`: manifest URL + minimum version

No floating `main` branches. A release is reproducible from `release.yaml` alone.

## Verification pipeline

```
validate-manifest.mjs
→ bootstrap.sh        (toolchain + lockfile + revision checks, --strict for CI)
→ version.sh check    (pubspec.yaml + VERSION propagation)
→ flutter analyze
→ dart format --set-exit-if-changed
→ flutter test
→ verify-flutter-tracker (if present)
→ secret scan + .gitignore guard
→ checksum verify + release-manifest --check
→ platform-support guard (windows/linux folder presence)
```

Shared logic lives in `scripts/common.sh` + `scripts/verify.sh`; per-platform builds do not duplicate it.

## Build dispatch

```
build.sh <platform|all|verify>
  → build-web.sh       (flutter build web --wasm + tar.gz + unpacked smoke)
  → build-macos.sh     (flutter build macos → .app + DMG + zip, codesign hook)
  → build-ios.sh       (--no-codesign locally, ipa when signed)
  → build-android.sh   (debug apk + release apk + aab, keystore hook)
  → build-windows.sh   (portable zip + WINDOWS_INSTALLER hook, skip gracefully off-Windows)
  → build-linux.sh     (bundle tar.gz + LINUX_APPIMAGE_HOOK / LINUX_DEB_HOOK)
  → checksum.sh generate
  → release-manifest.mjs
```

Each per-platform script is idempotent and can be re-run. Platform detection is explicit: Windows-only scripts no-op with a diagnostic on macOS/Linux rather than silently claiming support.

## Version propagation

`release.yaml:release.version` is authoritative. `scripts/version.sh`:

- `sync` → patches `apps/flutter/pubspec.yaml:version` to `release.version+release.buildNumber` and `VERSION` to `release.version`
- `bump <ver>` → updates `release.yaml:release.version` + `app.version` + `VERSION`
- `check` → asserts pubspec + VERSION match the manifest (fails the release if drifted)

Flutter's `--build-name` / `--build-number` then propagate to native metadata (`CFBundleShortVersionString`/`CFBundleVersion`/`versionName`/`versionCode`) without code-level patching.

## Artifact layout

```
artifacts/
  web/         dsh-flutter-web-<ver>+<build>.tar.gz + unpacked build/
  macos/       .app + .dmg + .zip
  windows/     portable zip (+ installer via hook)
  linux/       bundle tar.gz (+ AppImage/.deb via hooks)
  android/     -debug.apk + .apk + .aab
  ios/         .xcarchive.zip + .ipa (when signed)
  checksums/   SHA256SUMS + per-file .sha256
  release-manifest.json
  RELEASE_NOTES.md   # seeded by release.sh
```

No artifact is committed; all are published via GitHub Releases.

## Update architecture

- Desktop: clients poll `update.manifestUrl` (see `release.yaml:update.manifestUrl`) for `release-manifest.json` containing `version`, `channel`, `minimumVersion`, `artifacts[].file` + `sha256` + `downloadUrl` pattern. No custom auto-updater is shipped — the manifest is the contract; a future updater (e.g. Sparkle/electron-updater analogue for Flutter) would consume it.
- Mobile: store-managed; no APK/IPA self-update mechanism.

The manifest + checksums are the only required surface today; the update service seam is documented but not implemented as a risky updater.

## Desktop host strategy

`connection_target.dart` shows the app is a client that connects to an external `dsh web` host (local `127.0.0.1:3080` or remote via `remote.pair` QR). Installers do **not** bundle Node or the Harness runtime. Docs state the external host requirement explicitly; a future bundled-host variant would need an explicit runtime artifact spec and process supervision, not an implicit global dependency.

## Icons / branding

Centralized under `branding.icons` in `release.yaml`, sourced from the app repo's asset locations. No platform gets a divergent identity; all re-use the existing product icons (web `icons/`, macOS/iOS `Assets.xcassets`, Android `mipmap-*`).

## CI

- `ci.yml` (PR): manifest validation + bootstrap + analyze + test + per-native-runner builds (macos-14, windows-2022, ubuntu-22.04, etc.) + artifact verification (checksums/manifest).
- `release.yml` (tag `v*` / `workflow_dispatch`): strict bootstrap + version check + matrix builds on native runners + checksums + manifest + `softprops/action-gh-release` publish.

Windows jobs run under native `pwsh`-compatible `bash` on `windows-2022`; the pull-request `windows` under Wine path is not conflated with the build repo's native `windows-2022` build.

## Failure semantics (§37)

Platforms report separate states rather than a single green:

- `BUILD VERIFIED` — `flutter build` succeeded + output exists
- `PACKAGE VERIFIED` — archive is structurally valid (`unzip -tq`, `tar tzf`, `codesign --verify`, `aapt2 dump`, etc.)
- `SIGNING VERIFIED` — signature valid when credentials present
- `PHYSICAL DEVICE VERIFIED` — manual device launch (out of band for CI)

Only `BUILD VERIFIED` + `PACKAGE VERIFIED` gate the release; `SIGNING VERIFIED` gates store / notarized channels.

## Reproducibility

Two builds of the same `release.yaml` (same pinned app/harness revs + toolchain) produce identical `release-manifest.json` inputs. Byte-for-byte artifact equality is verified where platform signing/timestamps allow; otherwise the manifest documents the non-deterministic fields (signing timestamp, archive mtime) and `checksum.sh verify` asserts all source/build inputs remain identical.
