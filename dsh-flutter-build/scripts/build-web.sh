#!/usr/bin/env bash
# build-web.sh — Flutter Web release build (configurable DSH_HOST_URL).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd flutter
require_cmd node

get_yaml() {
  node -e "
    const fs=require('fs');
    try{ const y=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); const p=process.argv[2].split('.'); let c=y; for(const k of p) c=c?.[k]; if(c==null) process.exit(1); process.stdout.write(String(c)); } catch(e){ process.exit(2); }
  " "$RELEASE_YAML" "$1" 2>/dev/null || yaml_get "$1"
}

APP_DIR="$MONOREPO_ROOT/$(get_yaml 'app.path' 2>/dev/null || echo 'apps/flutter')"
VERSION="$(get_yaml 'release.version')"
BUILD_NUMBER="$(get_yaml 'release.buildNumber')"
DSH_HOST_URL="${DSH_HOST_URL:-$(get_yaml 'platforms.web.dartDefine.DSH_HOST_URL' 2>/dev/null || echo '')}"
REQUIRE_NON_LOCAL="${REQUIRE_NON_LOCAL:-false}"

info "Web build: $APP_DIR @ $VERSION+$BUILD_NUMBER (DSH_HOST_URL=${DSH_HOST_URL:-<origin>})"

if [[ "$REQUIRE_NON_LOCAL" == "true" && ( -z "$DSH_HOST_URL" || "$DSH_HOST_URL" == *"localhost"* || "$DSH_HOST_URL" == *"127.0.0.1"* ) ]]; then
  die "Production web build requires non-local DSH_HOST_URL (got: ${DSH_HOST_URL:-<empty>})"
fi
if [[ -n "$DSH_HOST_URL" && "$DSH_HOST_URL" == *"localhost"* ]]; then
  warn "DSH_HOST_URL contains localhost — not suitable for production"
fi

[[ -d "$APP_DIR" ]] || die "App dir not found: $APP_DIR"
[[ -f "$APP_DIR/pubspec.yaml" ]] || die "pubspec.yaml missing at $APP_DIR"

pushd "$APP_DIR" >/dev/null

# Ensure deps
flutter pub get

WEB_OUT="build/web"
rm -rf "$WEB_OUT"

# Build flags
BUILD_ARGS=( build web --release --wasm --build-name="$VERSION" --build-number="$BUILD_NUMBER" )
if [[ -n "$DSH_HOST_URL" ]]; then
  BUILD_ARGS+=( --dart-define="DSH_HOST_URL=$DSH_HOST_URL" )
fi
# Optional renderer override from manifest
RENDERER="$(get_yaml 'platforms.web.renderer' 2>/dev/null || echo "")"
if [[ -n "$RENDERER" && "$RENDERER" != "null" && "$RENDERER" != "undefined" ]]; then
  BUILD_ARGS+=( --web-renderer "$RENDERER" )
fi

info "Running: flutter ${BUILD_ARGS[*]}"
flutter "${BUILD_ARGS[@]}"

if [[ ! -d "$WEB_OUT" ]]; then
  die "Web build output missing: $WEB_OUT"
fi

# Verify: index.html exists and no hardcoded localhost when production
if [[ ! -f "$WEB_OUT/index.html" ]]; then
  die "Web artifact missing index.html"
fi
if [[ "$REQUIRE_NON_LOCAL" == "true" ]]; then
  if grep -rq "localhost" "$WEB_OUT" 2>/dev/null; then
    warn "Web output contains 'localhost' strings — inspect DSH_HOST_URL injection"
  fi
fi

# Package
ensure_artifacts_dir
ARCHIVE="$ARTIFACTS_DIR/web/dsh-flutter-web-${VERSION}+${BUILD_NUMBER}.tar.gz"
mkdir -p "$(dirname "$ARCHIVE")"
# Archive build/web contents (not the build/ dir itself)
tar -czf "$ARCHIVE" -C "$WEB_OUT" .
info "Web archive: $ARCHIVE ($(du -h "$ARCHIVE" | awk '{print $1}'))"

# Also keep an unpacked copy for CI smoke (serve test)
UNPACKED="$ARTIFACTS_DIR/web/build"
rm -rf "$UNPACKED"
cp -R "$WEB_OUT" "$UNPACKED"
info "Unpacked copy: $UNPACKED"

popd >/dev/null

# Smoke: verify artifact serves (basic file check)
if command -v python3 >/dev/null 2>&1; then
  info "Web smoke: index.html exists and is non-empty"
  [[ -s "$ARTIFACTS_DIR/web/build/index.html" ]] || die "Web smoke failed: index.html empty"
fi

info "Web build complete: $ARCHIVE"
