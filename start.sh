#!/usr/bin/env bash
set -euo pipefail

# start.sh — one command to run backend + Flutter Web + macOS side-by-side
#
# Backend (dsh host) serves the React frontend at http://127.0.0.1:3080
# Flutter Web runs as a separate web-server at http://127.0.0.1:5001
# Flutter macOS runs as a native desktop app (when --macos is used)
# All hit the SAME backend so you can compare parity in multiple windows.
#
# Usage:
#   ./start.sh                  # backend + Flutter Web (auto-build if needed)
#   ./start.sh --macos          # backend + Flutter Web + Flutter macOS
#   ./start.sh --flutter-device macos  # backend + macOS only
#   ./start.sh --no-open        # don't auto-open browsers
#   ./start.sh --no-build       # skip build even if artifacts look stale
#   ./start.sh --build          # force rebuild
#   ./start.sh --backend-port 3080 --flutter-port 5001
#   ./start.sh --flutter-device chrome   # use Chrome instead of web-server
#   ./start.sh --help
#
# Requirements: pnpm, node ^22.19 || >=24, flutter (or fvm)
# First run does `pnpm run build` (needed for dsh web to have apps/web/dist).

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND_PORT=3080
FLUTTER_PORT=5001
FLUTTER_DEVICE="web-server"  # web-server | chrome | edge | macos | comma-separated list | none
DO_BUILD="auto"         # auto | force | skip
OPEN_BROWSER="true"
SKIP_FLUTTER="false"
RUN_MACOS_SEPARATELY="false"
BACKEND_EXTRA_ARGS=()
FLUTTER_EXTRA_ARGS=()
FLUTTER_DEVICES=()

# ── colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  CYAN="$(printf '\033[36m')"
  RED="$(printf '\033[31m')"
  DIM="$(printf '\033[2m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  GREEN=""; YELLOW=""; CYAN=""; RED=""; DIM=""; BOLD=""; RESET=""
fi

info()  { printf "${GREEN}▸${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${RESET} %s\n" "$*" >&2; }
err()   { printf "${RED}✘${RESET} %s\n" "$*" >&2; }
dim()   { printf "${DIM}%s${RESET}\n" "$*"; }

usage() {
  cat <<EOF
start.sh — one command to run backend + Flutter Web (+ macOS) side-by-side

Backend (dsh host) serves the React frontend at http://127.0.0.1:3080
Flutter Web runs as a separate web-server at http://127.0.0.1:5001
Flutter macOS runs as a native desktop app when --macos is used.
All hit the SAME backend so you can compare parity in multiple windows.

Usage:
  ./start.sh                  # backend + Flutter Web
  ./start.sh --macos          # backend + Flutter Web + Flutter macOS  ← recommended on macOS
  ./start.sh --no-open        # don't auto-open browsers
  ./start.sh --no-build       # skip build even if artifacts look stale
  ./start.sh --build          # force rebuild
  ./start.sh --backend-port 3080 --flutter-port 5001
  ./start.sh --flutter-device chrome   # use Chrome instead of web-server
  ./start.sh --flutter-device macos    # macOS only (no web)
  ./start.sh --flutter-device web-server,macos  # explicit both
  ./start.sh --no-flutter     # backend + React only
  ./start.sh --help

Requirements: pnpm, node ^22.19 || >=24, flutter (or fvm)
First run does 'pnpm run build' (needed for dsh web to have apps/web/dist).

Options:
  --backend-port <port>    backend (dsh web) listen port (default: 3080)
  --flutter-port <port>    flutter web-server port (default: 5001)
  --flutter-device <dev>   flutter device: web-server (default) | chrome | edge | macos
                           can be comma-separated or repeated: web-server,macos
  --macos                  shorthand for --flutter-device web-server,macos (both)
  --with-macos             alias for --macos
  --no-flutter             skip Flutter entirely (backend + React only)
  --build                  force pnpm run build before starting
  --no-build               skip build check
  --no-open                don't auto-open browsers (default opens both URLs)
  --kill                   kill any process on backend/flutter ports before start
  --backend-arg <arg>      extra arg forwarded to 'pnpm dsh web' (repeatable)
  --flutter-arg <arg>      extra arg forwarded to 'flutter run' (repeatable)
  -h, --help               show this help

Examples:
  ./start.sh --macos
  ./start.sh --no-open --backend-port 3080 --flutter-port 5001
  ./start.sh --no-flutter --no-open
  ./start.sh --build --macos
  ./start.sh --flutter-device chrome
  ./start.sh --backend-arg "--trusted-host=192.168.1.10:3080"

URLs after start:
  React (via backend):  http://127.0.0.1:3080
  Flutter Web:          http://127.0.0.1:5001  → talks to http://127.0.0.1:3080
  Flutter macOS:        native window (when --macos)
  Flutter baseUrl: compile-time DSH_HOST_URL (see apps/flutter/lib/src/core/connection/connection_client.dart:278)

EOF
}

