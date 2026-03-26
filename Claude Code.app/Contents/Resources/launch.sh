#!/bin/bash

CLAUDE_TEAM_ID="Q6L2SF6YDW"
CLAUDE_MANIFEST_BASE="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

support_exit() {
  echo ""
  echo "If you need help, please contact IT support at itteam@northcoastchurch.com"
  read -r -p "Press Enter to close..."
  exit 1
}

# Refresh PATH to pick up freshly installed tools
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

  # Code signature + team ID check
  if ! codesign --verify --strict "$real_bin" 2>/dev/null; then
    echo "ERROR: claude binary has an invalid signature. Aborting."
    return 1
  fi
  local team
  team=$(codesign -dv "$real_bin" 2>&1 | awk -F= '/TeamIdentifier/{print $2}')
  if [[ "$team" != "$CLAUDE_TEAM_ID" ]]; then
    echo "ERROR: claude binary team ID '$team' does not match expected '$CLAUDE_TEAM_ID'. Aborting."
    return 1
  fi

  # Manifest checksum check
  version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [[ -z "$version" ]]; then
    echo "ERROR: Could not determine claude version. Aborting."
    return 1
  fi

  local os arch
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  [[ "$arch" == "x86_64" ]] && arch="x64"
  [[ "$arch" == "arm64" || "$arch" == "aarch64" ]] && arch="arm64"
  platform="${os}-${arch}"

  manifest=$(curl -fsSL --max-time 30 "${CLAUDE_MANIFEST_BASE}/${version}/manifest.json" 2>/dev/null)
  if [[ -z "$manifest" ]]; then
    echo "ERROR: Could not fetch manifest for claude v${version}. Aborting."
    return 1
  fi

  checksum=$(python3 -c "
import json, sys
m = json.loads(sys.stdin.read())
p = m.get('platforms', {}).get(sys.argv[1], {})
print(p.get('checksum', ''))
" "$platform" <<< "$manifest")

  if [[ -z "$checksum" ]]; then
    echo "ERROR: No checksum found in manifest for platform '$platform'. Aborting."
    return 1
  fi

  actual_checksum=$(shasum -a 256 "$real_bin" | awk '{print $1}')
  if [[ "$actual_checksum" != "$checksum" ]]; then
    echo "ERROR: claude binary checksum mismatch."
    echo "  Expected: $checksum"
    echo "  Got:      $actual_checksum"
    return 1
  fi
}

scan_installer() {
  local file="$1" label="$2" scan_output threats

  if ! command -v mdatp &>/dev/null; then
    echo "ERROR: Microsoft Defender (mdatp) not found. Cannot scan $label installer. Aborting."
    return 1
  fi

  echo "Scanning $label installer with Microsoft Defender..."
  scan_output=$(mdatp scan custom --path "$file" 2>&1)
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "ERROR: Defender scan failed for $label installer (exit code $exit_code). Aborting."
    echo "$scan_output"
    return 1
  fi

  threats=$(echo "$scan_output" | grep -oE '[0-9]+ threat' | grep -oE '^[0-9]+')
  if [[ "${threats:-0}" -gt 0 ]]; then
    echo "ERROR: Defender detected ${threats} threat(s) in $label installer. Aborting."
    echo "$scan_output"
    return 1
  fi

  echo "Defender scan passed for $label installer."
}

verify_basecamp() {
  local bin
  bin=$(command -v basecamp) || return 1
  if ! codesign --verify --strict "$bin" 2>/dev/null; then
    echo "ERROR: basecamp binary has an invalid signature. Aborting."
    return 1
  fi
}

# Check for Claude Code
if ! command -v claude &>/dev/null; then
  echo "Claude Code is not installed."
  read -r -p "Install it now? [y/n]: " answer
  case "$answer" in
    [Yy])
      echo "Installing Claude Code..."
      installer=$(mktemp /tmp/claude-install.XXXXXX.sh)
      curl -fsSL --max-time 60 https://claude.ai/install.sh -o "$installer" || { rm -f "$installer"; echo "ERROR: Failed to download Claude Code installer."; support_exit; }
      scan_installer "$installer" "Claude Code" || { rm -f "$installer"; support_exit; }
      bash "$installer"
      rm -f "$installer"
      refresh_path
      if ! command -v claude &>/dev/null; then
        echo "Installation failed. Please install Claude Code manually and try again."
        support_exit
      fi
      echo "Claude Code installed successfully."
      ;;
    *)
      echo "Exiting."
      exit 1
      ;;
  esac
fi
verify_claude || support_exit

# Check for Basecamp CLI
if ! command -v basecamp &>/dev/null; then
  echo "Basecamp CLI is not installed."
  read -r -p "Install it now? [y/n]: " answer
  case "$answer" in
    [Yy])
      echo "Installing Basecamp CLI..."
      installer=$(mktemp /tmp/basecamp-install.XXXXXX.sh)
      curl -fsSL --max-time 60 https://basecamp.com/install-cli -o "$installer" || { rm -f "$installer"; echo "ERROR: Failed to download Basecamp CLI installer."; support_exit; }
      scan_installer "$installer" "Basecamp CLI" || { rm -f "$installer"; support_exit; }
      bash "$installer"
      rm -f "$installer"
      refresh_path
      if ! command -v basecamp &>/dev/null; then
        echo "Installation failed. Please install Basecamp CLI manually and try again."
        support_exit
      fi
      echo "Basecamp CLI installed successfully."
      ;;
    *)
      echo "Exiting."
      exit 1
      ;;
  esac
fi
verify_basecamp || support_exit

# Check Basecamp authentication
auth_status=$(basecamp auth status --json 2>/dev/null)
if ! grep -q '"authenticated": true' <<< "$auth_status"; then
  echo "Basecamp is not authenticated."
  read -r -p "Set up Basecamp authentication now? [y/n]: " answer
  case "$answer" in
    [Yy])
      basecamp auth login
      auth_status=$(basecamp auth status --json 2>/dev/null)
      if ! grep -q '"authenticated": true' <<< "$auth_status"; then
        echo "Authentication failed. Please run 'basecamp auth login' manually and try again."
        support_exit
      fi
      echo "Basecamp authenticated successfully."
      ;;
    *)
      echo "Exiting."
      exit 1
      ;;
  esac
fi

# Check for ~/Claude folder
if [ ! -d ~/Claude ]; then
  echo "~/Claude folder not found."
  read -r -p "Create it now? [y/n]: " answer
  case "$answer" in
    [Yy]) mkdir -p ~/Claude && echo "Created ~/Claude." ;;
    *) echo "Exiting."; exit 1 ;;
  esac
fi

cd ~/Claude || support_exit
clear && claude
