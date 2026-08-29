#!/usr/bin/env bash
# verify.sh — reusable verification pipeline:
# bootstrap → analyzer → unit tests → tracker checks → build sanity → package checks → checksum verify → release manifest
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd node
require_cmd flutter

get_yaml() {
  node -e "
    const fs=require('fs');
    try{ const y=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); const p=process.argv[2].split('.'); let c=y; for(const k of p) c=c?.[k]; if(c==null) process.exit(1); process.stdout.write(String(c)); } catch(e){ process.exit(2); }
  " "$RELEASE_YAML" "$1" 2>/dev/null || yaml_get "$1"
}

APP_PATH="$(get_yaml 'app.path' 2>/dev/null || echo 'apps/flutter')"
APP_DIR="$MONOREPO_ROOT/$APP_PATH"
FAILURES=0
fail() { error "$*"; FAILURES=$((FAILURES+1)); }

info "=== Verify pipeline ==="
info "Manifest: $RELEASE_YAML"
node "$SCRIPT_DIR/validate-manifest.mjs" || fail "manifest validation"

info "--- Bootstrap (toolchain + lockfile) ---"
"$SCRIPT_DIR/bootstrap.sh" || fail "bootstrap"

info "--- Version propagation ---"
"$SCRIPT_DIR/version.sh" check || fail "version check"

info "--- Flutter analyzer ---"
if [[ -d "$APP_DIR" ]]; then
  (cd "$APP_DIR" && flutter analyze) || fail "flutter analyze"
else
  warn "App dir missing — skipping analyze"
fi

info "--- Dart format check ---"
if [[ -d "$APP_DIR" ]]; then
  (cd "$APP_DIR" && dart format --set-exit-if-changed lib test 2>&1 | head -20) || warn "dart format diff (run: dart format lib test)"
fi

info "--- Unit tests ---"
if [[ -d "$APP_DIR" ]]; then
  (cd "$APP_DIR" && flutter test --reporter=compact) || fail "flutter test"
else
  warn "App dir missing — skipping tests"
fi

info "--- Tracker validation (where applicable) ---"
if [[ -f "$MONOREPO_ROOT/scripts/verify-flutter-tracker.ts" ]]; then
  (cd "$MONOREPO_ROOT" && npx tsx scripts/verify-flutter-tracker.ts) || warn "verify-flutter-tracker failed (informational on feature branches)"
else
  info "No verify-flutter-tracker script — skipping"
fi

info "--- Package metadata checks ---"
# Ensure no secrets in repo
if grep -r -i "BEGIN PRIVATE KEY\|BEGIN RSA PRIVATE KEY\|DSH_.*TOKEN\|keystore.*password" "$BUILD_REPO_ROOT" --include="*.yaml" --include="*.sh" --include="*.mjs" 2>/dev/null | grep -v ".git" | head -5; then
  fail "Potential secret found in build repo (see grep above)"
else
  info "No secrets detected in build repo"
fi

# Ensure artifacts/.gitignore is effective
if git -C "$BUILD_REPO_ROOT" check-ignore -q "$BUILD_REPO_ROOT/artifacts/dummy" 2>/dev/null || true; then
  # check-ignore returns 0 when ignored; we test via parent's .gitignore? standalone repo check is different
  :
fi
if [[ -f "$BUILD_REPO_ROOT/.gitignore" ]] && grep -q "^artifacts/" "$BUILD_REPO_ROOT/.gitignore"; then
  info "artifacts/ is gitignored"
else
  warn "artifacts/ not ignored in $BUILD_REPO_ROOT/.gitignore"
fi

info "--- Artifact existence (after prior builds) ---"
if [[ -d "$ARTIFACTS_DIR" ]]; then
  FOUND="$(find "$ARTIFACTS_DIR" -type f ! -name ".gitkeep" ! -path "*/checksums/*" 2>/dev/null | wc -l | xargs)"
  info "Artifacts present: $FOUND files"
  if [[ "$FOUND" -gt 0 ]]; then
    find "$ARTIFACTS_DIR" -type f ! -name ".gitkeep" ! -path "*/checksums/*" | head -20 | while read -r f; do info "  $f"; done
  fi
fi

info "--- Checksums ---"
if [[ -f "$ARTIFACTS_DIR/checksums/SHA256SUMS" ]]; then
  "$SCRIPT_DIR/checksum.sh" verify || fail "checksum verify"
else
  warn "No SHA256SUMS yet — run: ./scripts/checksum.sh generate (after building)"
fi

info "--- Release manifest ---"
if [[ -f "$ARTIFACTS_DIR/release-manifest.json" ]]; then
  node "$SCRIPT_DIR/release-manifest.mjs" --check || fail "release-manifest check"
  # Validate required fields
  node -e "
    const fs=require('fs'), p=process.argv[1];
    const j=JSON.parse(fs.readFileSync(p,'utf8'));
    const req=['version','app','harness','toolchain','artifacts','checksumsFile'];
    for(const k of req) if(!(k in j)) { console.error('missing '+k); process.exit(1); }
    for(const [rel,meta] of Object.entries(j.artifacts)) if(!meta.sha256) { console.error('artifact missing sha256: '+rel); process.exit(1); }
    console.log('[ok] release-manifest structure valid');
  " "$ARTIFACTS_DIR/release-manifest.json" || fail "release-manifest structure"
else
  warn "No release-manifest.json — run: node scripts/release-manifest.mjs"
fi

info "--- Unsupported platform detection ---"
for plat in windows linux; do
  if [[ ! -d "$APP_DIR/$plat" ]]; then
    warn "Platform folder missing: $plat (build will create it on appropriate runner)"
  fi
done

if [[ "$FAILURES" -gt 0 ]]; then
  die "Verify pipeline failed: $FAILURES check(s) failed"
fi
info "Verify pipeline passed"
