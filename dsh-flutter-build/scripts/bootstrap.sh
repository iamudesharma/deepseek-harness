#!/usr/bin/env bash
# bootstrap.sh — deterministic source checkout + toolchain verification.
# Usage:
#   ./scripts/bootstrap.sh            # verify current checkout matches manifest
#   ./scripts/bootstrap.sh --fetch    # (standalone mode) clone/fetch pinned revisions into .sources/
#   ./scripts/bootstrap.sh --strict   # fail on any lockfile drift
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FETCH=0
STRICT=0
for arg in "$@"; do
  case "$arg" in
    --fetch) FETCH=1 ;;
    --strict) STRICT=1 ;;
    -h|--help)
      echo "Usage: $0 [--fetch] [--strict]"
      echo "  --fetch   Clone pinned revisions into .sources/ (standalone build-repo mode)"
      echo "  --strict  Fail if lockfiles would change after install"
      exit 0
      ;;
    *) die "Unknown arg: $arg" ;;
  esac
done

info "Validating release manifest..."
node "$SCRIPT_DIR/validate-manifest.mjs"

# Read pinned values (prefer node/js-yaml when available)
require_cmd node
require_cmd git

# Helper to get yaml value via node for correctness
get() {
  node -e "
    const fs=require('fs');
    let j; try{ j=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); } catch(e){ process.exit(2); }
    const parts=process.argv[2].split('.');
    let cur=j; for(const p of parts) cur=cur?.[p];
    if(cur==null) process.exit(1);
    process.stdout.write(String(cur));
  " "$RELEASE_YAML" "$1" 2>/dev/null || yaml_get "$1"
}

APP_REV="$(get 'app.revision')"
HARNESS_REV="$(get 'harness.revision')"
APP_REPO="$(get 'app.repository')"
HARNESS_REPO="$(get 'harness.repository')"
APP_PATH="$(get 'app.path')"
FLUTTER_VERSION="$(get 'toolchain.flutter.version')"
FLUTTER_CHANNEL="$(get 'toolchain.flutter.channel')"
DART_VERSION="$(get 'toolchain.dart.version')"
NODE_VERSION="$(get 'toolchain.node.version')"
PNPM_VERSION="$(get 'toolchain.pnpm.version')"
RELEASE_VERSION="$(get 'release.version')"
BUILD_NUMBER="$(get 'release.buildNumber')"

# Derive expected monorepo root: app.path is relative to repo root.
# In monorepo mode, MONOREPO_ROOT should contain APP_PATH.
if [[ -f "$MONOREPO_ROOT/$APP_PATH/pubspec.yaml" ]]; then
  APP_DIR="$MONOREPO_ROOT/$APP_PATH"
  HARNESS_DIR="$MONOREPO_ROOT"
  info "Monorepo mode: app dir = $APP_DIR"
else
  # Standalone mode: app/harness may have been fetched into .sources/
  APP_DIR="$BUILD_REPO_ROOT/.sources/app/$APP_PATH"
  HARNESS_DIR="$BUILD_REPO_ROOT/.sources/harness"
  if [[ "$FETCH" -eq 1 ]]; then
    info "Standalone fetch mode — cloning pinned revisions..."
    mkdir -p "$BUILD_REPO_ROOT/.sources"
    fetch_repo() {
      local repo="$1" rev="$2" dest="$3" label="$4"
      if [[ -d "$dest/.git" ]]; then
        info "Fetching $label @ $rev into $dest ..."
        git -C "$dest" fetch --depth 1 origin "$rev" || git -C "$dest" fetch origin
        git -C "$dest" checkout --detach "$rev"
      else
        info "Cloning $label $repo @ $rev ..."
        rm -rf "$dest"
        git clone --depth 1 "$repo" "$dest"
        git -C "$dest" fetch --depth 50 origin "$rev" || true
        git -C "$dest" checkout --detach "$rev"
      fi
      local actual
      actual="$(git -C "$dest" rev-parse HEAD)"
      if [[ "$actual" != "$rev" ]]; then
        # Allow short SHA prefix match for convenience
        if [[ "$rev" == "$actual"* ]]; then
          info "$label revision prefix match: $rev -> $actual"
        else
          die "$label revision mismatch: expected $rev, got $actual"
        fi
      fi
    }
    fetch_repo "$APP_REPO" "$APP_REV" "$BUILD_REPO_ROOT/.sources/app" "app"
    if [[ "$HARNESS_REPO" != "$APP_REPO" ]]; then
      fetch_repo "$HARNESS_REPO" "$HARNESS_REV" "$HARNESS_DIR" "harness"
    else
      # Same repo — reuse app clone as harness
      HARNESS_DIR="$BUILD_REPO_ROOT/.sources/app"
    fi
  else
    warn "App dir not found at $APP_DIR; run with --fetch to clone pinned revisions"
  fi
