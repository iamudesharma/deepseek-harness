#!/usr/bin/env bash
# Top-level wrapper for ergonomics: ./build.sh <platform|all>
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$DIR/scripts/build.sh" "$@"
