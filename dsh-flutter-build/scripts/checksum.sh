#!/usr/bin/env bash
# checksum.sh — SHA-256 generation + verification for every published artifact.
# Usage:
#   ./scripts/checksum.sh generate           # write artifacts/checksums/SHA256SUMS
#   ./scripts/checksum.sh verify             # verify existing checksums
#   ./scripts/checksum.sh generate --release-manifest  # also embed into release-manifest.json (noop, manifest generator reads SHA256SUMS)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd node

CMD="${1:-generate}"

ARTIFACTS_ABS="$ARTIFACTS_DIR"
CHECKSUMS_DIR="$ARTIFACTS_ABS/checksums"
SUMS_FILE="$CHECKSUMS_DIR/SHA256SUMS"

generate() {
  ensure_artifacts_dir
  mkdir -p "$CHECKSUMS_DIR"
  local tmp
  tmp="$(mktemp)"
  # Only published artifacts: top-level packaged files + web archive, not unpacked
  # introspection copies (web/build/**, macos/*.app/**) which are for smoke only.
  if [[ -d "$ARTIFACTS_ABS" ]]; then
    find "$ARTIFACTS_ABS" -type f \
      ! -path "$CHECKSUMS_DIR/*" \
      ! -path "*/checksums/*" \
      ! -name ".gitkeep" \
      ! -name "*.tmp" \
      ! -name "*.sha256" \
      ! -name "release-manifest.json" \
      ! -name "RELEASE_NOTES.md" \
      ! -path "*/web/build/*" \
      ! -path "*.app/*" \
      ! -path "*/macos/*.app/*" \
      -print0 | sort -z | while IFS= read -r -d '' f; do
        if [[ "$f" == *".app/"* ]]; then
          continue
        fi
        if [[ "$f" == *"/web/build/"* ]]; then
          continue
        fi
        if [[ "$(basename "$f")" == "release-manifest.json" ]]; then
          continue
        fi
        rel="${f#$ARTIFACTS_ABS/}"
        sum="$(sha256_file "$f")"
        printf "%s  %s\n" "$sum" "$rel" >> "$tmp"
        info "  $sum  $rel"
    done
  fi
  if [[ ! -s "$tmp" ]]; then
    warn "No artifacts found to checksum (artifacts/ is empty). Writing empty SHA256SUMS."
  fi
  # Sort for reproducibility
  sort "$tmp" -o "$tmp"
  mv "$tmp" "$SUMS_FILE"
  info "Wrote $SUMS_FILE ($(wc -l < "$SUMS_FILE" | xargs) entries)"

  # Also emit per-artifact .sha256 sidecars for convenience
  while read -r sum rel; do
    [[ -z "$sum" ]] && continue
    echo "$sum" > "$ARTIFACTS_ABS/${rel}.sha256"
  done < "$SUMS_FILE"
  info "Wrote per-artifact .sha256 sidecars"
}

verify() {
  if [[ ! -f "$SUMS_FILE" ]]; then
    die "Checksums file not found: $SUMS_FILE (run: ./scripts/checksum.sh generate)"
  fi
  local failures=0
  local total=0
  while read -r expected rel; do
    [[ -z "$expected" ]] && continue
    total=$((total+1))
    local file="$ARTIFACTS_ABS/$rel"
    if [[ ! -f "$file" ]]; then
      error "Missing artifact: $rel (expected $expected)"
      failures=$((failures+1))
      continue
    fi
    local actual
    actual="$(sha256_file "$file")"
    if [[ "$actual" != "$expected" ]]; then
      error "Checksum mismatch: $rel"
      error "  expected: $expected"
      error "  actual:   $actual"
      failures=$((failures+1))
    else
      info "[ok] $rel"
    fi
    # Structural validity: archive is readable where applicable
    case "$rel" in
      *.zip)
        if command -v unzip >/dev/null 2>&1; then
          unzip -tq "$file" >/dev/null || { error "zip integrity failed: $rel"; failures=$((failures+1)); }
        fi
        ;;
      *.tar.gz|*.tgz)
        if command -v tar >/dev/null 2>&1; then
          tar tzf "$file" >/dev/null || { error "tar.gz integrity failed: $rel"; failures=$((failures+1)); }
        fi
        ;;
      *.dmg)
        if command -v hdiutil >/dev/null 2>&1; then
          hdiutil imageinfo "$file" >/dev/null 2>&1 || warn "dmg info check failed (may be expected on Linux): $rel"
        fi
        ;;
    esac
  done < "$SUMS_FILE"
  if [[ "$failures" -gt 0 ]]; then
    die "Checksum verification failed: $failures/$total failures"
  fi
  info "Checksum verification passed: $total artifacts"
}

case "$CMD" in
  generate) generate ;;
  verify) verify ;;
  *) die "Unknown command: $CMD (expected generate|verify)" ;;
esac
