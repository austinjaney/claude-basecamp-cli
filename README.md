# claude-basecamp-cli

A macOS launcher app and workspace for managing Basecamp using [Claude Code](https://claude.ai/code) and the [Basecamp CLI](https://github.com/basecamp/bc).

## What this is

`Claude Code.app` is a double-click launcher that handles everything needed to get Claude Code running against Basecamp — installing dependencies, verifying their integrity, authenticating, and dropping you into a ready-to-use workspace. You double-click it, and within a few seconds you're talking to Basecamp in plain language.

The `~/Claude` directory is a Claude Code workspace pre-configured with a default Basecamp account and project, so commands go to the right place without any extra flags.

## Requirements

- macOS (arm64 or x86_64)
- Microsoft Defender for Endpoint (`mdatp`) — required; installation will not proceed without it
- Internet access on first launch
- A Basecamp account

## The experience

### First launch

The app detects what's missing and presents a single setup screen before doing anything:

```
  Claude Code · Basecamp
  ──────────────────────────────────────────

  First-time setup
  This app uses Claude Code and the Basecamp CLI to let you
  manage Basecamp in plain language. The following will be set up:

    • Install Claude Code
    • Install Basecamp CLI
    • Connect your Basecamp account
    • Create the ~/Claude workspace

  Ready to continue? [y/n]:
```

One confirmation, then the setup runs:

```
  Downloading Claude Code...           ✓
  Scanning with Microsoft Defender...  ✓
  Installing Claude Code...            ✓
  Downloading Basecamp CLI...          ✓
  Scanning with Microsoft Defender...  ✓
  Installing Basecamp CLI...           ✓

  Connect your Basecamp account
  Your browser will open — sign in and return here when done.

  ✓ Basecamp account connected.
  Creating ~/Claude workspace...       ✓

  Setup complete! Starting Claude Code...
```

Each step shows a live progress indicator and resolves to ✓ or ✗. On failure, the terminal stays open with a clear error and IT contact information.

### Every subsequent launch

```
  Claude Code · Basecamp
  ──────────────────────────────────────────

  Checking for updates...              ✓
  Verifying Claude Code...             ✓
  Verifying Basecamp CLI...            ✓

  Everything is ready. Opening Claude Code...
  (Just type what you want to do in plain English.)
```

Updates to both tools are checked in parallel, at most once per day, to keep startup fast. Binary verification (code signature, team ID, checksum) runs on every launch regardless. If an update fails (no network, already latest), the current version is still verified and launched normally.

### If something goes wrong

Any failure at any stage stops the launcher and shows:

```
  Something went wrong. Contact IT support: itteam@northcoastchurch.com

  Press Enter to close...
```

The terminal stays open so the error context is visible before the user contacts support.

## App structure

```
Claude Code.app/
└── Contents/
    ├── Info.plist                   # App metadata (minimal permissions)
    ├── MacOS/applet                 # AppleScript runtime binary
    └── Resources/
        ├── launch.sh               # All launcher logic lives here
        └── Scripts/main.scpt       # Opens Terminal and runs launch.sh
```

The AppleScript in `main.scpt` is a thin wrapper — it opens Terminal and hands off to `launch.sh`. Everything meaningful happens in the shell script.

## Basecamp workspace

The `~/Claude` directory uses `.basecamp/config.json` to set a default account and project. All `basecamp` commands target this project unless overridden with `-p` or `-a`. See the [Basecamp CLI docs](https://github.com/basecamp/bc) for available commands.

## Security

See [SECURITY.md](SECURITY.md) for a detailed walkthrough of every security decision in `launch.sh` — what risks were considered, what controls were added, and what limitations remain.

## IT support

Issues with the launcher? Contact [itteam@northcoastchurch.com](mailto:itteam@northcoastchurch.com).