fi

info "Verifying clean git state..."
if [[ -d "$HARNESS_DIR/.git" ]]; then
  if ! git -C "$HARNESS_DIR" diff --quiet 2>/dev/null; then
    warn "Working tree has unstaged changes in $HARNESS_DIR"
    if [[ "$STRICT" -eq 1 ]]; then die "Strict mode: dirty working tree"; fi
  fi
  CURRENT_REV="$(git -C "$HARNESS_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
  info "Current harness HEAD: $CURRENT_REV"
  info "Pinned harness revision: $HARNESS_REV"
  if [[ "$CURRENT_REV" != "$HARNESS_REV" && "$HARNESS_REV" != "${CURRENT_REV:0:${#HARNESS_REV}}" ]]; then
    warn "Current HEAD does not match pinned harness revision"
    warn "  current: $CURRENT_REV"
    warn "  pinned:  $HARNESS_REV"
    if [[ "$STRICT" -eq 1 ]]; then die "Strict mode: revision mismatch"; fi
  else
    info "Revision check passed"
  fi
fi

# Toolchain verification
info "Verifying toolchain..."

# Node
if command -v node >/dev/null 2>&1; then
  ACTUAL_NODE="$(node --version | sed 's/^v//')"
  info "Node: $ACTUAL_NODE (required $NODE_VERSION)"
  # Use node semver check via JS if possible
  node -e "
    const actual=process.argv[1], range=process.argv[2] || process.argv[3];
    // minimal semver range check for ^22.19 style — delegate to JS semver if available
    try {
      const semver=require('semver');
      if(!semver.satisfies(actual, range)) { console.error('Node version '+actual+' does not satisfy '+range); process.exit(1); }
    } catch(e) {
      // fallback: exact major check
      const majActual=actual.split('.')[0], majReq=(range.match(/\d+/)||[''])[0];
      if(majActual!==majReq) console.warn('[warn] Node major mismatch: '+actual+' vs '+range);
    }
  " "$ACTUAL_NODE" "$(get 'toolchain.node.range' 2>/dev/null || echo "$NODE_VERSION")" "$NODE_VERSION" || {
    if [[ "$STRICT" -eq 1 ]]; then die "Node version check failed"; fi
  }
else
  warn "node not found — skipping Node version check"
fi

# pnpm
if command -v pnpm >/dev/null 2>&1; then
  ACTUAL_PNPM="$(pnpm --version 2>/dev/null || echo "unknown")"
  info "pnpm: $ACTUAL_PNPM (required $PNPM_VERSION)"
  if [[ "$ACTUAL_PNPM" != "$PNPM_VERSION" ]]; then
    warn "pnpm version mismatch: got $ACTUAL_PNPM, pinned $PNPM_VERSION"
    if [[ "$STRICT" -eq 1 ]]; then die "pnpm version mismatch in strict mode"; fi
  fi
else
  warn "pnpm not found — will be required for harness builds"
fi

# Flutter
if command -v flutter >/dev/null 2>&1; then
  ACTUAL_FLUTTER="$(flutter --version 2>&1 | grep -oE 'Flutter [0-9.]+' | awk '{print $2}' || echo "unknown")"
  info "Flutter: $ACTUAL_FLUTTER (required $FLUTTER_VERSION, channel $FLUTTER_CHANNEL)"
  if [[ "$ACTUAL_FLUTTER" != "$FLUTTER_VERSION" ]]; then
    warn "Flutter version mismatch: got $ACTUAL_FLUTTER, pinned $FLUTTER_VERSION"
    if [[ "$STRICT" -eq 1 ]]; then die "Flutter version mismatch in strict mode"; fi
  fi
  ACTUAL_CHANNEL="$(flutter channel 2>&1 | grep '^\*' | awk '{print $2}' || echo "unknown")"
  info "Flutter channel: $ACTUAL_CHANNEL (required $FLUTTER_CHANNEL)"
  if [[ "$ACTUAL_CHANNEL" != "$FLUTTER_CHANNEL" ]]; then
    warn "Flutter channel mismatch: got $ACTUAL_CHANNEL, required $FLUTTER_CHANNEL"
  fi
