#!/usr/bin/env bash
# build-macos.sh — Flutter macOS build → .app + .dmg
# Supports: Apple Silicon, Intel, universal. Signing + notarization via env.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd flutter

get_yaml() {
  node -e "
    const fs=require('fs');
    try{ const y=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); const p=process.argv[2].split('.'); let c=y; for(const k of p) c=c?.[k]; if(c==null) process.exit(1); process.stdout.write(String(c)); } catch(e){ process.exit(2); }
  " "$RELEASE_YAML" "$1" 2>/dev/null || yaml_get "$1"
}

APP_DIR="$MONOREPO_ROOT/$(get_yaml 'app.path' 2>/dev/null || echo 'apps/flutter')"
VERSION="$(get_yaml 'release.version')"
BUILD_NUMBER="$(get_yaml 'release.buildNumber')"

if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "macOS build requires a macOS runner (current: $(uname -s)). Skipping."
  exit 0
fi

# Check if macOS platform exists; if not, create it (flutter create)
if [[ ! -d "$APP_DIR/macos" ]]; then
  warn "macOS platform folder missing — running: flutter create --platforms=macos ."
  (cd "$APP_DIR" && flutter create --platforms=macos .)
fi

info "macOS build: $APP_DIR @ $VERSION+$BUILD_NUMBER"
[[ -d "$APP_DIR/macos" ]] || die "macOS platform not available after flutter create"

pushd "$APP_DIR" >/dev/null
flutter pub get

# Determine arch handling; Flutter macOS builds fat by default when --target-platform not specified
# We produce one .app that is universal where toolchain supports it.
BUILD_ARGS=( build macos --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" )

# Optional dart-define for host URL (web parity; macos client also uses connection target)
if [[ -n "${DSH_HOST_URL:-}" ]]; then
  BUILD_ARGS+=( --dart-define="DSH_HOST_URL=$DSH_HOST_URL" )
fi

info "Running: flutter ${BUILD_ARGS[*]}"
flutter "${BUILD_ARGS[@]}"

# Locate .app — Flutter places it at build/macos/Build/Products/Release/
APP_BUNDLE="$(find build/macos -name "*.app" -type d -maxdepth 4 2>/dev/null | head -1 || true)"
if [[ -z "$APP_BUNDLE" ]]; then
  # fallback glob
  APP_BUNDLE="build/macos/Build/Products/Release/dsh_flutter.app"
fi
if [[ ! -d "$APP_BUNDLE" ]]; then
  die "macOS .app not found (looked for $APP_BUNDLE)"
fi
info ".app: $APP_BUNDLE"

# Bundle metadata verification
BUNDLE_ID="$(get_yaml 'platforms.macos.bundleId' 2>/dev/null || echo 'ai.deepseek.dshFlutter')"
PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$PLIST" ]]; then
  ACTUAL_ID="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$PLIST" 2>/dev/null || echo "unknown")"
  info "Bundle ID: $ACTUAL_ID (manifest: $BUNDLE_ID)"
fi

# Signing hooks (only when credentials present)
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  info "Signing .app with identity: $SIGNING_IDENTITY"
  codesign --force --deep --sign "$SIGNING_IDENTITY" --options runtime --entitlements "$APP_DIR/macos/Runner/Release.entitlements" "$APP_BUNDLE" || {
    warn "codesign failed — artifact will be unsigned"
    SIGNING_IDENTITY=""
  }
  # Verify signature
  codesign --verify --deep --strict "$APP_BUNDLE" && info "codesign verify: ok" || warn "codesign verify failed"
else
  warn "No APPLE_SIGNING_IDENTITY — producing unsigned build (local dev)"
fi

