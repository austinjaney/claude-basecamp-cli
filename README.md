<p align="center">
  <img src="Icons/AppIcon_1024x1024.png" alt="Claude Code · Basecamp" width="128">
</p>

# claude-basecamp-cli

A macOS launcher app and workspace for managing Basecamp using [Claude Code](https://claude.ai/code) and the [Basecamp CLI](https://github.com/basecamp/bc).

## What this is

`Claude Code.app` is a double-click launcher that handles everything needed to get Claude Code running against Basecamp — installing dependencies, verifying their integrity, authenticating, and dropping you into a ready-to-use workspace. You double-click it, and within a few seconds you're talking to Basecamp in plain language.

The `~/Claude` directory is a Claude Code workspace pre-configured with a default Basecamp account and project, so commands go to the right place without any extra flags.

## Prerequisites

Before distributing this app, ensure the following are in place on target machines:

| Requirement | Why | How to verify |
|---|---|---|
| **macOS** (arm64 or x86_64) | Only platform supported | `uname -ms` → `Darwin arm64` or `Darwin x86_64` |
| **Microsoft Defender for Endpoint** | Every downloaded installer is scanned before execution. The launcher will not proceed without it. | `mdatp version` returns a version number |
| **Internet access** | Required on first launch to download Claude Code and Basecamp CLI, and for Basecamp OAuth. Subsequent launches need internet only for daily update checks and manifest verification. | `curl -sI https://claude.ai` returns `200` |
| **A Basecamp account** | Users authenticate via OAuth during first-time setup. | User can sign in at [launchpad.37signals.com](https://launchpad.37signals.com) |
| **Terminal.app** | The launcher opens Terminal to run its setup script. Included with macOS by default. | `/Applications/Utilities/Terminal.app` exists |

No other dependencies are needed — Claude Code and the Basecamp CLI are installed automatically on first launch.

## The experience

### First launch

The app detects what's missing and presents a single setup screen before doing anything:

```
  Claude Code · Basecamp
  ──────────────────────────────────────────

  First-time setup
  This app uses Claude Code and the Basecamp CLI to let you
  manage Basecamp in plain language. The following will be set up:

    • Configure IT support contact
    • Install Claude Code
    • Install Basecamp CLI
    • Connect your Basecamp account
    • Create the ~/Claude workspace

  Ready to continue? [y/n]:
```

One confirmation, then setup begins. The first step prompts for an IT support email address — this is saved locally and shown to the user if anything goes wrong in the future:

```
  IT support contact
  If something goes wrong, this email will be shown so you
  know who to contact for help.

  IT support email address: helpdesk@example.com

  ✓ Support contact saved.
```

Then the rest of the setup runs:

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

Each step shows a live progress indicator and resolves to ✓ or ✗. On failure, the terminal stays open with a clear error and the IT support contact.

### Every subsequent launch

```
  Claude Code · Basecamp
  ──────────────────────────────────────────

  Verifying Claude Code...             ✓
  Verifying Basecamp CLI...            ✓

  Everything is ready. Opening Claude Code...
  (Just type what you want to do in plain English.)
```

Binary verification (code signature, team ID, checksum) runs on every launch. Once per day, a "Checking for updates..." step also appears before verification — both tools are updated in parallel. If an update fails (no network, already latest), the current version is still verified and launched normally.

### If something goes wrong

Any failure at any stage stops the launcher and shows:

```
  Something went wrong. Contact IT support: helpdesk@example.com

  Press Enter to close...
```

The terminal stays open so the error context is visible before the user contacts support. The email shown is whatever was entered during first-time setup (stored in `~/.claude/.support_email`).

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

## Configuration files

| File | Purpose |
|---|---|
| `~/.claude/.support_email` | IT support email shown on errors (set during first-time setup) |
| `~/.claude/.last_update_check` | Timestamp for daily update throttling |
| `~/Claude/.basecamp/config.json` | Default Basecamp account and project |
