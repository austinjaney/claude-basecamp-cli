# Security Design — Claude Code.app

This document describes the security decisions in `Claude Code.app/Contents/Resources/launch.sh` and the reasoning behind them.

## Threat model

The launcher downloads and executes third-party software (Claude Code, Basecamp CLI) and runs them with the current user's privileges. The primary threats are:

- A tampered or substituted binary (supply chain compromise, local replacement)
- A malicious installer script delivered via MITM or compromised CDN
- The app requesting unnecessary system permissions

## Controls

### 1. Pruned app permissions

The `Info.plist` declares only the permissions the app actually needs. All unnecessary usage description keys (camera, microphone, contacts, calendar, HomeKit, photos, music, reminders, Siri, system administration) were removed. Any permissions Claude Code or Basecamp actually require at runtime are requested by Terminal.app, not by this launcher.

### 2. Download-then-execute (no curl-pipe-bash)

Installers are never piped directly to a shell:

```bash
# What we don't do
curl -fsSL https://example.com/install.sh | bash

# What we do instead
installer=$(mktemp /tmp/claude-install.XXXXXX.sh)
curl -fsSL --max-time 60 https://example.com/install.sh -o "$installer" || abort
# ... scan and verify ...
bash "$installer"
rm -f "$installer"
```

The installer lands in a temp file (mode 600 — owner only) before anything runs. The download exit code is checked; a failed download aborts before reaching execution.

### 3. Microsoft Defender scan

Before executing any downloaded installer, `mdatp scan custom --path` is called against the temp file. If Defender is not present or the scan fails, the install aborts — there is no bypass path.

```
Defender missing      → abort
Scan command errors   → abort
Threats detected > 0  → abort
Scan passes           → proceed to execute
```

The installer temp file is removed immediately after execution (or on any abort path).

### 4. Binary verification — code signature + team ID

After installation (and on every subsequent launch), the installed binary is verified against Anthropic's Apple Developer team ID before Claude Code is allowed to run:

```bash
codesign --verify --strict "$real_bin"           # valid signature
codesign -dv "$real_bin" | grep TeamIdentifier   # must match Q6L2SF6YDW
```

The team ID `Q6L2SF6YDW` is Anthropic's and is stable across releases. A mismatched or unsigned binary is rejected regardless of how it got there.

The Basecamp CLI is signature-verified (`codesign --verify --strict`) but has no team ID in its current distribution, so publisher identity cannot be confirmed for that binary.

### 5. Binary verification — manifest checksum

In addition to the code signature, the `claude` binary is verified against the SHA-256 checksum published in Anthropic's release manifest:

```
https://storage.googleapis.com/.../claude-code-releases/{VERSION}/manifest.json
```

The manifest is fetched for the exact installed version, the platform-specific checksum is extracted via `python3` (with `$platform` passed as an argument, never interpolated into code), and compared against `shasum -a 256` of the real binary on disk.

This catches a binary that is validly signed but does not match what Anthropic actually shipped for that version.

### 6. curl timeouts

All `curl` calls have explicit `--max-time` limits to prevent the launcher from hanging indefinitely on a slow or unresponsive server:

- Manifest fetch: 30 seconds
- Installer downloads: 60 seconds

## Known limitations

**Manifest trust anchor.** The release manifest is fetched over HTTPS from Google Cloud Storage. Transport security (TLS) protects against MITM, but a compromised GCS bucket could serve a manifest with attacker-controlled checksums, which would cause the checksum check to pass for a malicious binary. The code signature + team ID check is a separate and independent layer that would still catch this scenario for `claude`.

**Installer not verified before execution.** The Defender scan and download-exit-code check reduce risk, but the installer script itself has no cryptographic verification (no GPG signature, no checksum). A compromised CDN could deliver a malicious installer that causes damage before the binary verification step runs. This is a fundamental limitation of the curl-based installer model used by both Anthropic and Basecamp.

**Basecamp CLI has no team ID.** The Basecamp binary ships without an Apple Developer team identifier, so publisher identity cannot be confirmed beyond "the signature is structurally valid." If Basecamp begins publishing a properly signed binary this check should be extended to include a team ID assertion.
