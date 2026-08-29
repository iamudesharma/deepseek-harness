#!/usr/bin/env bash
# version.sh — single release version source and propagation.
# Usage:
#   ./scripts/version.sh get                 # print release version
#   ./scripts/version.sh get --build-number  # print build number
#   ./scripts/version.sh sync                # propagate release.yaml → pubspec.yaml + VERSION + platform configs
#   ./scripts/version.sh bump <newVersion>   # bump release.yaml + VERSION (e.g. 1.1.0 or 1.1.0-rc.1)
#   ./scripts/version.sh check               # verify propagation consistency
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd node

get_yaml() {
  node -e "
    const fs=require('fs');
    let j; try{ j=require('js-yaml').load(fs.readFileSync(process.argv[1],'utf8')); } catch(e){ const c=fs.readFileSync(process.argv[1],'utf8'); console.error(e.message); process.exit(2); }
    const parts=process.argv[2].split('.');
    let cur=j; for(const p of parts) cur=cur?.[p];
    if(cur==null) process.exit(1);
    process.stdout.write(String(cur));
  " "$RELEASE_YAML" "$1" 2>/dev/null || yaml_get "$1"
}

CMD="${1:-get}"

case "$CMD" in
  get)
    if [[ "${2:-}" == "--build-number" ]]; then
      get_yaml "release.buildNumber"
      echo
    elif [[ "${2:-}" == "--full" ]]; then
      VER="$(get_yaml 'release.version')"
      BN="$(get_yaml 'release.buildNumber')"
      echo "${VER}+${BN}"
    else
      get_yaml "release.version"
      echo
    fi
    ;;
  check)
    node "$SCRIPT_DIR/validate-manifest.mjs"
    VER="$(get_yaml 'release.version')"
    BN="$(get_yaml 'release.buildNumber')"
    APP_DIR_RESOLVED="$MONOREPO_ROOT/$(get_yaml 'app.path' 2>/dev/null || echo 'apps/flutter')"
    if [[ ! -f "$APP_DIR_RESOLVED/pubspec.yaml" ]]; then
      warn "pubspec.yaml not found at $APP_DIR_RESOLVED — skipping pubspec check"
      exit 0
    fi
    PUBSPEC_VER="$(grep -E '^version:' "$APP_DIR_RESOLVED/pubspec.yaml" | sed -E 's/version:[[:space:]]*//; s/[[:space:]]*#.*//; s/"//g' | tr -d "'" | xargs || echo "")"
    EXPECTED="${VER}+${BN}"
    if [[ "$PUBSPEC_VER" != "$EXPECTED" ]]; then
      error "pubspec.yaml version mismatch: got '$PUBSPEC_VER', expected '$EXPECTED'"
      exit 1
    fi
    VERSION_FILE_CONTENT="$(cat "$VERSION_FILE" 2>/dev/null | tr -d ' \n' || echo "")"
    if [[ "$VERSION_FILE_CONTENT" != "$VER" ]]; then
      error "VERSION file mismatch: got '$VERSION_FILE_CONTENT', expected '$VER'"
      exit 1
    fi
    info "Version propagation consistent: $EXPECTED"
    ;;
  sync)
    VER="$(get_yaml 'release.version')"
    BN="$(get_yaml 'release.buildNumber')"
    if ! semver_valid "$VER"; then die "release.version is not semver: $VER"; fi
    APP_DIR_RESOLVED="$MONOREPO_ROOT/$(get_yaml 'app.path' 2>/dev/null || echo 'apps/flutter')"
    EXPECTED="${VER}+${BN}"
    info "Syncing version $EXPECTED -> $APP_DIR_RESOLVED/pubspec.yaml, VERSION, platform configs"
    if [[ -f "$APP_DIR_RESOLVED/pubspec.yaml" ]]; then
      # Update pubspec.yaml `version:` line preserving comments
      if grep -qE '^version:' "$APP_DIR_RESOLVED/pubspec.yaml"; then
        # Use a temp file to avoid BSD vs GNU sed differences
        TMP="$(mktemp)"
        awk -v v="$EXPECTED" 'BEGIN{done=0} /^version:/ && !done {print "version: " v; done=1; next} {print}' "$APP_DIR_RESOLVED/pubspec.yaml" > "$TMP"
        mv "$TMP" "$APP_DIR_RESOLVED/pubspec.yaml"
        info "  pubspec.yaml -> $EXPECTED"
      else
        warn "  pubspec.yaml has no version: line"
      fi
    else
      warn "  pubspec.yaml not found at $APP_DIR_RESOLVED"
    fi
    echo "$VER" > "$VERSION_FILE"
    info "  VERSION -> $VER"

    # Keep release.yaml's app.version/buildNumber in sync when they diverge
    # (both are authoritative for the manifest; we only sync pubspec/VERSION)
    info "Sync complete. Remember: release.yaml is the source of truth — commit both."

    # Validate after sync
    "$SCRIPT_DIR/version.sh" check
    ;;
  bump)
    NEW_VER="${2:-}"
    [[ -n "$NEW_VER" ]] || die "Usage: $0 bump <newVersion>  e.g. $0 bump 1.1.0-rc.1"
    # Strip build metadata if user included it
    BARE_VER="$(echo "$NEW_VER" | sed -E 's/\+.*//')"
    if ! semver_valid "$BARE_VER"; then die "Not semver: $NEW_VER"; fi
    # Determine prerelease and base
    info "Bumping release.yaml version: $(get_yaml 'release.version') -> $BARE_VER"
    # Update release.yaml via node/js-yaml for fidelity
    node -e "
      const fs=require('fs'), path=process.argv[1], nv=process.argv[2];
      const yaml=require('js-yaml');
      let j=yaml.load(fs.readFileSync(path,'utf8'));
      j.release.version=nv;
      j.app.version=nv;
      // bump buildNumber for non-prerelease stable bumps? Keep caller's buildNumber unless they say otherwise
      // For now, keep buildNumber unchanged; caller can bump separately
      fs.writeFileSync(path, yaml.dump(j, {lineWidth:120, noRefs:true}));
    " "$RELEASE_YAML" "$BARE_VER" 2>/dev/null || {
      # fallback: sed update
      TMP="$(mktemp)"
      awk -v nv="$BARE_VER" '
        /^release:/ {in_release=1; in_app=0}
        /^app:/ {in_release=0; in_app=1}
        /^[^[:space:]]/ && !/^release:/ && !/^app:/ {in_release=0; in_app=0}
        in_release && /^[[:space:]]*version:/ {sub(/version:.*/, "version: \"" nv "\""); }
        in_app && /^[[:space:]]*version:/ {sub(/version:.*/, "version: \"" nv "\""); }
        {print}
      ' "$RELEASE_YAML" > "$TMP" && mv "$TMP" "$RELEASE_YAML"
    }
    echo "$BARE_VER" > "$VERSION_FILE"
    info "Bumped to $BARE_VER — now run: ./scripts/version.sh sync"
    ;;
  *)
    die "Unknown command: $CMD (expected get|check|sync|bump)"
    ;;
esac
