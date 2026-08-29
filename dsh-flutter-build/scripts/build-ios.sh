#!/usr/bin/env bash
# build-ios.sh — Flutter iOS archive → IPA (when signing available)
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
BUNDLE_ID="$(get_yaml 'platforms.ios.bundleId' 2>/dev/null || echo 'ai.deepseek.dshFlutter')"

if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "iOS build requires a macOS runner (current: $(uname -s)). Skipping."
  exit 0
fi

if [[ ! -d "$APP_DIR/ios" ]]; then
  warn "iOS platform folder missing — running: flutter create --platforms=ios ."
  (cd "$APP_DIR" && flutter create --platforms=ios .)
fi

info "iOS build: $APP_DIR @ $VERSION+$BUILD_NUMBER (bundleId=$BUNDLE_ID)"
[[ -d "$APP_DIR/ios" ]] || die "iOS platform not available"

# Patch bundle identifier if placeholder (com.example.*) and manifest is production
if grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.example' "$APP_DIR/ios/Runner.xcodeproj/project.pbxproj" 2>/dev/null; then
  if [[ "$BUNDLE_ID" != "com.example"* ]]; then
    info "Patching iOS PRODUCT_BUNDLE_IDENTIFIER placeholder -> $BUNDLE_ID"
    # Only patch the main Runner target, not RunnerTests
    perl -pi -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.example\.dshFlutter;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/" "$APP_DIR/ios/Runner.xcodeproj/project.pbxproj"
  fi
fi

# Install pods if needed
if [[ -f "$APP_DIR/ios/Podfile" ]] && command -v pod >/dev/null 2>&1; then
  info "Running pod install..."
  (cd "$APP_DIR/ios" && pod install) || warn "pod install failed"
fi

pushd "$APP_DIR" >/dev/null
flutter pub get

ensure_artifacts_dir
mkdir -p "$ARTIFACTS_DIR/ios"

# Determine signing availability
HAS_SIGNING=0
if [[ -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  HAS_SIGNING=1
  info "Signing credentials present — will attempt signed archive"
else
  warn "No signing credentials — building unsigned archive (local dev)"
fi

if [[ "$HAS_SIGNING" -eq 1 ]]; then
  # Signed archive + IPA via flutter build ipa
  EXPORT_METHOD="$(get_yaml 'platforms.ios.exportMethod' 2>/dev/null || echo 'development')"
  BUILD_ARGS=( build ipa --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" --export-method="$EXPORT_METHOD" )
  if [[ -n "${DSH_HOST_URL:-}" ]]; then
    BUILD_ARGS+=( --dart-define="DSH_HOST_URL=$DSH_HOST_URL" )
  fi
  info "Running: flutter ${BUILD_ARGS[*]}"
  flutter "${BUILD_ARGS[@]}" || {
    error "flutter build ipa failed — falling back to unsigned iOS build"
    flutter build ios --release --no-codesign --build-name="$VERSION" --build-number="$BUILD_NUMBER" || warn "unsigned ios build also failed"
  }
  # Collect IPA if produced
  IPA_PATH="$(find build/ios -name "*.ipa" -type f 2>/dev/null | head -1 || true)"
  if [[ -n "$IPA_PATH" && -f "$IPA_PATH" ]]; then
    cp "$IPA_PATH" "$ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}.ipa"
    info "IPA: $ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}.ipa"
  else
    warn "IPA not found after flutter build ipa"
  fi
  # Also stash archive
  ARCHIVE_PATH="$(find build/ios -name "*.xcarchive" -type d 2>/dev/null | head -1 || true)"
  if [[ -n "$ARCHIVE_PATH" && -d "$ARCHIVE_PATH" ]]; then
    # Zip the xcarchive for artifact storage
    (cd "$(dirname "$ARCHIVE_PATH")" && zip -qr "$ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}.xcarchive.zip" "$(basename "$ARCHIVE_PATH")")
    info "xcarchive: $ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}.xcarchive.zip"
  fi
else
  # Unsigned build (no codesign)
  info "Running: flutter build ios --release --no-codesign --build-name=$VERSION --build-number=$BUILD_NUMBER"
  flutter build ios --release --no-codesign --build-name="$VERSION" --build-number="$BUILD_NUMBER" ${DSH_HOST_URL:+--dart-define=DSH_HOST_URL="$DSH_HOST_URL"} || {
    error "iOS unsigned build failed"
    exit 1
  }
  ARCHIVE_PATH="$(find build/ios -name "*.xcarchive" -type d 2>/dev/null | head -1 || true)"
  if [[ -n "$ARCHIVE_PATH" && -d "$ARCHIVE_PATH" ]]; then
    (cd "$(dirname "$ARCHIVE_PATH")" && zip -qr "$ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}.xcarchive.zip" "$(basename "$ARCHIVE_PATH")")
    info "xcarchive (unsigned): $ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}.xcarchive.zip"
  else
    # Fallback: zip the build/ios/iphoneos output
    if [[ -d "build/ios/iphoneos" ]]; then
      (cd build/ios && zip -qr "$ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}-iphoneos.zip" iphoneos)
      info "iphoneos zip: $ARTIFACTS_DIR/ios/dsh-flutter-${VERSION}+${BUILD_NUMBER}-iphoneos.zip"
    fi
  fi
fi

# Smoke: verify Info.plist inside archive
if [[ -n "${ARCHIVE_PATH:-}" && -d "$ARCHIVE_PATH" ]]; then
  INFO_PLIST="$ARCHIVE_PATH/Products/Applications/Runner.app/Info.plist"
  if [[ -f "$INFO_PLIST" ]]; then
    V="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "unknown")"
    B="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "unknown")"
    info "Archive Info.plist: $V ($B) — expected $VERSION ($BUILD_NUMBER)"
  fi
fi

popd >/dev/null
info "iOS build complete"