else
  warn "flutter not found — install Flutter $FLUTTER_VERSION ($FLUTTER_CHANNEL)"
  if [[ "$STRICT" -eq 1 ]]; then die "flutter not found in strict mode"; fi
fi

# Dart
if command -v dart >/dev/null 2>&1; then
  ACTUAL_DART="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")"
  info "Dart: $ACTUAL_DART (required $DART_VERSION)"
  if [[ "$ACTUAL_DART" != "$DART_VERSION" ]]; then
    warn "Dart version mismatch: got $ACTUAL_DART, pinned $DART_VERSION"
  fi
fi

# Dependency installation + lockfile verification
if [[ -n "${APP_DIR:-}" && -d "$APP_DIR" ]]; then
  info "Verifying Flutter dependencies in $APP_DIR ..."
  if [[ -f "$APP_DIR/pubspec.lock" ]]; then
    info "pubspec.lock present"
  else
    warn "pubspec.lock missing"
  fi
  # Run pub get and check for drift when strict
  if command -v flutter >/dev/null 2>&1; then
    if [[ "$STRICT" -eq 1 ]]; then
      LOCK_BEFORE="$(sha256_file "$APP_DIR/pubspec.lock" 2>/dev/null || echo "none")"
      (cd "$APP_DIR" && flutter pub get)
      LOCK_AFTER="$(sha256_file "$APP_DIR/pubspec.lock" 2>/dev/null || echo "none")"
      if [[ "$LOCK_BEFORE" != "$LOCK_AFTER" ]]; then
        die "pubspec.lock changed after 'flutter pub get' — commit the updated lockfile"
      fi
      info "Lockfile verification passed"
    else
      # Non-strict: just ensure get succeeds, warn if lockfile drifts
      LOCK_BEFORE="$(sha256_file "$APP_DIR/pubspec.lock" 2>/dev/null || echo "none")"
      (cd "$APP_DIR" && flutter pub get) || warn "flutter pub get failed"
      LOCK_AFTER="$(sha256_file "$APP_DIR/pubspec.lock" 2>/dev/null || echo "none")"
      if [[ "$LOCK_BEFORE" != "$LOCK_AFTER" ]]; then
        warn "pubspec.lock drifted after pub get — consider committing"
      fi
    fi
  fi

  # Harness pnpm lockfile check
  if [[ -f "$HARNESS_DIR/pnpm-lock.yaml" ]]; then
    info "pnpm-lock.yaml present"
    if [[ "$STRICT" -eq 1 ]] && command -v pnpm >/dev/null 2>&1; then
      (cd "$HARNESS_DIR" && pnpm install --frozen-lockfile) || die "pnpm install --frozen-lockfile failed — lockfile drift"
      info "pnpm lockfile verification passed"
    fi
  fi
fi

# Version propagation check: pubspec.yaml version must encode release.version
if [[ -n "${APP_DIR:-}" && -f "$APP_DIR/pubspec.yaml" ]]; then
  PUBSPEC_VER="$(grep -E '^version:' "$APP_DIR/pubspec.yaml" | sed -E 's/version:[[:space:]]*//; s/[[:space:]]*#.*//; s/"//g' | tr -d "'" | xargs || echo "")"
  info "pubspec.yaml version: $PUBSPEC_VER (release.yaml: $RELEASE_VERSION+$BUILD_NUMBER)"
  EXPECTED_PUBSPEC="${RELEASE_VERSION}+${BUILD_NUMBER}"
  if [[ "$PUBSPEC_VER" != "$EXPECTED_PUBSPEC" ]]; then
    warn "pubspec.yaml version ($PUBSPEC_VER) != expected ($EXPECTED_PUBSPEC)"
    warn "  Run: ./scripts/version.sh sync  (to propagate release.yaml → pubspec.yaml)"
    if [[ "$STRICT" -eq 1 ]]; then die "Version drift in strict mode"; fi
  else
    info "Version propagation consistent"
  fi
fi

info "Bootstrap complete."
if [[ "$FETCH" -eq 0 && ! -d "${APP_DIR:-/nonexistent}" ]]; then
  warn "App dir not materialized — re-run with --fetch when building standalone"
fi
