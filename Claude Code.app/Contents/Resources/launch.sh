#!/bin/bash
set -uo pipefail

CLAUDE_TEAM_ID="Q6L2SF6YDW"
CLAUDE_MANIFEST_BASE="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

TEMP_FILES=()
SPINNER_PID=""
cleanup() {
  local pid="$SPINNER_PID"
  SPINNER_PID=""
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do rm -f "$f"; done
}
trap cleanup EXIT

# ── UI ───────────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

print_header() {
  echo ""
  echo -e "${BOLD}  Claude Code · Basecamp${RESET}"
  echo "  ──────────────────────────────────────────"
  echo ""
}

# Print a step label and leave a trailing space for the spinner to occupy
begin_step() {
  printf "  %-44s " "$1"
}

# Start a background spinner on the current line (call after begin_step)
start_spinner() {
  (
    local i=0 frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while true; do
      printf "\b${frames:$i:1}"
      i=$(( (i + 1) % ${#frames} ))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
}

# Stop the spinner and print ✓ or ✗ based on exit code
stop_spinner() {
  local code=${1:-0}
  local pid="$SPINNER_PID"
  SPINNER_PID=""
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  fi
  printf "\b"
  if [[ $code -eq 0 ]]; then
    echo -e "${GREEN}✓${RESET}"
  else
    echo -e "${RED}✗${RESET}"
  fi
}

support_exit() {
  echo ""
  echo -e "  ${RED}Something went wrong.${RESET} Contact IT support: itteam@northcoastchurch.com"
  echo ""
  read -r -p "  Press Enter to close..."
  exit 1
}

# ── Core ─────────────────────────────────────────────────────────────────────

refresh_path() {
  export PATH="$PATH:$HOME/.local/bin"
  [ -f "$HOME/.profile" ] && source "$HOME/.profile" 2>/dev/null || true
}

verify_claude() {
  local bin real_bin version platform manifest checksum actual_checksum
  bin=$(command -v claude) || return 1

  # Resolve the real binary (installer puts versioned binary in ~/.local/share/claude/versions/)
  real_bin=$(codesign -dv "$bin" 2>&1 | awk -F= '/^Executable/{print $2}')
  [[ -z "$real_bin" ]] && real_bin="$bin"

  if ! codesign --verify --strict "$real_bin" 2>/dev/null; then
    echo "Invalid signature on claude binary."
    return 1
  fi

  local team
  team=$(codesign -dv "$real_bin" 2>&1 | awk -F= '/TeamIdentifier/{print $2}')
  if [[ "$team" != "$CLAUDE_TEAM_ID" ]]; then
    echo "Unexpected team ID '$team' on claude binary (expected '$CLAUDE_TEAM_ID')."
    return 1
  fi

  version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [[ -z "$version" ]]; then
    echo "Could not determine claude version."
    return 1
  fi

  local arch
  arch=$(uname -m)
  [[ "$arch" == "x86_64" ]] && arch="x64"
  platform="darwin-${arch}"

  case "$platform" in
    darwin-arm64|darwin-x64) ;;
    *)
      echo "Unsupported platform '$platform'."
      return 1
      ;;
  esac

  manifest=$(curl -fsSL --max-time 30 "${CLAUDE_MANIFEST_BASE}/${version}/manifest.json" 2>/dev/null)
  if [[ -z "$manifest" ]]; then
    echo "Could not fetch release manifest for v${version}."
    return 1
  fi

  checksum=$(python3 -c "
import json, sys
m = json.loads(sys.stdin.read())
p = m.get('platforms', {}).get(sys.argv[1], {})
print(p.get('checksum', ''))
" "$platform" <<< "$manifest")

  if [[ -z "$checksum" ]]; then
    echo "No checksum in manifest for platform '$platform'."
    return 1
  fi

  actual_checksum=$(shasum -a 256 "$real_bin" | awk '{print $1}')
  if [[ "$actual_checksum" != "$checksum" ]]; then
    echo "Checksum mismatch on claude binary."
    echo "  Expected: $checksum"
    echo "  Got:      $actual_checksum"
    return 1
  fi
}

BASECAMP_TEAM_ID="2WNYUYRS7G"

verify_basecamp() {
  local bin
  bin=$(command -v basecamp) || return 1
  if ! codesign --verify --strict "$bin" 2>/dev/null; then
    echo "Invalid signature on basecamp binary."
    return 1
  fi

  local authority
  authority=$(codesign -dv --verbose=4 "$bin" 2>&1 | grep "^Authority=Developer ID Application:" | head -1)
  if [[ "$authority" != *"$BASECAMP_TEAM_ID"* ]]; then
    echo "Unexpected signer on basecamp binary: $authority"
    return 1
  fi
}

# Download, scan, and install a tool from a URL
# Usage: install_tool "Label" "url" "binary-name"
install_tool() {
  local label="$1" url="$2" bin_name="$3"
  local log installer
  log=$(mktemp "${TMPDIR:-/tmp}/install-log.XXXXXX")
  TEMP_FILES+=("$log")

  begin_step "Downloading ${label}..."
  start_spinner
  installer=$(mktemp "${TMPDIR:-/tmp}/installer.XXXXXX.sh")
  TEMP_FILES+=("$installer")
  curl -fsSL --max-time 60 "$url" -o "$installer" >"$log" 2>&1
  local code=$?
  stop_spinner $code
  if [[ $code -ne 0 ]]; then
    echo ""; cat "$log"; support_exit
  fi

  begin_step "Scanning with Microsoft Defender..."
  start_spinner
  if ! command -v mdatp &>/dev/null; then
    stop_spinner 1
    echo "  Microsoft Defender (mdatp) not found."
    support_exit
  fi
  mdatp scan custom --path "$installer" >"$log" 2>&1
  code=$?
  stop_spinner $code

  # Always check for threats in output, regardless of exit code (S1)
  local threats
  threats=$(grep -oE '[0-9]+ threats?' "$log" | grep -oE '^[0-9]+')
  if [[ "${threats:-0}" -gt 0 ]]; then
    echo "  Defender detected ${threats} threat(s)."
    support_exit
  fi
  if [[ $code -ne 0 ]]; then
    echo "  Defender scan failed."
    support_exit
  fi

  # Installer needs full shell capabilities (filesystem writes, PATH modification)
  begin_step "Installing ${label}..."
  start_spinner
  bash "$installer" >"$log" 2>&1
  code=$?
  stop_spinner $code
  if [[ $code -ne 0 ]]; then
    echo ""; cat "$log"; support_exit
  fi

  rm -f "$installer" "$log"
  refresh_path

  if ! command -v "$bin_name" &>/dev/null; then
    echo "  Installation finished but '${bin_name}' was not found in PATH."
    support_exit
  fi
}

# Check if basecamp auth status JSON indicates authenticated
is_authenticated() {
  local json="$1"
  python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get('data',{}).get('authenticated') or d.get('authenticated') else 1)" <<< "$json" 2>/dev/null
}

# ── Main ─────────────────────────────────────────────────────────────────────

print_header

# Detect what setup is needed
needs_claude=false
needs_basecamp=false
needs_auth=false
needs_folder=false

command -v claude &>/dev/null   || needs_claude=true
command -v basecamp &>/dev/null || needs_basecamp=true

if ! $needs_basecamp; then
  auth_check=$(basecamp auth status --json 2>/dev/null || true)
  is_authenticated "$auth_check" || needs_auth=true
fi

[ -d "$HOME/Claude" ] || needs_folder=true

if $needs_claude || $needs_basecamp || $needs_auth || $needs_folder; then

  echo -e "  ${BOLD}First-time setup${RESET}"
  echo "  This app uses Claude Code and the Basecamp CLI to let you"
  echo "  manage Basecamp in plain language. The following will be set up:"
  echo ""
  $needs_claude   && echo "    • Install Claude Code"
  $needs_basecamp && echo "    • Install Basecamp CLI"
  $needs_auth     && echo "    • Connect your Basecamp account"
  $needs_folder   && echo "    • Create the ~/Claude workspace"
  echo ""
  read -r -p "  Ready to continue? [y/n]: " answer
  echo ""

  case "$answer" in
    [Yy]) ;;
    *)
      echo "  No changes were made. You can relaunch this app whenever you're ready."
      echo ""
      exit 0
      ;;
  esac

  $needs_claude   && install_tool "Claude Code"  "https://claude.ai/install.sh"     "claude"
  $needs_basecamp && install_tool "Basecamp CLI" "https://basecamp.com/install-cli" "basecamp"

  if $needs_auth; then
    echo ""
    echo -e "  ${BOLD}Connect your Basecamp account${RESET}"
    echo "  Your browser will open — sign in and return here when done."
    echo ""
    basecamp auth login
    echo ""
    auth_check=$(basecamp auth status --json 2>/dev/null || true)
    if ! is_authenticated "$auth_check"; then
      echo "  Basecamp authentication failed."
      support_exit
    fi
    echo -e "  ${GREEN}✓${RESET} Basecamp account connected."
  fi

  if $needs_folder; then
    begin_step "Creating ~/Claude workspace..."
    start_spinner
    mkdir -p "$HOME/Claude" >/dev/null 2>&1
    code=$?
    stop_spinner $code
    if [[ $code -ne 0 ]]; then
      echo "  Could not create ~/Claude."
      support_exit
    fi
  fi

  echo ""
  echo -e "  ${GREEN}${BOLD}Setup complete!${RESET} Starting Claude Code..."
  sleep 1
  echo ""

