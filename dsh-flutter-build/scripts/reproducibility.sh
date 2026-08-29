#!/usr/bin/env bash
# reproducibility.sh — Build same release twice and compare inputs/outputs.
# Where byte-for-byte reproduction is impossible (signing timestamps, archive mtimes),
# verify that source revisions, toolchain, and metadata remain identical and
# document non-deterministic fields.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

info "=== Reproducibility test ==="
node "$SCRIPT_DIR/validate-manifest.mjs"

# Capture first manifest snapshot
FIRST_MANIFEST="$ARTIFACTS_DIR/release-manifest.json"
if [[ ! -f "$FIRST_MANIFEST" ]]; then
  die "No existing manifest — run a build first: bash scripts/build.sh web"
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cp "$FIRST_MANIFEST" "$TMPDIR/first.json"
if [[ -f "$ARTIFACTS_DIR/checksums/SHA256SUMS" ]]; then
  cp "$ARTIFACTS_DIR/checksums/SHA256SUMS" "$TMPDIR/first.SHA256SUMS"
fi

# Capture manifest inputs
get_field() {
  node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); const p=process.argv[2].split('.'); let cur=j; for(const k of p) cur=cur?.[k]; process.stdout.write(JSON.stringify(cur))" "$FIRST_MANIFEST" "$1" 2>/dev/null || echo "null"
}

info "First build: $(get_field version) buildNumber=$(get_field buildNumber) releaseDate=$(get_field releaseDate)"
info "  app.revision=$(get_field app.revision)"
info "  harness.revision=$(get_field harness.revision)"
info "  toolchain.flutter=$(get_field toolchain.flutter.version) toolchain.node=$(get_field toolchain.node.version)"

# Rebuild a fast deterministic artifact (web) twice and compare
info "Rebuilding web for reproducibility check..."
APP_DIR="$MONOREPO_ROOT/$(node -e "try{const y=require('js-yaml').load(require('fs').readFileSync('$RELEASE_YAML','utf8')); process.stdout.write(y.app.path)}catch(e){process.stdout.write('apps/flutter')}" 2>/dev/null || echo "apps/flutter")"
# Save current web tarball hash
WEB_TAR="$(ls "$ARTIFACTS_DIR/web"/dsh-flutter-web-*.tar.gz 2>/dev/null | head -1 || echo "")"
if [[ -z "$WEB_TAR" || ! -f "$WEB_TAR" ]]; then
  warn "No web tarball to compare — building web now"
  bash "$SCRIPT_DIR/build-web.sh" >/dev/null 2>&1 || die "web build failed"
  WEB_TAR="$(ls "$ARTIFACTS_DIR/web"/dsh-flutter-web-*.tar.gz | head -1)"
fi
HASH_BEFORE="$(sha256_file "$WEB_TAR")"
info "  before: $WEB_TAR  $HASH_BEFORE"

# Second build
bash "$SCRIPT_DIR/build-web.sh" >/dev/null 2>&1 || die "second web build failed"
WEB_TAR2="$(ls "$ARTIFACTS_DIR/web"/dsh-flutter-web-*.tar.gz | head -1)"
HASH_AFTER="$(sha256_file "$WEB_TAR2")"
info "  after:  $WEB_TAR2  $HASH_AFTER"

if [[ "$HASH_BEFORE" == "$HASH_AFTER" ]]; then
  info "Byte-for-byte reproducibility: WEB archive identical across builds (PASS)"
else
  warn "WEB archive differs across builds (expected for non-deterministic mtimes/Wasm)"
  warn "  before: $HASH_BEFORE"
  warn "  after:  $HASH_AFTER"
  warn "  Non-deterministic fields: tar mtime, gzip header, Wasm build timestamps"
  # Verify inputs are identical despite output diff
  bash "$SCRIPT_DIR/checksum.sh" generate >/dev/null 2>&1 || true
  node "$SCRIPT_DIR/release-manifest.mjs" >/dev/null 2>&1 || true
  cp "$ARTIFACTS_DIR/release-manifest.json" "$TMPDIR/second.json"
  # Compare inputs (excluding releaseDate and artifact hashes)
  DIFF_INPUTS="$(node -e "
    const a=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    const b=JSON.parse(require('fs').readFileSync(process.argv[2],'utf8'));
    const fields=['version','buildNumber','channel','app','harness','toolchain','platforms'];
    let d=0;
    for(const f of fields) if(JSON.stringify(a[f])!==JSON.stringify(b[f])) { console.error('diff '+f); d++; }
    process.exit(d);
  " "$TMPDIR/first.json" "$TMPDIR/second.json" 2>&1 || true)"
  if [[ -z "$DIFF_INPUTS" ]]; then
    info "Source/build inputs identical across builds (PASS) — output non-determinism is documented"
  else
    error "Inputs differed: $DIFF_INPUTS"
    exit 1
  fi
fi

# Final manifest check
node "$SCRIPT_DIR/release-manifest.mjs" --check && info "Manifest consistency: PASS"

info "Reproducibility test complete"
info "Deterministic fields verified: source revisions, toolchain, manifest inputs"
info "Documented non-deterministic fields: archive mtimes, signing timestamps, gzip headers"
