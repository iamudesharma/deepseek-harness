# Signing

Signing credentials **must** come from CI secrets. Never commit certificates, private keys, keystores, provisioning profiles, or passwords. The build scripts produce unsigned artifacts by default for local developer builds; production release manifests mark `signing.status` explicitly.

## macOS

**Required secrets (CI):**

- `APPLE_SIGNING_IDENTITY` — e.g. `Developer ID Application: Your Team (TEAMID)`
- `APPLE_TEAM_ID` — for notarization / export
- `APPLE_ID` — Apple ID for notarization (when using Apple ID auth)
- `APPLE_NOTARIZATION_PROFILE` — `notarytool` keychain profile name (preferred over Apple ID password), or `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` + `APPLE_TEAM_ID`

**Local (unsigned):**

```sh
bash scripts/build-macos.sh   # no env needed — produces unsigned .app + .dmg + .zip
codesign --verify --deep --strict artifacts/macos/*.app || echo "unsigned (expected locally)"
```

**CI (signed):**

```sh
APPLE_SIGNING_IDENTITY="Developer ID Application: ..." \
APPLE_TEAM_ID="TEAMID" \
bash scripts/build-macos.sh
codesign --verify --deep --strict artifacts/macos/*.app
```

**Notarization (CI):**

```sh
# After signing, submit the DMG (or ZIP) to notarytool and staple
xcrun notarytool submit artifacts/macos/*.dmg --keychain-profile "$APPLE_NOTARIZATION_PROFILE" --wait
xcrun stapler staple artifacts/macos/*.dmg
# Or: xcrun notarytool store-credentials ... && xcrun notarytool submit ... --keychain-profile ...
```

The `build-macos.sh` script documents the expected `notarytool` invocation; it does not hardcode Apple endpoints.

**Artifacts:**

- Unsigned build → `.app` + `.zip` usable for local testing
- Signed build → `.app` signed with hardened runtime + entitlements
- Notarized release → signed + notarized DMG/zipped app

All three are distinct states; local builds must not require signing.

## iOS

**Required secrets (CI) for signed archive / IPA:**

- Apple distribution certificate (`.p12`) imported into the runner keychain
- Provisioning profile (`.mobileprovision`) installed via `PROVISIONING_PROFILE_SPECIFIER`
- `APPLE_TEAM_ID`, `APPLE_SIGNING_IDENTITY`

Import steps (CI `macos-14` runner):

```sh
security create-keychain -p "" build.keychain
security import certificate.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" build.keychain
```

`scripts/build-ios.sh` detects signing availability: when `APPLE_TEAM_ID`/`APPLE_SIGNING_IDENTITY` are absent it builds `--no-codesign` and emits an `.xcarchive.zip` (no `.ipa`). When present it runs `flutter build ipa --export-method <platforms.ios.exportMethod>`.

Never commit `.p12`, `.mobileprovision`, or passwords. The release manifest records `signing.ios: signed|unsigned`.

## Android

**Required secrets (CI) for Play-signed release:**

- `DSH_ANDROID_KEYSTORE_BASE64` — base64 of the release `.jks` / `.keystore`
- `DSH_ANDROID_KEYSTORE_PASSWORD`
- `DSH_ANDROID_KEY_ALIAS`
- `DSH_ANDROID_KEY_PASSWORD`

The script materializes:

```
android/app/release.keystore
android/key.properties   # gitignored
```

Ensure `android/app/build.gradle.kts` loads `key.properties` when present:

```kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
  keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
android {
  signingConfigs {
    create("release") {
      if (keystorePropertiesFile.exists()) {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
      }
    }
  }
  buildTypes {
    getByName("release") {
      signingConfig = signingConfigs.getByName("release")
    }
  }
}
```

**Local (debug-signed):** no env needed — `build-android.sh` produces a debug APK + release APK signed with the debug keystore (suitable for PR smoke).

The release manifest records `signing.android: signed|unsigned`.

## Windows

**Optional (when available):**

- `WINDOWS_SIGN_PFX_BASE64` — base64 of Authenticode `.pfx`
- `WINDOWS_SIGN_PASSWORD`

Wire via `signtool`:

```sh
echo "$WINDOWS_SIGN_PFX_BASE64" | base64 -d > cert.pfx
signtool sign /fd SHA256 /f cert.pfx /p "$WINDOWS_SIGN_PASSWORD" /tr http://timestamp.digicert.com /td SHA256 artifacts/windows/*.exe
```

If unavailable, the portable `.zip` is unsigned (expected). The release manifest records `signing.windows: signed|unsigned`.

## Manifest signing status

`artifacts/release-manifest.json` → `signing: { status, macos, ios, android, windows }`.

- Local builds: all `unsigned`
- CI with secrets: per-platform `signed` where verification succeeded

This makes signing explicit; consumers and QA can gate on it without guessing.

## Never commit

- `*.p12`, `*.mobileprovision`, `*.jks`, `*.keystore`, `*.pem`, `*.key`, `*.crt`, `*.p8`, `secrets/`, `.env` with tokens
- The `.gitignore` at the build repo root blocks these patterns