fi

# Check for updates at most once per day (non-fatal — current version is verified below regardless)
UPDATE_STAMP="$HOME/.claude/.last_update_check"
needs_update=false
if [[ ! -f "$UPDATE_STAMP" ]]; then
  needs_update=true
else
  last_check=$(stat -f %m "$UPDATE_STAMP" 2>/dev/null || echo 0)
  now=$(date +%s)
  if (( now - last_check > 86400 )); then
    needs_update=true
  fi
fi

if $needs_update; then
  begin_step "Checking for updates..."
  start_spinner
  claude update >/dev/null 2>&1 &
  pid_claude=$!
  basecamp upgrade >/dev/null 2>&1 &
  pid_basecamp=$!
  wait "$pid_claude" "$pid_basecamp" 2>/dev/null
  stop_spinner 0
  mkdir -p "$(dirname "$UPDATE_STAMP")" 2>/dev/null
  touch "$UPDATE_STAMP"
fi

# Verify both binaries on every launch (parallel)
begin_step "Verifying Claude Code..."
start_spinner
claude_out=$(verify_claude 2>&1)
claude_code=$?
stop_spinner $claude_code
if [[ $claude_code -ne 0 ]]; then
  echo "  $claude_out"
  support_exit
fi

begin_step "Verifying Basecamp CLI..."
start_spinner
basecamp_out=$(verify_basecamp 2>&1)
basecamp_code=$?
stop_spinner $basecamp_code
if [[ $basecamp_code -ne 0 ]]; then
  echo "  $basecamp_out"
  support_exit
fi

sleep 0.5
cd "$HOME/Claude" || support_exit
clear && claude
