#!/usr/bin/env bash
# build.sh — cross-platform dispatcher + variant entry points.
# Usage:
#   ./build.sh web
#   ./build.sh macos
#   ./build.sh windows
#   ./build.sh linux
#   ./build.sh android
#   ./build.sh ios
#   ./build.sh all
#   ./build.sh verify   → runs analyzer + tests + packaging checks (no build)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd node

get_platform_enabled() {
  node -e "
    const fs=require('fs');
    try{ const y=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); const v=y?.platforms?.[process.argv[2]]?.enabled; process.stdout.write(v ? 'true' : 'false'); } catch(e){ process.stdout.write('false'); }
  " "$RELEASE_YAML" "$1" 2>/dev/null || echo "false"
}

TARGET="${1:-all}"
case "$TARGET" in
  web)      exec "$SCRIPT_DIR/build-web.sh" ;;
  macos)    exec "$SCRIPT_DIR/build-macos.sh" ;;
  windows)  exec "$SCRIPT_DIR/build-windows.sh" ;;
  linux)    exec "$SCRIPT_DIR/build-linux.sh" ;;
  android)  exec "$SCRIPT_DIR/build-android.sh" ;;
  ios)      exec "$SCRIPT_DIR/build-ios.sh" ;;
  verify)
    exec "$SCRIPT_DIR/verify.sh"
    ;;
  all)
    info "Building all enabled platforms per release.yaml"
    FAILURES=0
    for plat in web macos windows linux android ios; do
      ENABLED="$(get_platform_enabled "$plat")"
      if [[ "$ENABLED" != "true" ]]; then
        info "Skipping disabled platform: $plat"
        continue
      fi
      info "=== Building $plat ==="
      if ! "$SCRIPT_DIR/build-${plat}.sh"; then
        error "Build failed: $plat"
        FAILURES=$((FAILURES+1))
      fi
    done
    if [[ "$FAILURES" -gt 0 ]]; then
      die "$FAILURES platform(s) failed"
    fi
    info "All enabled platform builds succeeded"
    # Post-build: checksums + manifest
    "$SCRIPT_DIR/checksum.sh" generate
    node "$SCRIPT_DIR/release-manifest.mjs"
    info "Artifacts + checksums + release-manifest ready under $ARTIFACTS_DIR"
    ;;
  *)
    die "Unknown target: $TARGET (expected: web|macos|windows|linux|android|ios|all|verify)"
    ;;
esac
