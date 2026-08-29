#!/usr/bin/env bash
# common.sh — shared helpers for dsh-flutter-build scripts.
# Sourced with: source "$(dirname "$0")/common.sh"
# Strict mode is set by callers; this file only defines functions/vars.

set -euo pipefail

# Resolve the build-repo root regardless of cwd or symlink.
BUILD_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONOREPO_ROOT="$(cd "$BUILD_REPO_ROOT/.." && pwd)"
# When consumed as a standalone clone, MONOREPO_ROOT == BUILD_REPO_ROOT's parent
# may not be the harness/app repo; callers override APP_DIR / HARNESS_DIR via
# release.yaml `app.path` / `harness.path` resolved at bootstrap.

RELEASE_YAML="${BUILD_REPO_ROOT}/release.yaml"
VERSION_FILE="${BUILD_REPO_ROOT}/VERSION"
ARTIFACTS_DIR="${BUILD_REPO_ROOT}/artifacts"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

info()  { echo -e "${GREEN}[info]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[warn]${RESET} $*"; }
error() { echo -e "${RED}[error]${RESET} $*" >&2; }

die() { error "$*"; exit 1; }

# Portable YAML field extractor that tolerates comments without a YAML parser.
# Args: <key-path> e.g. "release.version" -> reads `version:` under `release:`.
# For nested two-level keys only. For deeper needs use yq / node.
yaml_get() {
  local keypath="$1"
  local file="${2:-$RELEASE_YAML}"
  # Implement minimal indented mapping lookup via awk; avoids python/js dependency.
  # Supports formatVersion, release.version etc.
  if [[ "$keypath" == *.* ]]; then
    local parent="${keypath%%.*}"
    local child="${keypath#*.}"
    awk -v p="$parent" -v c="$child" '
      /^[^[:space:]#]/ { in_parent = ($1 == p":") }
      in_parent && $1 == c":" {
        sub(/^[^:]*:[[:space:]]*/, ""); gsub(/^[ \t"]+|[ \t"#].*$/, ""); gsub(/"$/, ""); gsub(/^"/,""); print; exit
      }
    ' "$file"
  else
    awk -v k="$keypath" '$1 == k":" { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/^[ \t"]+|[ \t"#].*$/, ""); gsub(/"$/, ""); gsub(/^"/,""); print; exit }' "$file"
  fi
}

# Extract nested values via node/js-yaml when available for correctness fallback.
yaml_get_node() {
  local keypath="$1"
  local file="${2:-$RELEASE_YAML}"
  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs');
      let raw=fs.readFileSync(process.argv[1],'utf8');
      let j;
      try{ const y=require('js-yaml'); j=y.load(raw); } catch(e){
        // minimal fallback: no js-yaml installed, use env var fallback
        process.exit(2);
      }
      const parts=process.argv[2].split('.');
      let cur=j;
      for(const p of parts){ cur=cur?.[p]; }
      if(cur==null) process.exit(1);
      if(typeof cur==='object') cur=JSON.stringify(cur);
      process.stdout.write(String(cur));
    " "$file" "$keypath" 2>/dev/null && return 0
  fi
  yaml_get "$keypath" "$file"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

semver_valid() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

# Compare versions: returns 0 if $1 == $2
version_eq() { [[ "$1" == "$2" ]]; }

# Compute flutter versionCode from buildNumber per Flutter convention:
# versionCode = buildNumber (or buildNumber * 1000 + ABI suffix for splits).
# We keep it simple: versionCode = buildNumber.
version_code() {
  yaml_get_node "app.buildNumber" 2>/dev/null || echo "1"
}

# SHA256 portable
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "No sha256sum / shasum available"
  fi
}

ensure_artifacts_dir() {
  mkdir -p "$ARTIFACTS_DIR"/{web,macos,windows,linux,android,ios,checksums}
}

# Validate that a git revision exists and is a full 40-hex SHA when required.
validate_revision() {
  local rev="$1"
  local label="$2"
  if [[ -z "$rev" ]]; then die "$label revision is empty (release.yaml)"; fi
  if [[ ! "$rev" =~ ^[0-9a-f]{7,40}$ ]]; then
    die "$label revision '$rev' is not a valid git SHA (expected 7-40 hex)"
  fi
}
