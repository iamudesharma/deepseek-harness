#!/usr/bin/env bash
# release.sh — end-to-end release orchestration.
# Steps: 1 update manifest, 2 pin revisions, 3 pin toolchain, 4 verify, 5 build all,
#        6 package, 7 sign stub, 8 notarize hook, 9 checksums, 10 manifest,
#        11 validate, 12 GitHub Release (optional), 13 notes, 14 store metadata.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DRY_RUN=0
SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--skip-build]"
      exit 0
      ;;
    *) die "Unknown arg: $arg" ;;
  esac
done

info "=== Release orchestration ==="
node "$SCRIPT_DIR/validate-manifest.mjs"

get_yaml() {
  node -e "
    const fs=require('fs');
    try{ const y=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); const p=process.argv[2].split('.'); let c=y; for(const k of p) c=c?.[k]; if(c==null) process.exit(1); process.stdout.write(String(c)); } catch(e){ process.exit(2); }
  " "$RELEASE_YAML" "$1" 2>/dev/null || yaml_get "$1"
}

VERSION="$(get_yaml 'release.version')"
BUILD_NUMBER="$(get_yaml 'release.buildNumber')"
CHANNEL="$(get_yaml 'release.channel')"
info "Release: $VERSION+$BUILD_NUMBER ($CHANNEL)"

info "[1/14] Manifest already authoritative (release.yaml)"
info "[2/14] Pinning app revision..."
APP_REV="$(get_yaml 'app.revision')"
info "  app.revision=$APP_REV"
info "[3/14] Pinning harness revision..."
HARNESS_REV="$(get_yaml 'harness.revision')"
info "  harness.revision=$HARNESS_REV"
info "[4/14] Pinning toolchain..."
FLUTTER_VER="$(get_yaml 'toolchain.flutter.version')"
NODE_VER="$(get_yaml 'toolchain.node.version')"
PNPM_VER="$(get_yaml 'toolchain.pnpm.version')"
info "  flutter $FLUTTER_VER / node $NODE_VER / pnpm $PNPM_VER"

if [[ "$DRY_RUN" -eq 1 ]]; then
  info "Dry run — stopping before verify/build"
  exit 0
fi

info "[5/14] Verification (analyzer + tests + tracker)..."
"$SCRIPT_DIR/verify.sh"

if [[ "$SKIP_BUILD" -eq 1 ]]; then
  info "Skipping builds (--skip-build)"
else
  info "[6/14] Building all platforms..."
  "$SCRIPT_DIR/build.sh" all
  info "[7/14] Packaging (handled per-platform in build.sh)"
  info "[8/14] Signing (hooks wired via CI secrets — local builds are unsigned)"
  if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
    info "  macOS/iOS signing identity present: $APPLE_SIGNING_IDENTITY"
  else
    warn "  No signing identity — artifacts are unsigned (expected locally)"
  fi
  if [[ -n "${DSH_ANDROID_KEYSTORE_BASE64:-}" ]]; then
    info "  Android keystore present"
  else
    warn "  No Android keystore — APK is debug-signed"
  fi
  info "[9/14] Notarization hook (macOS) — requires CI secrets, skipped locally"
fi

info "[10/14] Generating checksums..."
"$SCRIPT_DIR/checksum.sh" generate

info "[11/14] Generating release manifest..."
node "$SCRIPT_DIR/release-manifest.mjs"

info "[12/14] Validating all artifacts..."
"$SCRIPT_DIR/checksum.sh" verify
node "$SCRIPT_DIR/release-manifest.mjs" --check

if command -v gh >/dev/null 2>&1 && [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
  info "[13/14] Creating GitHub Release (gh available)..."
  TAG="v${VERSION}"
  if [[ -n "$(get_yaml 'release.prerelease' 2>/dev/null || echo "")" ]]; then
    TAG="v${VERSION}-$(get_yaml 'release.prerelease')"
  fi
  if gh release view "$TAG" >/dev/null 2>&1; then
    warn "Release $TAG already exists — skipping create"
  else
    info "Would create: gh release create $TAG artifacts/**/* --generate-notes"
    warn "GitHub Release creation is gated on CI — run via .github/workflows/release.yml"
  fi
else
  info "[13/14] Skipping GitHub Release (gh not available or no token) — CI will create it"
fi

info "[14/14] Storing release metadata..."
mkdir -p "$ARTIFACTS_DIR"
cat > "$ARTIFACTS_DIR/RELEASE_NOTES.md" <<EOF
# DeepSeek Harness Flutter $VERSION ($CHANNEL)

- Version: $VERSION+$BUILD_NUMBER
- Channel: $CHANNEL
- App revision: $APP_REV
- Harness revision: $HARNESS_REV
- Flutter: $FLUTTER_VER / Node: $NODE_VER / pnpm: $PNPM_VER
- Artifacts: see release-manifest.json and checksums/SHA256SUMS

## Artifacts
EOF
if [[ -f "$ARTIFACTS_DIR/checksums/SHA256SUMS" ]]; then
  echo "" >> "$ARTIFACTS_DIR/RELEASE_NOTES.md"
  echo '```' >> "$ARTIFACTS_DIR/RELEASE_NOTES.md"
  cat "$ARTIFACTS_DIR/checksums/SHA256SUMS" >> "$ARTIFACTS_DIR/RELEASE_NOTES.md"
  echo '```' >> "$ARTIFACTS_DIR/RELEASE_NOTES.md"
fi

info "Release orchestration complete."
info "Artifacts: $ARTIFACTS_DIR"
ls -R "$ARTIFACTS_DIR" 2>/dev/null | head -60 || true
