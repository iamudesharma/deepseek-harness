#!/usr/bin/env bash
# build-windows.sh — Flutter Windows release build → portable zip + MSIX hook
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

# Flutter Windows builds require a Windows host; gracefully skip on other OS
if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* && "$(uname -s)" != CYGWIN* ]] && [[ ! -d "/c/Windows" ]]; then
  warn "Windows build requires a Windows runner (current: $(uname -s)) — skipping native compile."
  if [[ ! -d "$APP_DIR/windows" ]]; then
    warn "Windows platform folder missing — creating metadata via: flutter create --platforms=windows ."
    if command -v flutter >/dev/null 2>&1; then
      (cd "$APP_DIR" && flutter create --platforms=windows . 2>&1) || warn "flutter create windows failed (expected on non-Windows)"
    fi
  fi
  info "Windows: metadata present, native build skipped on non-Windows host (CI will build on windows-2022)"
  exit 0
fi

info "Windows build: $APP_DIR @ $VERSION+$BUILD_NUMBER"
[[ -d "$APP_DIR/windows" ]] || die "Windows platform not available"

pushd "$APP_DIR" >/dev/null
flutter pub get

BUILD_ARGS=( build windows --release --build-name="$VERSION" --build-number="$BUILD_NUMBER" )
if [[ -n "${DSH_HOST_URL:-}" ]]; then
  BUILD_ARGS+=( --dart-define="DSH_HOST_URL=$DSH_HOST_URL" )
fi

info "Running: flutter ${BUILD_ARGS[*]}"
flutter "${BUILD_ARGS[@]}" || {
  error "Windows build failed — ensure Visual Studio + Windows SDK are installed on this runner"
  exit 1
}

# Flutter Windows output: build/windows/x64/runner/Release/
WIN_OUT="build/windows/x64/runner/Release"
if [[ ! -d "$WIN_OUT" ]]; then
  # Try alternative arch layout
  WIN_OUT="$(find build/windows -type d -name Release 2>/dev/null | head -1 || echo "build/windows/x64/runner/Release")"
fi
[[ -d "$WIN_OUT" ]] || die "Windows output not found: $WIN_OUT"
info "Windows output: $WIN_OUT ($(du -sh "$WIN_OUT" 2>/dev/null | awk '{print $1}'))"

ensure_artifacts_dir
mkdir -p "$ARTIFACTS_DIR/windows"

# Portable zip
ZIP="$ARTIFACTS_DIR/windows/dsh-flutter-windows-x64-${VERSION}+${BUILD_NUMBER}.zip"
rm -f "$ZIP"
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -Command "Compress-Archive -Path '$WIN_OUT\\*' -DestinationPath '$(cygpath -w "$ZIP" 2>/dev/null || echo "$ZIP")' -Force" 2>/dev/null || (cd "$WIN_OUT" && zip -qr "$ZIP" .)
else
  (cd "$WIN_OUT" && zip -qr "$ZIP" .)
fi
info "Portable zip: $ZIP ($(du -h "$ZIP" | awk '{print $1}'))"

# Installer hook: if Inno Setup or WiX is configured, CI can produce an installer.
# We do not bundle an installer generator by default; this is an explicit seam.
if [[ -n "${WINDOWS_INSTALLER:-}" ]]; then
  info "WINDOWS_INSTALLER hook: $WINDOWS_INSTALLER — delegating"
  bash -c "$WINDOWS_INSTALLER" || warn "WINDOWS_INSTALLER hook failed"
fi

# Optional code signing (Windows Authenticode) via env
if [[ -n "${WINDOWS_SIGN_PFX_BASE64:-}" && -n "${WINDOWS_SIGN_PASSWORD:-}" ]]; then
  info "Windows code signing requested — env present"
  warn "Authenticode signing is environment-specific (signtool). Wire via DSH_WINDOWS_SIGN_PFX_BASE64 + DSH_WINDOWS_SIGN_PASSWORD."
fi

# Smoke: executable exists
EXE="$WIN_OUT/dsh_flutter.exe"
if [[ -f "$EXE" ]]; then
  info "Smoke: $EXE exists ($(du -h "$EXE" | awk '{print $1}'))"
else
  warn "Smoke: dsh_flutter.exe not found in $WIN_OUT"
  ls -la "$WIN_OUT" | head -20 || true
fi

popd >/dev/null
info "Windows build complete"