# ── arg parse ────────────────────────────────────────────────────────────────
KILL_EXISTING="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend-port)   BACKEND_PORT="$2"; shift 2 ;;
    --flutter-port)   FLUTTER_PORT="$2"; shift 2 ;;
    --flutter-device) FLUTTER_DEVICE="$2"; shift 2 ;;
    --macos|--with-macos) RUN_MACOS_SEPARATELY="true"; shift ;;
    --no-flutter)     SKIP_FLUTTER="true"; shift ;;
    --build)          DO_BUILD="force"; shift ;;
    --no-build)       DO_BUILD="skip"; shift ;;
    --no-open)        OPEN_BROWSER="false"; shift ;;
    --kill)           KILL_EXISTING="true"; shift ;;
    --backend-arg)    BACKEND_EXTRA_ARGS+=("$2"); shift 2 ;;
    --flutter-arg)    FLUTTER_EXTRA_ARGS+=("$2"); shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; break ;;
    *) err "Unknown flag: $1 (see --help)"; exit 2 ;;
  esac
done

# Normalize flutter devices: support --macos shorthand and comma-separated values
if [[ "$RUN_MACOS_SEPARATELY" == "true" ]]; then
  if [[ "$FLUTTER_DEVICE" == "web-server" ]]; then
    FLUTTER_DEVICE="web-server,macos"
  elif [[ "$FLUTTER_DEVICE" != *"macos"* ]]; then
    FLUTTER_DEVICE="${FLUTTER_DEVICE},macos"
  fi
fi

# Split comma-separated FLUTTER_DEVICE into array FLUTTER_DEVICES
IFS=',' read -ra FLUTTER_DEVICES <<< "$FLUTTER_DEVICE"
# Trim whitespace and filter empty
FLUTTER_DEVICES_TRIMMED=()
for d in "${FLUTTER_DEVICES[@]}"; do
  d="$(echo "$d" | xargs)"
  if [[ -n "$d" && "$d" != "none" ]]; then
    FLUTTER_DEVICES_TRIMMED+=("$d")
  fi
done
FLUTTER_DEVICES=("${FLUTTER_DEVICES_TRIMMED[@]}")

# If --no-flutter, clear devices
if [[ "$SKIP_FLUTTER" == "true" ]]; then
  FLUTTER_DEVICES=()
fi

# ── env setup: nvm / fvm / pnpm ──────────────────────────────────────────────
# Try to source nvm if pnpm/node not in PATH (common with nvm installs)
if ! command -v pnpm >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
  if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
  fi
  # Also try common pnpm home
  if [[ -d "$HOME/Library/pnpm" ]]; then
    export PATH="$HOME/Library/pnpm:$PATH"
  fi
fi

