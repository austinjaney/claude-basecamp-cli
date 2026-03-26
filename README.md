# claude-basecamp-cli

A macOS launcher app and workspace for managing Basecamp using [Claude Code](https://claude.ai/code) and the [Basecamp CLI](https://github.com/basecamp/bc).

## What this is

`Claude Code.app` is a double-click launcher that:

1. Ensures Claude Code and the Basecamp CLI are installed and authenticated
2. Verifies both binaries are legitimate before running them
3. Opens a terminal session in `~/Claude` with Claude Code ready to go

The `~/Claude` directory is a Claude Code workspace pre-configured to talk to Basecamp — you can ask Claude to read, create, and update Basecamp content in plain language.

## Requirements

- macOS (arm64 or x86_64)
- Microsoft Defender for Endpoint (`mdatp`) — required for installer scanning
- Internet access on first launch (for installing Claude Code and Basecamp CLI)
- A Basecamp account

## Usage

Double-click `Claude Code.app`. On first launch it will:

1. Check for Claude Code — offer to install if missing
2. Check for Basecamp CLI — offer to install if missing
3. Verify both binaries (signature + checksum)
4. Check Basecamp authentication — walk through login if needed
5. Create `~/Claude` if it doesn't exist
6. Open Claude Code in the `~/Claude` workspace

Subsequent launches skip straight to step 3 and open in a few seconds.

If anything fails, the terminal stays open with an error message and IT contact information.

## App structure

```
Claude Code.app/
├── Contents/
│   ├── Info.plist                        # App metadata and permissions
│   ├── MacOS/applet                      # AppleScript runtime binary
│   └── Resources/
│       ├── launch.sh                     # Main launcher logic (the interesting bit)
│       └── Scripts/main.scpt            # AppleScript that runs launch.sh in Terminal
```

The AppleScript in `main.scpt` is minimal — it opens Terminal and runs `launch.sh`. All the real logic lives in `launch.sh`.

## Basecamp workspace

The `~/Claude` directory uses a `.basecamp/config.json` to set a default account and project, so all `basecamp` commands target the right place without extra flags. See the [Basecamp CLI docs](https://github.com/basecamp/bc) for available commands.

## Security

See [SECURITY.md](SECURITY.md) for a full breakdown of the security design in `launch.sh`.

## IT support

Issues with the launcher? Contact [itteam@northcoastchurch.com](mailto:itteam@northcoastchurch.com).
