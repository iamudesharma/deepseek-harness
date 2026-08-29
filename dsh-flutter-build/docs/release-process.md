# Release Process

This document owns the release workflow for `dsh-flutter-build`.

## Prerequisites

- `release.yaml` is green (`node scripts/validate-manifest.mjs`)
- `bash scripts/bootstrap.sh --strict` passes (toolchain + lockfiles clean)
- `bash scripts/version.sh check` passes (propagation consistent)
- Platform builds pass on their native runners (`bash scripts/verify.sh`)

## Steps

1. **Update `release.yaml`**
   - Bump `release.version` / `release.buildNumber` / `release.prerelease` as needed.
   - Keep `app.version` / `app.buildNumber` in sync with `release.*`.
   - Update `toolchain.*` if Flutter / Dart / Node / pnpm are intentionally upgraded.

2. **Pin revisions**
   ```sh
   # Set app.revision / harness.revision to the exact SHAs you intend to ship
   # (full 40-char). Use the current monorepo HEAD when shipping from monorepo:
   git rev-parse HEAD   # paste into release.yaml
   ```

3. **Pin toolchain**
   - Record the exact `flutter --version`, `dart --version`, `node --version`, `pnpm --version` that produced the candidate.
   - Update `toolchain.flutter.revision` when applicable.

4. **Run verification**
   ```sh
   bash scripts/verify.sh
   # or stepwise:
   node scripts/validate-manifest.mjs
   bash scripts/bootstrap.sh --strict
   bash scripts/version.sh check
   ```

5. **Build all platforms**
   ```sh
   bash scripts/build.sh all
   # Per-platform on native runners:
   #   bash scripts/build-web.sh
   #   bash scripts/build-macos.sh   # macOS runner
   #   bash scripts/build-ios.sh     # macOS runner
   #   bash scripts/build-android.sh # needs JDK 17
   #   bash scripts/build-windows.sh # Windows runner
   #   bash scripts/build-linux.sh   # Linux runner with GTK deps
   ```

6. **Package** — handled inside each `build-*.sh` (`.app` + `.dmg` + `.zip` for macOS, etc.).

7. **Sign** — CI injects credentials via env (never committed):
   - macOS/iOS: `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`
   - Android: `DSH_ANDROID_KEYSTORE_BASE64` …

8. **Notarize (macOS)** — wired as a hook in `build-macos.sh`:
   ```sh
   xcrun notarytool submit artifacts/macos/*.dmg --keychain-profile "$APPLE_NOTARIZATION_PROFILE" --wait
   xcrun stapler staple artifacts/macos/*.dmg
   ```

9. **Checksums**
   ```sh
   bash scripts/checksum.sh generate
   bash scripts/checksum.sh verify
   ```

10. **Release manifest**
    ```sh
    node scripts/release-manifest.mjs
    node scripts/release-manifest.mjs --check
    ```

11. **Validate all artifacts**
    ```sh
    bash scripts/verify.sh   # re-runs checksums + manifest checks
    ```

12. **Create GitHub Release**
    - Push a tag `v<version>` (or `v<version>-<prerelease>`) to trigger `.github/workflows/release.yml`, or
    - Run `release.yml` via `workflow_dispatch`.
    - CI uploads `artifacts/**/*`, `SHA256SUMS`, and `release-manifest.json`.

13. **Publish release notes** — `artifacts/RELEASE_NOTES.md` is seeded by `scripts/release.sh`; CI uses `generate_release_notes: true`.

14. **Store release metadata** — commit the tag + `release.yaml` + `release-manifest.json` (the manifest artifact is also attached to the GitHub Release).

## Channels

`release.channel` selects the update channel:

- `nightly` / `dev` — frequent, may be unsigned
- `beta` — pre-release (`prerelease` like `rc.1`), signed when secrets allow
- `stable` — production (no `prerelease`)

The `update.manifestUrl` in `release.yaml` is where clients poll for the latest `release-manifest.json` of their channel.

## Reproducibility

A release is reproducible from `release.yaml` alone: same `app.revision` + `harness.revision` + `toolchain.*` produces byte-identical outputs except for inherently non-deterministic fields (signing timestamps, archive mtimes). `scripts/release-manifest.mjs` records those inputs so audits can assert they are identical across two builds of the same manifest.

## Failure policy

If any platform fails its build/packaging/signing/launch check, it is **not** marked complete:

- `BUILD VERIFIED` — `flutter build` succeeded and output exists
- `PACKAGE VERIFIED` — artifact is structurally valid (zip/tar test, `codesign --verify`, `aapt2 dump`, etc.)
- `SIGNING VERIFIED` — signature present and valid (when credentials were available)
- `PHYSICAL DEVICE VERIFIED` — manual launch on device (not gated in CI)

Report each state separately (see spec §37).
