#!/usr/bin/env bash
# build-linux.sh — Flutter Linux release → bundle + AppImage/.deb hooks
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

if [[ "$(uname -s)" != "Linux" ]]; then
  warn "Linux build requires a Linux runner (current: $(uname -s)) — skipping native compile."
  if [[ ! -d "$APP_DIR/linux" ]]; then
    warn "Linux platform folder missing — creating via: flutter create --platforms=linux . (metadata only)"
    (cd "$APP_DIR" && flutter create --platforms=linux . 2>&1) || warn "flutter create linux failed"
  fi
  info "Linux: metadata present, native build skipped on non-Linux host (CI will build on ubuntu-22.04)"
  exit 0
fi

info "Linux build: $APP_DIR @ $VERSION+$BUILD_NUMBER"
[[ -d "$APP_DIR/linux" ]] || die "Linux platform not available"

# Check native deps
if [[ "$(uname -s)" == "Linux" ]]; then
  for dep in clang cmake ninja-build pkg-config libgtk-3-dev; do
    if ! dpkg -s "$dep" >/dev/null 2>&1 2>/dev/null; then
      warn "Native dep may be missing: $dep (install via apt)"
    fi
  done
fi

pushd "$APP_DIR" >/dev/null
flutter pub get

BUILD_ARGS=( build linux --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" )
if [[ -n "${DSH_HOST_URL:-}" ]]; then
  BUILD_ARGS+=( --dart-define="DSH_HOST_URL=$DSH_HOST_URL" )
fi

info "Running: flutter ${BUILD_ARGS[*]}"
flutter "${BUILD_ARGS[@]}" || {
  error "Linux build failed — ensure clang/cmake/ninja/pkg-config/libgtk-3-dev are installed"
  exit 1
}

LINUX_OUT="build/linux/x64/release/bundle"
if [[ ! -d "$LINUX_OUT" ]]; then
  LINUX_OUT="$(find build/linux -type d -name bundle 2>/dev/null | head -1 || echo "build/linux/x64/release/bundle")"
fi
[[ -d "$LINUX_OUT" ]] || die "Linux bundle not found: $LINUX_OUT"
info "Linux bundle: $LINUX_OUT ($(du -sh "$LINUX_OUT" 2>/dev/null | awk '{print $1}'))"

ensure_artifacts_dir
mkdir -p "$ARTIFACTS_DIR/linux"

# 1) Tarball of the bundle (always)
TARBALL="$ARTIFACTS_DIR/linux/dsh-flutter-linux-x64-${VERSION}+${BUILD_NUMBER}.tar.gz"
tar -czf "$TARBALL" -C "$(dirname "$LINUX_OUT")" "$(basename "$LINUX_OUT")"
info "Tarball: $TARBALL ($(du -h "$TARBALL" | awk '{print $1}'))"

# 2) AppImage hook (requires linuxdeploy / appimagetool — optional)
if [[ -n "${LINUX_APPIMAGE_HOOK:-}" ]]; then
  info "AppImage hook: $LINUX_APPIMAGE_HOOK"
  bash -c "$LINUX_APPIMAGE_HOOK" || warn "AppImage hook failed"
elif command -v appimagetool >/dev/null 2>&1; then
  info "appimagetool found — building AppImage (best-effort)"
  APPIMAGE="$ARTIFACTS_DIR/linux/dsh-flutter-linux-x64-${VERSION}+${BUILD_NUMBER}.AppImage"
  # Minimal AppDir scaffolding
  APPDIR="$(mktemp -d)/dsh-flutter.AppDir"
  mkdir -p "$APPDIR/usr/bin"
  cp -R "$LINUX_OUT"/* "$APPDIR/usr/bin/" 2>/dev/null || cp -R "$LINUX_OUT" "$APPDIR/usr/bin/bundle"
  cat > "$APPDIR/dsh-flutter.desktop" <<EOF
[Desktop Entry]
Name=DeepSeek Harness
Exec=dsh_flutter
Icon=dsh_flutter
Type=Application
Categories=Development;Utility;
EOF
  # Icon fallback
  if [[ -f "$APP_DIR/web/icons/Icon-512.png" ]]; then
    cp "$APP_DIR/web/icons/Icon-512.png" "$APPDIR/dsh_flutter.png"
  fi
  appimagetool "$APPDIR" "$APPIMAGE" 2>&1 || warn "appimagetool failed"
  info "AppImage: $APPIMAGE"
else
  warn "Skipping AppImage — set LINUX_APPIMAGE_HOOK or install appimagetool"
fi

# 3) .deb hook (requires dpkg-deb — optional)
if [[ -n "${LINUX_DEB_HOOK:-}" ]]; then
  info ".deb hook: $LINUX_DEB_HOOK"
  bash -c "$LINUX_DEB_HOOK" || warn ".deb hook failed"
elif command -v dpkg-deb >/dev/null 2>&1 && [[ "$(uname -s)" == "Linux" ]]; then
  info "Building minimal .deb (best-effort)"
  DEB_ROOT="$(mktemp -d)/deb"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/usr/bin" "$DEB_ROOT/usr/share/applications" "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps"
  cp -R "$LINUX_OUT"/* "$DEB_ROOT/usr/bin/" 2>/dev/null || true
  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: dsh-flutter
Version: ${VERSION}
Architecture: amd64
Maintainer: $(get_yaml 'platforms.linux.maintainer' 2>/dev/null || echo 'DeepSeek AI <support@deepseek.com>')
Description: DeepSeek Harness Flutter client
 DeepSeek Harness — Flutter client for the DSH host.
EOF
  cat > "$DEB_ROOT/usr/share/applications/dsh-flutter.desktop" <<EOF
[Desktop Entry]
Name=DeepSeek Harness
Exec=/usr/bin/dsh_flutter
Icon=dsh_flutter
Type=Application
Categories=Development;Utility;
EOF
  if [[ -f "$APP_DIR/web/icons/Icon-512.png" ]]; then
    cp "$APP_DIR/web/icons/Icon-512.png" "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps/dsh_flutter.png"
  fi
  DEB="$ARTIFACTS_DIR/linux/dsh-flutter-linux-x64-${VERSION}+${BUILD_NUMBER}.deb"
  dpkg-deb --build "$DEB_ROOT" "$DEB" 2>&1 || warn "dpkg-deb failed"
  info ".deb: $DEB ($(du -h "$DEB" 2>/dev/null | awk '{print $1}'))"
else
  warn "Skipping .deb — not on Linux or LINUX_DEB_HOOK not set"
fi

# Smoke: bundle executable exists
if [[ -f "$LINUX_OUT/dsh_flutter" ]]; then
  info "Smoke: $LINUX_OUT/dsh_flutter exists ($(du -h "$LINUX_OUT/dsh_flutter" | awk '{print $1}'))"
else
  warn "Smoke: bundle executable not found"
  ls -la "$LINUX_OUT" | head -20 || true
fi

popd >/dev/null
info "Linux build complete"
