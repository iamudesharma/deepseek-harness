# dsh-flutter-build — Build, Packaging & Release Repository

English | Separate build repository for the DeepSeek Harness Flutter client (`apps/flutter` in the
harness monorepo). This repo is inspired by the `dsh-desktop` separation of application and
distribution responsibilities: the app repo owns product code, this repo owns reproducible releases.

## Repositories

| Repo | Owns |
|------|------|
| `deepseek-harness` (`apps/flutter`) | Dart code, plugins, conversation/mobile/desktop UI, automated product tests |
| `dsh-flutter-build` (this repo) | Release version, pinned revisions, toolchain, build orchestration, packaging, signing config, checksums, release manifest, CI/CD, update metadata |

Application code is **not** moved into this repo. When consumed standalone, this repo checks out
the pinned app revision into `.sources/app/` (see `scripts/bootstrap.sh --fetch`).

## Prerequisites

- Flutter `3.47.0` stable + Dart `3.13.0` (`flutter --version`)
- Node `22.23.2` (`^22.19.0 || >=24.0.0`) + pnpm `11.7.0`
- For macOS/iOS: Xcode 26+, CocoaPods
- For Android: JDK 17, Android SDK
- For Linux: `clang cmake ninja-build pkg-config libgtk-3-dev`
- For Windows: Visual Studio 2022 with Desktop C++ workload
- `js-yaml` for manifest tooling (`npm i -g js-yaml` or it is a transitive dep via Node)

## Bootstrap

```sh
# From the build repo root:
node scripts/validate-manifest.mjs    # manifest syntax / semver / SHA checks
bash scripts/bootstrap.sh             # verify toolchain + lockfiles vs release.yaml
bash scripts/bootstrap.sh --strict    # fail on any drift (CI mode)
bash scripts/bootstrap.sh --fetch     # standalone: clone pinned revisions into .sources/

bash scripts/version.sh check         # version propagation (release.yaml → pubspec.yaml + VERSION)
bash scripts/version.sh sync          # fix propagation drift
```

The manifest is authoritative; builds never use a floating `main` branch.

## Development builds

Each platform has an isolated script that reads `release.yaml` and the optional
`DSH_HOST_URL` env:

```sh
./scripts/build.sh web        # or bash scripts/build-web.sh
./scripts/build.sh macos
./scripts/build.sh windows
./scripts/build.sh linux
./scripts/build.sh android
./scripts/build.sh ios
./scripts/build.sh all        # all enabled platforms + checksums + release-manifest.json
./scripts/verify.sh           # analyzer + tests + checksums + manifest checks
```

Web respects `DSH_HOST_URL` via `--dart-define` (see `platforms.web` in `release.yaml`).
Production web builds can require a non-local host (`requireNonLocalHost: true`).

Local builds are unsigned — signing credentials come only from CI secrets (never committed).

## Release builds

```sh
bash scripts/release.sh              # full pipeline: verify → build all → checksums → manifest
bash scripts/release.sh --dry-run    # validate only
bash scripts/release.sh --skip-build # verify + checksums/manifest without rebuilding
```

CI mirrors this pipeline per platform runner (see `.github/workflows/ci.yml` + `release.yml`).

## Signing setup

| Platform | Secrets (CI env) | Local behavior |
|----------|------------------|----------------|
| macOS / iOS | `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_NOTARIZATION_PROFILE` | unsigned |
| Android | `DSH_ANDROID_KEYSTORE_BASE64`, `DSH_ANDROID_KEYSTORE_PASSWORD`, `DSH_ANDROID_KEY_ALIAS`, `DSH_ANDROID_KEY_PASSWORD` | debug keystore |
| Windows | `WINDOWS_SIGN_PFX_BASE64`, `WINDOWS_SIGN_PASSWORD` | unsigned |

Never commit keystores, certificates, or passwords. See `docs/signing.md`.

## Platform support

See `docs/platforms.md` for per-platform requirements and runner mapping.

## Artifacts

```
artifacts/
├── web/         # build/web + dsh-flutter-web-*.tar.gz
├── macos/       # .app + .dmg + .zip
├── windows/     # portable zip (+ installer hook)
├── linux/       # bundle tar.gz (+ AppImage/.deb hooks)
├── android/     # debug .apk + release .apk + .aab
├── ios/         # .xcarchive.zip + .ipa (when signed)
├── checksums/   # SHA256SUMS + per-file .sha256
└── release-manifest.json
```

Never commit generated artifacts (`artifacts/` is gitignored). Publish via GitHub Releases.

## Versioning

`release.yaml` → `release.version` + `release.buildNumber` is the single source.
Propagation:

- `VERSION` file = `release.version`
- `apps/flutter/pubspec.yaml` = `release.version+release.buildNumber` (Flutter's `versionName+versionCode`)
- iOS/macOS `CFBundleShortVersionString` / `CFBundleVersion` via `--build-name` / `--build-number`
- Android `versionName` / `versionCode` via same flags

```sh
bash scripts/version.sh get               # 1.0.0
bash scripts/version.sh get --full        # 1.0.0+1
bash scripts/version.sh sync              # fix drift
bash scripts/version.sh bump 1.1.0-rc.1  # bump manifest
```

## Checksums & release manifest

```sh
bash scripts/checksum.sh generate   # artifacts/checksums/SHA256SUMS + sidecars
bash scripts/checksum.sh verify
node scripts/release-manifest.mjs          # artifacts/release-manifest.json
node scripts/release-manifest.mjs --check
```

`release-manifest.json` records version, date, pinned revisions, toolchain, every artifact's SHA256/size/arch, and signing status — the contract for updaters and reproducibility audits.

## CI

- `ci.yml` — PR: manifest validation, bootstrap, analyze, tests, per-platform builds, checksums, manifest
- `release.yml` — tag push / dispatch: strict manifest check, matrix builds on native runners (macos-14 for macOS/iOS, windows-2022, ubuntu-22.04 for Linux), checksums, manifest, GitHub Release

Platform runners use the correct native host; web can run anywhere.

## Troubleshooting

- `release.yaml` validation fails → `node scripts/validate-manifest.mjs` prints diagnostics
- `flutter` / `pnpm` version mismatch → install the pinned version or use `--strict` only in CI
- `pubspec.lock` drift → `bash scripts/bootstrap.sh` will run `flutter pub get`; commit the updated lockfile
- `android` unsigned in release → set `DSH_ANDROID_KEYSTORE_BASE64` etc. in CI secrets
- `macos` DMG missing on Linux → DMG creation requires macOS + `hdiutil` (Linux runner intentionally skips it)

## Related

- App: `apps/flutter/README.md`
- Architecture: `../../docs/architecture.md` (when consumed inside the monorepo)
- Signing: `docs/signing.md` · Platforms: `docs/platforms.md` · Release process: `docs/release-process.md`