# Resolve flutter command: prefer plain flutter, fallback to fvm
FLUTTER_CMD="flutter"
if ! command -v flutter >/dev/null 2>&1; then
  if command -v fvm >/dev/null 2>&1; then
    FLUTTER_CMD="fvm flutter"
    warn "flutter not in PATH, using 'fvm flutter' instead"
  elif [[ -x "$HOME/fvm/default/bin/flutter" ]]; then
    FLUTTER_CMD="$HOME/fvm/default/bin/flutter"
    warn "flutter not in PATH, using '$FLUTTER_CMD' instead"
  elif [[ -x "/Users/$USER/fvm/default/bin/flutter" ]]; then
    FLUTTER_CMD="/Users/$USER/fvm/default/bin/flutter"
    warn "flutter not in PATH, using '$FLUTTER_CMD' instead"
  fi
fi

# ── preflight ────────────────────────────────────────────────────────────────
need_cmd() {
  local cmd="$1"
  local base_cmd
  base_cmd="$(echo "$cmd" | awk '{print $1}')"
  if ! command -v "$base_cmd" >/dev/null 2>&1; then
    err "Missing required command: $base_cmd"
    case "$base_cmd" in
      pnpm)    dim "  install: npm i -g pnpm  or  brew install pnpm" ;;
      flutter|fvm) dim "  install: https://docs.flutter.dev/get-started/install  or  brew install --cask flutter  or  dart pub global activate fvm" ;;
      node)    dim "  install: https://nodejs.org (need ^22.19 || >=24)  or  nvm install 22" ;;
    esac
    exit 1
  fi
}
need_cmd node
need_cmd pnpm
# Only check flutter if we actually need it
if [[ ${#FLUTTER_DEVICES[@]} -gt 0 ]]; then
  need_cmd "$FLUTTER_CMD"
fi

# Quick node version check (informational)
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" -lt 22 ]]; then
  warn "node $(node -v) is older than required ^22.19 || >=24 — build may fail"
fi

if [[ ! -f "$REPO_ROOT/pnpm-workspace.yaml" ]]; then
  err "Run ./start.sh from the repository root (pnpm-workspace.yaml not found at $REPO_ROOT)"
  exit 1
fi

# Port helpers
port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1
  else
    (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
  fi
}
kill_port() {
  local port="$1"
  local label="$2"
  if port_in_use "$port"; then
    warn "Killing existing process on $label port $port (--kill)…"
    if command -v lsof >/dev/null 2>&1; then
      lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | xargs kill -9 2>/dev/null || true
    else
      # shellcheck disable=SC2009
      ps aux | grep -E ":$port" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null || true
    fi
    sleep 0.5
  fi
}
if [[ "$KILL_EXISTING" == "true" ]]; then
  kill_port "$BACKEND_PORT" "backend"
  for dev in "${FLUTTER_DEVICES[@]}"; do
    if [[ "$dev" == "web-server" ]]; then
      kill_port "$FLUTTER_PORT" "flutter web-server"
    fi
  done
else
  if port_in_use "$BACKEND_PORT"; then
    warn "Port $BACKEND_PORT already in use — backend may fail to bind (try --backend-port 3081 or --kill)"
  fi
  for dev in "${FLUTTER_DEVICES[@]}"; do
    if [[ "$dev" == "web-server" ]] && port_in_use "$FLUTTER_PORT"; then
      warn "Port $FLUTTER_PORT already in use — flutter web-server may fail (try --flutter-port 5002 or --kill)"
    fi
  done
fi

# ── build gate ───────────────────────────────────────────────────────────────
needs_build() {
  if [[ ! -f "$REPO_ROOT/apps/web/dist/index.html" ]]; then return 0; fi
  if [[ ! -d "$REPO_ROOT/apps/cli/lib" ]]; then return 0; fi
  return 1
}

if [[ "$DO_BUILD" == "force" ]]; then
  info "Building (forced --build)…"
  (cd "$REPO_ROOT" && pnpm run build)
elif [[ "$DO_BUILD" == "skip" ]]; then
  dim "Skipping build (--no-build)"
elif needs_build; then
  info "Build artifacts missing — running 'pnpm run build' (first run, one-time)…"
  dim "  Tip: next time use --no-build to skip this check"
  (cd "$REPO_ROOT" && pnpm run build)
else
  dim "Build artifacts present — skipping build (use --build to force)"
fi

# Ensure flutter pubs are fetched (fast no-op if already fetched)
if [[ ${#FLUTTER_DEVICES[@]} -gt 0 && ! -f "$REPO_ROOT/apps/flutter/.dart_tool/package_config.json" ]]; then
  info "Fetching Flutter packages (first run)…"
  (cd "$REPO_ROOT/apps/flutter" && $FLUTTER_CMD pub get)
fi

BACKEND_URL="http://127.0.0.1:${BACKEND_PORT}"
FLUTTER_URL="http://127.0.0.1:${FLUTTER_PORT}"

# ── launch ───────────────────────────────────────────────────────────────────
BACKEND_PID=""
FLUTTER_PIDS=()
TMPDIR_LOGS=""
cleanup() {
  local code=$?
  printf "\n"
  info "Shutting down…"
  for pid in "${FLUTTER_PIDS[@]:-}"; do
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      pkill -P "$pid" 2>/dev/null || true
    fi
  done
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    kill "$BACKEND_PID" 2>/dev/null || true
    pkill -P "$BACKEND_PID" 2>/dev/null || true
  fi
  sleep 0.5
  for pid in "${FLUTTER_PIDS[@]:-}"; do
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
  done
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then kill -9 "$BACKEND_PID" 2>/dev/null || true; fi
  for pid in "${FLUTTER_PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
  wait "$BACKEND_PID" 2>/dev/null || true
  if [[ -n "${TMPDIR_LOGS:-}" && -d "$TMPDIR_LOGS" ]]; then
    dim "Logs kept at: $TMPDIR_LOGS/"
    ls -1 "$TMPDIR_LOGS" 2>/dev/null | while read -r f; do dim "  $TMPDIR_LOGS/$f"; done
  fi
  if [[ $code -ne 0 ]]; then
    dim "Exit code: $code"
  fi
}
trap cleanup INT TERM EXIT

TMPDIR_LOGS="$(mktemp -d 2>/dev/null || mktemp -d -t dsh-start)"
BACKEND_LOG="$TMPDIR_LOGS/backend.log"
touch "$BACKEND_LOG"

# Helper: prefix each line with a colored tag
prefix_stream() {
  local tag="$1" color="$2" logfile="$3"
  tee -a "$logfile" | while IFS= read -r line; do
    printf "${color}[%s]${RESET} %s\n" "$tag" "$line"
  done
}

# Helper: wait for http 200/401/303 with timeout (401/303 means backend is up but needs token)
wait_for_http() {
  local url="$1" label="$2" timeout="${3:-60}"
  local i=0
  while [[ $i -lt $timeout ]]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo 000)
    if [[ "$code" == "200" || "$code" == "401" || "$code" == "303" || "$code" == "302" ]]; then
      return 0
    fi
    sleep 1
    i=$((i+1))
    if [[ $((i % 10)) -eq 0 ]]; then
      dim "  still waiting for $label ($i/${timeout}s) — $url (last code $code)"
      if [[ "$label" == Flutter* ]]; then
        dim "  (first Flutter web compile can take 60-90s; check $TMPDIR_LOGS/flutter-*.log)"
      fi
    fi
  done
  return 1
}

open_url() {
  local url="$1"
  if [[ "$OPEN_BROWSER" != "true" ]]; then return 0; fi
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
}

# ── 1) backend (dsh web) — serves React at BACKEND_URL ──────────────────────
info "Starting backend (dsh web) on $BACKEND_URL …"
dim "  logs: $BACKEND_LOG"

# Auto-add trusted-host for flutter web so CORS is not needed manually
BACKEND_TRUST_ARGS=()
for dev in "${FLUTTER_DEVICES[@]}"; do
  if [[ "$dev" == "web-server" ]]; then
    BACKEND_TRUST_ARGS+=("--trusted-host" "127.0.0.1:${FLUTTER_PORT}" "--trusted-host" "localhost:${FLUTTER_PORT}")
    break
  fi
done

set +e
set +u
(
  cd "$REPO_ROOT"
  pnpm dsh web --port "$BACKEND_PORT" --no-open "${BACKEND_TRUST_ARGS[@]}" ${BACKEND_EXTRA_ARGS[@]+"${BACKEND_EXTRA_ARGS[@]}"} 2>&1
) | prefix_stream "backend" "$CYAN" "$BACKEND_LOG" &
BACKEND_PID=$!
set -u
set -e

info "Waiting for backend to be ready…"
if ! wait_for_http "$BACKEND_URL/" "backend $BACKEND_URL" 90; then
  err "Backend did not become ready at $BACKEND_URL within 90s"
  dim "  Check $BACKEND_LOG for errors (port in use? missing DEEPSEEK_API_KEY is OK for UI — only agent calls need it)"
  printf "\n${DIM}--- backend.log tail ---${RESET}\n"
  tail -n 80 "$BACKEND_LOG" 2>/dev/null || true
  printf "${DIM}--- end tail ---${RESET}\n"
  exit 1
fi
if ! curl -fsS --max-time 3 "$BACKEND_URL/" 2>/dev/null | grep -q "__DSH_BOOT__"; then
  warn "Backend responded but __DSH_BOOT__ not found in index — React shell may show blank (try 'pnpm run build' and restart)"
fi
info "Backend ready at ${BOLD}${BACKEND_URL}${RESET}  ${DIM}(React UI)${RESET}"

# Extract the authenticated URL (with ?token=) for native Flutter.
# Native `dart:io` has no automatic cookie jar, so it must perform
# `GET /?token=` → `Set-Cookie: dsh-auth-*` and replay `Cookie` on every
# `/api/*` and `ws://` request. That token is printed as
# `dsh web: http://127.0.0.1:3080/?token=...` — capture it for macOS.
# Poll until the token appears because `pnpm dsh web` prints it asynchronously
# after `wait_for_http` already succeeded (the index is served before the log
# line is flushed through `prefix_stream`/`tee`). The previous 5×0.5s poll was
# too short when the backend needed >3s to print; extend to 20×0.5s (10s) and
# block launch of native until the token is ready — native cannot auth without
# it and would otherwise spin `401`/`GEN timeout` forever (see macOS reconnect
# bug after trajectory hot-reload).
AUTHENTICATED_URL="$BACKEND_URL"
for _ in {1..20}; do
  if grep -q "dsh web:" "$BACKEND_LOG" 2>/dev/null; then
    EXTRACTED=$(grep -oE 'dsh web: http://[^[:space:]]+token=[^[:space:]\)]+' "$BACKEND_LOG" 2>/dev/null | head -n1 | sed 's/dsh web: //' | tr -d '()')
    if [[ -n "${EXTRACTED:-}" ]]; then
      AUTHENTICATED_URL="$EXTRACTED"
      dim "  authenticated URL for native: $AUTHENTICATED_URL"
      break
    fi
  fi
  sleep 0.5
done
if [[ "$AUTHENTICATED_URL" == "$BACKEND_URL" ]]; then
  warn "Failed to extract authenticated URL with ?token= for native (backend log had no \"dsh web:\" line after 10s); native will likely 401 — check $BACKEND_LOG"
fi

# ── 2) flutter — one or more devices ────────────────────────────────────────
if [[ ${#FLUTTER_DEVICES[@]} -eq 0 ]]; then
  dim "Skipping Flutter (--no-flutter)"
else
  for FLUTTER_DEVICE in "${FLUTTER_DEVICES[@]}"; do
    # Validate device
    if [[ "$FLUTTER_DEVICE" != "web-server" && "$FLUTTER_DEVICE" != "chrome" && "$FLUTTER_DEVICE" != "edge" && "$FLUTTER_DEVICE" != "macos" ]]; then
      warn "Unknown --flutter-device '$FLUTTER_DEVICE' — trying anyway"
    fi

    FLUTTER_LOG="$TMPDIR_LOGS/flutter-${FLUTTER_DEVICE}.log"
    touch "$FLUTTER_LOG"

    if [[ "$FLUTTER_DEVICE" == "web-server" ]]; then
      info "Starting Flutter Web on $FLUTTER_URL → backend $BACKEND_URL …"
      dim "  logs: $FLUTTER_LOG"
      dim "  device: $FLUTTER_DEVICE  •  dart-define DSH_HOST_URL=$BACKEND_URL"
      set +e
      set +u
      (
        cd "$REPO_ROOT/apps/flutter"
        $FLUTTER_CMD run \
          -d web-server \
          --web-port "$FLUTTER_PORT" \
          --web-hostname 127.0.0.1 \
          --dart-define="DSH_HOST_URL=${BACKEND_URL}" \
          ${FLUTTER_EXTRA_ARGS[@]+"${FLUTTER_EXTRA_ARGS[@]}"} 2>&1
      ) | prefix_stream "flutter:web" "$GREEN" "$FLUTTER_LOG" &
      FLUTTER_PIDS+=($!)
      set -u
      set -e

      info "Waiting for Flutter Web to be ready (first compile 60-90s)…"
      if ! wait_for_http "$FLUTTER_URL/" "Flutter $FLUTTER_URL" 180; then
        err "Flutter Web did not become ready at $FLUTTER_URL within 180s"
        dim "  Check $FLUTTER_LOG — common causes: port in use, 'flutter pub get' needed, Dart compile error"
        printf "\n${DIM}--- flutter-web.log tail ---${RESET}\n"
        tail -n 120 "$FLUTTER_LOG" 2>/dev/null || true
        printf "${DIM}--- end tail ---${RESET}\n"
        warn "Continuing with backend only — fix Flutter Web and re-run ./start.sh"
        # Remove the failed pid from tracking (it may have already exited)
        unset 'FLUTTER_PIDS[${#FLUTTER_PIDS[@]}-1]'
      else
        info "Flutter Web ready at ${BOLD}${FLUTTER_URL}${RESET}  ${DIM}(→ $BACKEND_URL)${RESET}"
      fi

    elif [[ "$FLUTTER_DEVICE" == "macos" ]]; then
      # Re-extract token just before macOS launch when web-server was first:
      # web-server launch consumed the post-`wait_for_http` window where the
      # token line finally appeared. Re-poll here so macOS never launches with
      # a token-less URL (the previous bug that caused `GEN timeout`/`401`).
      if [[ "$AUTHENTICATED_URL" == "$BACKEND_URL" ]]; then
        for _ in {1..10}; do
          if grep -q "dsh web:" "$BACKEND_LOG" 2>/dev/null; then
            EXTRACTED=$(grep -oE 'dsh web: http://[^[:space:]]+token=[^[:space:]\)]+' "$BACKEND_LOG" 2>/dev/null | head -n1 | sed 's/dsh web: //' | tr -d '()')
            if [[ -n "${EXTRACTED:-}" ]]; then
              AUTHENTICATED_URL="$EXTRACTED"
              dim "  (late) authenticated URL for native: $AUTHENTICATED_URL"
              break
            fi
          fi
          sleep 0.5
        done
      fi
      info "Starting Flutter macOS (native) → backend $BACKEND_URL …"
      dim "  logs: $FLUTTER_LOG"
      dim "  device: $FLUTTER_DEVICE  •  dart-define DSH_HOST_URL=$AUTHENTICATED_URL"
      # macOS needs a built host; ensure `pod install` hint if needed
      if [[ ! -d "$REPO_ROOT/apps/flutter/macos/Pods" && -f "$REPO_ROOT/apps/flutter/macos/Podfile" ]]; then
        dim "  (first macOS run may need 'cd apps/flutter && pod install' — will try anyway)"
      fi
      set +e
      set +u
      (
        cd "$REPO_ROOT/apps/flutter"
        $FLUTTER_CMD run \
          -d macos \
          --dart-define="DSH_HOST_URL=${AUTHENTICATED_URL}" \
          ${FLUTTER_EXTRA_ARGS[@]+"${FLUTTER_EXTRA_ARGS[@]}"} 2>&1
      ) | prefix_stream "flutter:macos" "$GREEN" "$FLUTTER_LOG" &
      FLUTTER_PIDS+=($!)
      set -u
      set -e
      # macOS launch is a native window, not an http endpoint — just give it a moment
      sleep 3
      # Check the process is still alive (did not crash immediately)
      LAST_PID="${FLUTTER_PIDS[${#FLUTTER_PIDS[@]}-1]}"
      if kill -0 "$LAST_PID" 2>/dev/null; then
        info "Flutter macOS launched (pid $LAST_PID) — check the native window"
        dim "  (macOS hot reload: press 'r' in this terminal for web, or focus the macOS terminal)"
      else
        err "Flutter macOS exited quickly — check $FLUTTER_LOG"
        printf "\n${DIM}--- flutter-macos.log tail ---${RESET}\n"
        tail -n 80 "$FLUTTER_LOG" 2>/dev/null || true
        printf "${DIM}--- end tail ---${RESET}\n"
        warn "Continuing — backend and web may still be running"
        unset 'FLUTTER_PIDS[${#FLUTTER_PIDS[@]}-1]'
      fi

    else
      # chrome / edge / other
      info "Starting Flutter on device '$FLUTTER_DEVICE' → backend $BACKEND_URL …"
      dim "  logs: $FLUTTER_LOG"
      set +e
      set +u
      (
        cd "$REPO_ROOT/apps/flutter"
        $FLUTTER_CMD run \
          -d "$FLUTTER_DEVICE" \
          --dart-define="DSH_HOST_URL=${BACKEND_URL}" \
          ${FLUTTER_EXTRA_ARGS[@]+"${FLUTTER_EXTRA_ARGS[@]}"} 2>&1
      ) | prefix_stream "flutter:$FLUTTER_DEVICE" "$GREEN" "$FLUTTER_LOG" &
      FLUTTER_PIDS+=($!)
      set -u
      set -e
      sleep 3
      info "Flutter launching on device '$FLUTTER_DEVICE' — check the opened window"
      dim "  (chrome/edge picks its own port; look for the URL in [flutter:$FLUTTER_DEVICE] logs above)"
    fi
  done
fi

# ── summary + open ───────────────────────────────────────────────────────────
printf "\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD}  DeepSeek Harness — side-by-side comparison${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "  ${CYAN}React${RESET}  (via backend)  →  ${BOLD}${BACKEND_URL}${RESET}\n"
if [[ ${#FLUTTER_PIDS[@]} -eq 0 && ${#FLUTTER_DEVICES[@]} -eq 0 ]]; then
  printf "  ${GREEN}Flutter${RESET}               →  ${DIM}skipped (--no-flutter)${RESET}\n"
else
  for idx in "${!FLUTTER_DEVICES[@]}"; do
    dev="${FLUTTER_DEVICES[$idx]}"
    pid="${FLUTTER_PIDS[$idx]:-?}"
    if [[ "$dev" == "web-server" ]]; then
      printf "  ${GREEN}Flutter${RESET} Web             →  ${BOLD}${FLUTTER_URL}${RESET}  ${DIM}(DSH_HOST_URL=${BACKEND_URL})${RESET}\n"
    elif [[ "$dev" == "macos" ]]; then
      printf "  ${GREEN}Flutter${RESET} macOS           →  ${BOLD}native window${RESET}  ${DIM}(DSH_HOST_URL=${AUTHENTICATED_URL}, pid ${pid})${RESET}\n"
    else
      printf "  ${GREEN}Flutter${RESET} (${dev})    →  ${DIM}see [flutter:${dev}] logs for URL  (DSH_HOST_URL=${BACKEND_URL})${RESET}\n"
    fi
  done
fi
printf "  ${DIM}Backend logs: $BACKEND_LOG${RESET}\n"
for dev in "${FLUTTER_DEVICES[@]}"; do
  printf "  ${DIM}Flutter ($dev) logs: $TMPDIR_LOGS/flutter-${dev}.log${RESET}\n"
done
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${DIM}  Tip: open both URLs in two tabs/monitors to compare parity.${RESET}\n"
printf "${DIM}  Press Ctrl+C to stop all.  --help for ports/build options.${RESET}\n"
printf "${DIM}  Rebuild React after edits: pnpm run build  (or pnpm run dev:web for HMR)${RESET}\n"
printf "${DIM}  Rebuild Flutter after edits: hot reload is automatic (r in terminal)${RESET}\n"
printf "${DIM}  Single-command macOS+Web: ./start.sh --macos  (or --flutter-device web-server,macos)${RESET}\n"
printf "\n"

if [[ "$OPEN_BROWSER" == "true" ]]; then
  info "Opening browsers…"
  open_url "$AUTHENTICATED_URL"
  # Only auto-open web-server (macos is a native window, already visible)
  for dev in "${FLUTTER_DEVICES[@]}"; do
    if [[ "$dev" == "web-server" ]]; then
      sleep 0.8
      open_url "$FLUTTER_URL"
      break
    fi
  done
else
  dim "(--no-open) Skipping auto-open — open the URLs above manually"
fi

# ── keep running until Ctrl+C ────────────────────────────────────────────────
trap 'cleanup; exit 0' INT TERM
trap - EXIT

info "Running — press ${BOLD}Ctrl+C${RESET} to stop all"
# Poll for child liveness (bash 3.2 compat — no wait -n)
while true; do
  BACKEND_ALIVE="true"
  if [[ -n "${BACKEND_PID:-}" ]] && ! kill -0 "$BACKEND_PID" 2>/dev/null; then BACKEND_ALIVE="false"; fi

  FLUTTER_ANY_ALIVE="false"
  for pid in "${FLUTTER_PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then FLUTTER_ANY_ALIVE="true"; break; fi
  done
  if [[ ${#FLUTTER_PIDS[@]} -eq 0 ]]; then FLUTTER_ANY_ALIVE="true"; fi # no flutter = don't trigger

  if [[ "$BACKEND_ALIVE" == "false" && "$FLUTTER_ANY_ALIVE" == "false" ]]; then
    warn "All processes exited — stopping"
    break
  fi
  if [[ "$BACKEND_ALIVE" == "false" ]]; then
    err "Backend exited — React URL will be down (see $BACKEND_LOG)"
    dim "  Flutter may still be running — Ctrl+C to stop"
    wait "$BACKEND_PID" 2>/dev/null || true
    BACKEND_PID=""
    if [[ "$FLUTTER_ANY_ALIVE" == "true" ]]; then
      for pid in "${FLUTTER_PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
    fi
    break
  fi
  # Check if any flutter pid died
  DEAD_FLUTTER=()
  for pid in "${FLUTTER_PIDS[@]:-}"; do
    if ! kill -0 "$pid" 2>/dev/null; then DEAD_FLUTTER+=("$pid"); fi
  done
  if [[ ${#DEAD_FLUTTER[@]} -gt 0 && ${#FLUTTER_PIDS[@]} -gt 0 ]]; then
    # If at least one flutter died but others still alive, just warn
    if [[ "$FLUTTER_ANY_ALIVE" == "false" ]]; then
      warn "Flutter exited — Flutter URLs will be down (see $TMPDIR_LOGS/flutter-*.log)"
      dim "  Backend still running at $BACKEND_URL — Ctrl+C to stop"
      for pid in "${FLUTTER_PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
      FLUTTER_PIDS=()
      wait "$BACKEND_PID" 2>/dev/null || true
      break
    fi
  fi
  sleep 1
done

cleanup
