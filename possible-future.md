# Possible Future Improvements

Ideas that fit within the scope of a minimal Claude Code launcher. None of these are planned — they're starting points for the next time this project gets attention.

## Reliability

- **Offline detection** — Check for internet connectivity before attempting downloads or auth. Show a clear "No internet connection" message instead of letting curl timeout.
- **Retry on transient failures** — Auth token exchange and manifest fetches can fail with 502/503. Offer "Try again? [y/n]" instead of immediately sending users to IT support.
- **Clean error display** — Strip HTML from failed HTTP responses before showing them in the terminal. A raw `<!DOCTYPE html>` dump is confusing for non-technical users.

## UX for non-technical users

- **Progress percentage for downloads** — Show download progress (curl's `-#` flag or a custom progress bar) so users know the app hasn't frozen during large installs.
- **"What just happened" summary** — After first-time setup completes, briefly explain what was installed and where, so users aren't left wondering what changed on their machine.
- **Guided first prompt** — After Claude Code opens for the first time, suggest a starter prompt like "Show me my Basecamp todos" so users aren't staring at a blank cursor.

## IT administration

- **Session logging** — Write launcher output to `~/Claude/.launcher.log` (rotating, capped size) so IT can troubleshoot without asking users to reproduce the issue.
- **Health check flag** — `launch.sh --status` that runs all verification checks and prints a summary without launching Claude Code. Useful for MDM compliance scripts.
- **Configurable support contact** — Move the IT email to a config file or plist key so other organizations can use the launcher without editing the script.
- **Self-update mechanism** — Check a release URL for a newer version of the launcher itself, download and replace the .app bundle. Currently the launcher can update its dependencies but not itself.

## Multi-project support

- **Project selector** — If the Basecamp account has multiple projects, offer a picker on launch instead of always targeting the default project.
- **Workspace profiles** — Support multiple `~/Claude-<project>` directories with different `.basecamp/config.json` files, selectable at launch.

## Security

- **Checksum verification for Basecamp CLI** — If Basecamp publishes release manifests in the future, add checksum verification to match what we already do for Claude Code.
- **Certificate revocation checking** — Add `--check-revocation` to codesign verification for environments where network access is reliable.
- **Installer pinning** — If either vendor publishes versioned installer URLs, pin to specific versions and update them deliberately rather than always fetching latest.
