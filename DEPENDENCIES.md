# External Dependencies

This document lists every external assumption `launch.sh` makes beyond its own code. If the launcher stops working after an upstream change, start here.

## Hardcoded identifiers

| Identifier | Value | Used in | Breaks if |
|---|---|---|---|
| Anthropic Apple Team ID | `Q6L2SF6YDW` | `verify_claude()` — checked against `codesign -dv` output | Anthropic re-signs Claude Code under a different Apple Developer account |
| Basecamp Apple Team ID | `2WNYUYRS7G` | `verify_basecamp()` — checked against `codesign -dv --verbose=4` authority chain | Basecamp LLC re-signs their CLI under a different Apple Developer account |
| Claude manifest base URL | `https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases` | `verify_claude()` — fetches `{base}/{version}/manifest.json` | Anthropic moves their release manifests to a different bucket or URL structure |

## Parsed output formats

These are the most fragile dependencies — any upstream format change breaks parsing silently.

### `codesign -dv` (Apple)

```
Executable=/path/to/binary
TeamIdentifier=Q6L2SF6YDW
```

- **Parsed by:** `awk -F= '/^Executable/{print $2}'` and `awk -F= '/TeamIdentifier/{print $2}'`
- **Used in:** `verify_claude()` to resolve the real binary path and extract the team ID
- **Breaks if:** Apple changes the output format of `codesign -dv` (key=value layout, key names, or line structure)

### `codesign -dv --verbose=4` (Apple)

```
Authority=Developer ID Application: Basecamp, LLC (2WNYUYRS7G)
```

- **Parsed by:** `grep "^Authority=Developer ID Application:"` then substring match for team ID
- **Used in:** `verify_basecamp()` to confirm the signing authority
- **Breaks if:** Apple changes the authority line format, or Basecamp changes their Developer ID certificate name

### `claude --version`

```
claude v1.0.25
```

- **Parsed by:** `grep -oE '[0-9]+\.[0-9]+\.[0-9]+'` then validated against `^[0-9]+\.[0-9]+\.[0-9]+$`
- **Used in:** `verify_claude()` to determine which manifest to fetch
- **Breaks if:** Anthropic changes to a non-semver version scheme (e.g., two-part `1.0`, calendar-based `2026.03`), or stops including a version number in the output. Note: pre-release suffixes like `1.0.25-beta` would NOT break it — the grep still extracts `1.0.25`.

### `mdatp scan custom` (Microsoft Defender)

```
... found 0 threats
```

- **Parsed by:** `grep -oE '[0-9]+ threats?'` then extract the number
- **Used in:** `install_tool()` to detect malware in downloaded installers
- **Breaks if:** Microsoft changes the scan output format. **Risk:** if the format changes and `mdatp` exits 0, the threat count grep returns empty, `${threats:-0}` evaluates to 0, and a threat passes undetected. The exit code check is a fallback but some `mdatp` versions exit 0 even with threats.

### `basecamp auth status --json`

```json
{
  "ok": true,
  "data": {
    "authenticated": true,
    "expired": false,
    ...
  }
}
```

- **Parsed by:** python3 — checks `d.get('data',{}).get('authenticated')` or `d.get('authenticated')`
- **Used in:** `is_authenticated()` to decide whether to prompt for login
- **Breaks if:** Basecamp changes the JSON structure (already happened once — `authenticated` moved inside `data`). The dual-path check handles both old and new formats.

### Release manifest JSON (Anthropic)

```json
{
  "platforms": {
    "darwin-arm64": { "checksum": "sha256hex..." },
    "darwin-x64": { "checksum": "sha256hex..." }
  }
}
```

- **Parsed by:** python3 — `m.get('platforms',{}).get(platform,{}).get('checksum','')`
- **Used in:** `verify_claude()` to get the expected SHA-256 checksum
- **Breaks if:** Anthropic restructures the manifest (renames keys, moves checksum to a different path, or changes the hash algorithm)

## System tools assumed present

| Tool | Provided by | Used for | Risk |
|---|---|---|---|
| `python3` | Xcode Command Line Tools | JSON parsing (manifest, auth status) | Apple doesn't guarantee python3 ships with macOS. If removed in a future version, both `verify_claude()` and `is_authenticated()` break. |
| `codesign` | macOS (built-in) | Binary signature verification | Extremely low risk — core macOS security tool |
| `shasum` | macOS (built-in) | SHA-256 checksum of claude binary | Low risk — ships with macOS |
| `curl` | macOS (built-in) | Downloads installers and manifests | Low risk — ships with macOS |
| `stat -f %m` | macOS (built-in) | File modification time for update throttling | macOS-specific flag (`-f %m`). Would break on Linux but this app is macOS-only. |
| `mdatp` | Microsoft Defender for Endpoint | Malware scanning of installers | Required — installer aborts without it. Not a macOS default; must be deployed separately (typically via MDM). |

## Install URLs

| Tool | URL | Breaks if |
|---|---|---|
| Claude Code | `https://claude.ai/install.sh` | Anthropic changes the install URL or script behavior |
| Basecamp CLI | `https://basecamp.com/install-cli` | Basecamp changes the install URL or script behavior |

These are mutable — they always serve the latest version. There is no way to pin to a specific version.

## OAuth flow

- `basecamp auth login` opens a browser to `launchpad.37signals.com` for OAuth
- The callback uses a local HTTP server on `127.0.0.1` started by the Basecamp CLI
- **Breaks if:** 37signals changes their OAuth endpoint, the Basecamp CLI changes its auth flow, or a firewall blocks localhost callbacks
