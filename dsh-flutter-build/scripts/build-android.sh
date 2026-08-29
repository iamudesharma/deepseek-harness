#!/usr/bin/env bash
# build-android.sh — Flutter Android APK + AAB
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
APP_ID_MANIFEST="$(get_yaml 'platforms.android.applicationId' 2>/dev/null || echo 'ai.deepseek.dshFlutter')"

# Normalize android applicationId to lowercase (Android requires)
APP_ID="$(echo "$APP_ID_MANIFEST" | tr '[:upper:]' '[:lower:]')"

info "Android build: $APP_DIR @ $VERSION+$BUILD_NUMBER (applicationId=$APP_ID)"

if [[ ! -d "$APP_DIR/android" ]]; then
  warn "Android platform folder missing — running: flutter create --platforms=android ."
  (cd "$APP_DIR" && flutter create --platforms=android .)
fi

# Ensure gradle wrapper is executable
chmod +x "$APP_DIR/android/gradlew" 2>/dev/null || true

# Signing setup via env (CI secrets):
#   DSH_ANDROID_KEYSTORE_BASE64  — base64-encoded .jks
#   DSH_ANDROID_KEYSTORE_PASSWORD
#   DSH_ANDROID_KEY_ALIAS
#   DSH_ANDROID_KEY_PASSWORD
# When absent, release builds use debug signing (suitable for local/PR smoke).
setup_signing() {
  if [[ -n "${DSH_ANDROID_KEYSTORE_BASE64:-}" ]]; then
    info "Configuring Android release signing from env"
    KEYSTORE_PATH="$APP_DIR/android/app/release.keystore"
    # Portable base64 decode: GNU --decode/-d, BSD -D
    if ! echo "$DSH_ANDROID_KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE_PATH" 2>/dev/null; then
      if ! echo "$DSH_ANDROID_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE_PATH" 2>/dev/null; then
        echo "$DSH_ANDROID_KEYSTORE_BASE64" | base64 -D > "$KEYSTORE_PATH" 2>/dev/null || {
          error "Failed to decode DSH_ANDROID_KEYSTORE_BASE64"
          exit 1
        }
      fi
    fi
    cat > "$APP_DIR/android/key.properties" <<EOF
storeFile=release.keystore
storePassword=${DSH_ANDROID_KEYSTORE_PASSWORD:-}
keyAlias=${DSH_ANDROID_KEY_ALIAS:-}
keyPassword=${DSH_ANDROID_KEY_PASSWORD:-}
EOF
    info "  keystore: $KEYSTORE_PATH"
    if ! grep -q "key.properties" "$APP_DIR/android/app/build.gradle.kts" 2>/dev/null; then
      warn "build.gradle.kts does not reference key.properties — release will still use debug signing unless template is updated"
      warn "  To enable release signing, add keystoreProperties loading to android/app/build.gradle.kts (see docs/signing.md)"
    fi
  else
    if [[ -f "$APP_DIR/android/app/release.keystore" && -f "$APP_DIR/android/key.properties" ]]; then
      info "Using existing local release keystore at $APP_DIR/android/app/release.keystore"
    else
      warn "No DSH_ANDROID_KEYSTORE_BASE64 and no local keystore — using debug signing (OK for local/PR)"
    fi
  fi
}

setup_signing

# Optional applicationId override: inject via --build-name/number only changes version;
# applicationId is set in build.gradle.kts. We patch it if manifest diverges.
# Only patch when manifest's applicationId is not the placeholder and differs.
if grep -q 'applicationId = "com.example' "$APP_DIR/android/app/build.gradle.kts" 2>/dev/null; then
  if [[ "$APP_ID" != "com.example.dsh_flutter" ]]; then
    info "Patching applicationId placeholder -> $APP_ID"
    # Use perl for cross-platform in-place
    perl -pi -e "s/applicationId = \"com\\.example\\.dsh_flutter\"/applicationId = \"$APP_ID\"/" "$APP_DIR/android/app/build.gradle.kts"
  fi
fi

# Also guard against localhost DSH_HOST in release
if [[ -n "${DSH_HOST_URL:-}" && "${DSH_HOST_URL:-}" == *"localhost"* ]]; then
  warn "DSH_HOST_URL contains localhost — not suitable for Play release"
fi

pushd "$APP_DIR" >/dev/null
flutter pub get

ensure_artifacts_dir
mkdir -p "$ARTIFACTS_DIR/android"

# Debug APK for CI smoke (fast)
info "Building debug APK (smoke)..."
flutter build apk --debug --build-name="$VERSION" --build-number="$BUILD_NUMBER" ${DSH_HOST_URL:+--dart-define=DSH_HOST_URL="$DSH_HOST_URL"} || warn "debug APK failed"
if [[ -f "build/app/outputs/flutter-apk/app-debug.apk" ]]; then
  cp "build/app/outputs/flutter-apk/app-debug.apk" "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}-debug.apk"
  info "Debug APK: $ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}-debug.apk"
fi

# Release APK + AAB (Play publishing)
info "Building release APK..."
flutter build apk --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" ${DSH_HOST_URL:+--dart-define=DSH_HOST_URL="$DSH_HOST_URL"} || {
  error "release APK build failed"
  exit 1
}
if [[ -f "build/app/outputs/flutter-apk/app-release.apk" ]]; then
  cp "build/app/outputs/flutter-apk/app-release.apk" "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.apk"
  info "Release APK: $ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.apk"
fi

info "Building Android App Bundle (AAB)..."
flutter build appbundle --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" ${DSH_HOST_URL:+--dart-define=DSH_HOST_URL="$DSH_HOST_URL"} || {
  error "AAB build failed"
  exit 1
}
if [[ -f "build/app/outputs/bundle/release/app-release.aab" ]]; then
  cp "build/app/outputs/bundle/release/app-release.aab" "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.aab"
  info "AAB: $ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.aab"
fi

# Smoke: verify permissions / manifests
if command -v aapt2 >/dev/null 2>&1 && [[ -f "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.apk" ]]; then
  info "APK permissions:"
  aapt2 dump permissions "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.apk" 2>&1 | head -20 || true
else
  # Fallback via unzip + manifest inspection
  if [[ -f "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.apk" ]] && command -v unzip >/dev/null 2>&1; then
    info "APK exists, listing contents (first 10):"
    unzip -l "$ARTIFACTS_DIR/android/dsh-flutter-${VERSION}+${BUILD_NUMBER}.apk" | head -20 || true
  fi
fi

popd >/dev/null
info "Android build complete"
