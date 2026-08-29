# Update Architecture

## Abstract model

Releases publish two artifacts that together form the update contract:

1. `artifacts/release-manifest.json` — authoritative release description (version, date, pinned revisions, toolchain, artifacts with SHA256/size, signing status, update metadata)
2. `artifacts/checksums/SHA256SUMS` — line-oriented `sha256  relative/path` for every published artifact (plus per-file `*.sha256` sidecars)

Clients poll `update.manifestUrl` (see `release.yaml:update.manifestUrl`) for the manifest of their channel (`stable` / `beta` / `nightly` / `dev`). The manifest URL is the seam; the updater implementation (if any) is a consumer of it.

## Desktop

- **Manifest fields for updaters:**
  ```json
  {
    "version": "1.0.0",
    "fullVersion": "1.0.0+1",
    "channel": "stable",
    "releaseDate": "2026-08-29T12:00:00.000Z",
    "minimumVersion": null,
    "artifacts": {
      "macos/dsh-flutter-macos-1.0.0+1.zip": { "file": "...", "sha256": "...", "size": 123, "platform": "macos", "signed": false },
      "web/dsh-flutter-web-1.0.0+1.tar.gz": { "file": "...", "sha256": "...", "size": 123, "platform": "web", "signed": false }
    },
    "signing": { "status": "unsigned", "macos": "unsigned", "windows": "unsigned" }
  }
  ```
- **Download URL pattern:** consumers derive the download URL from `update.manifestUrl` origin + `artifacts[].file`. The manifest itself is hosted at `manifestUrl`; artifacts are co-hosted under the same distribution prefix (e.g. `https://releases.deepseek.com/dsh-flutter/...`). CI uploads both to the same GitHub Release.

- **Update decision:**
  - `version` / `fullVersion` compared via semver
  - `minimumVersion` gates the earliest version that can auto-update to this release
  - `channel` must match the client's channel subscription
  - SHA256 must match `SHA256SUMS` before install

- **No risky auto-updater shipped:** At this stage the repository implements only the manifest contract and the optional seam. A future desktop updater (e.g. Sparkle for macOS, custom logic for Windows/Linux) would consume this contract without requiring a new manifest shape.

## Mobile

- **Store-managed:** Android (Play) and iOS (App Store / TestFlight) use store update mechanisms.
- **No APK/IPA self-update:** The build scripts do not implement a custom APK/IPA self-updater. `release-manifest.json` still lists mobile artifacts (`android/*.aab`, `ios/*.ipa`) for provenance and checksum verification, but clients do not pull them for self-install.
- **Future OTA (if needed):** Would be a separate capability seam (e.g. CodePush-style) with its own manifest; not conflated with the installer manifest.

## Optional update service seam

The release manifest is the contract; an optional update service would:

1. Poll `update.manifestUrl` at the client's channel
2. Compare `version` against the installed `CFBundleShortVersionString` / `versionName` / etc.
3. Check `signing.status === "signed"` when distributing via verified channels
4. Verify `SHA256SUMS` before download, then per-artifact SHA256 after download
5. Stage the new artifact (e.g. DMG/ZIP/AppImage) and prompt / install per OS conventions

No updater is implemented in this repository; the seam is documented and the manifest is the boundary.

## Example

See `artifacts/release-manifest.json` for a real release and `artifacts/checksums/SHA256SUMS` for the companion checksums file.

```sh
# Generate (CI and local)
bash scripts/checksum.sh generate
node scripts/release-manifest.mjs
node scripts/release-manifest.mjs --check   # validate against release.yaml
```