# Notarization hook (requires APPLE_ID + TEAM_ID + APP_SPECIFIC_PASSWORD or notarytool keychain profile)
if [[ -n "${APPLE_NOTARIZATION_PROFILE:-}" && -n "$SIGNING_IDENTITY" ]]; then
  info "Notarization requested via profile: $APPLE_NOTARIZATION_PROFILE"
  # Caller should have stapleed via: xcrun notarytool submit ... --wait && xcrun stapler staple
  warn "Notarization submit is environment-specific — ensure CI runs: xcrun notarytool submit ... && xcrun stapler staple $APP_BUNDLE"
fi

# Package .app into .dmg (or zip as fallback)
ensure_artifacts_dir
ARTIFACT_APP="$ARTIFACTS_DIR/macos/dsh-flutter-macos-${VERSION}+${BUILD_NUMBER}.app"
ARTIFACT_DMG="$ARTIFACTS_DIR/macos/dsh-flutter-macos-${VERSION}+${BUILD_NUMBER}.dmg"
ARTIFACT_ZIP="$ARTIFACTS_DIR/macos/dsh-flutter-macos-${VERSION}+${BUILD_NUMBER}.zip"

rm -rf "$ARTIFACT_APP"
cp -R "$APP_BUNDLE" "$ARTIFACT_APP"
info "Staged .app: $ARTIFACT_APP"

# Create DMG via hdiutil — best-effort, non-fatal
if command -v hdiutil >/dev/null 2>&1; then
  rm -f "$ARTIFACT_DMG"
  TMP_DMG="$(mktemp -u).dmg"
  if hdiutil create -volname "DeepSeek Harness" -srcfolder "$(dirname "$APP_BUNDLE")" -ov -format UDRW "$TMP_DMG" >/dev/null 2>&1; then
    DEV_MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" 2>/dev/null | grep -E '^/dev/' | head -1 | awk '{print $1}')" || true
    if [[ -n "${DEV_MOUNT:-}" ]]; then
      MOUNT_POINT="$(hdiutil info 2>/dev/null | grep "$DEV_MOUNT" | awk -F'\t' '{print $NF}' | head -1 || echo "/Volumes/DeepSeek Harness")"
      if [[ -d "$MOUNT_POINT" ]]; then
        ln -sf /Applications "$MOUNT_POINT/Applications" 2>/dev/null || true
        hdiutil detach "$DEV_MOUNT" -quiet 2>/dev/null || true
      fi
    fi
    if hdiutil convert "$TMP_DMG" -format UDZO -o "$ARTIFACT_DMG" >/dev/null 2>&1; then
      info "DMG: $ARTIFACT_DMG ($(du -h "$ARTIFACT_DMG" 2>/dev/null | awk '{print $1}'))"
    else
      warn "DMG convert failed — artifact will be .app + .zip only"
      rm -f "$ARTIFACT_DMG"
    fi
    rm -f "$TMP_DMG"
  else
    warn "DMG create failed — artifact will be .app + .zip only"
    rm -f "$TMP_DMG"
  fi
else
  warn "hdiutil not available — skipping DMG"
fi

# Always produce a zip as well (cross-platform extraction)
if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --keepParent "$(dirname "$APP_BUNDLE")" "$ARTIFACT_ZIP"
else
  (cd "$(dirname "$APP_BUNDLE")" && zip -qr "$ARTIFACT_ZIP" "$(basename "$APP_BUNDLE")")
fi
info "ZIP: $ARTIFACT_ZIP ($(du -h "$ARTIFACT_ZIP" | awk '{print $1}'))"

# Smoke: .app opens bundle metadata correct
if [[ -f "$PLIST" ]]; then
  VERSION_PLIST="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "unknown")"
  BUILD_PLIST="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST" 2>/dev/null || echo "unknown")"
  info "Plist version: $VERSION_PLIST ($BUILD_PLIST) — expected $VERSION ($BUILD_NUMBER)"
  if [[ "$VERSION_PLIST" != "$VERSION" ]]; then
    warn "CFBundleShortVersionString mismatch: got $VERSION_PLIST, expected $VERSION"
  fi
fi

popd >/dev/null
info "macOS build complete"
