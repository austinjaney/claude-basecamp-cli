# Security Design — Claude Code.app

This document walks through every security decision in `Claude Code.app/Contents/Resources/launch.sh` — what risk each one addresses, how it works, and what tradeoffs were made. It's written so that someone maintaining this later can understand not just *what* the controls are, but *why* they exist.

## The threat model

The launcher's job is to download and execute third-party software (Claude Code, Basecamp CLI) using the current user's credentials. That makes it an attractive target. The threats we designed against are:

- **Supply chain compromise** — a tampered binary delivered via a compromised CDN or package source
- **Binary substitution** — a legitimate-looking executable that isn't actually from Anthropic or Basecamp
- **Malicious installer** — a script delivered over the network that does damage before the binary is even placed on disk
- **Excessive app permissions** — the launcher itself requesting system access it doesn't need

## The security story, step by step

### Step 1 — Strip the app's own permissions

The first question we asked was: what does this launcher actually need access to? The answer is nothing — it opens Terminal and runs a shell script. Yet the default AppleScript applet template ships with usage descriptions for camera, microphone, contacts, calendar, HomeKit, photos, music, reminders, Siri, and system administration declared in `Info.plist`.

We removed all of them. Any permissions that Claude Code or Basecamp actually need at runtime are requested by Terminal.app in context, not pre-declared by the launcher. The launcher's `Info.plist` is now minimal.

### Step 2 — Don't pipe the internet directly into bash

The standard install pattern for both Claude Code and Basecamp CLI is:

```bash
curl -fsSL https://example.com/install.sh | bash
```

This is convenient but dangerous — the script is streamed directly into a shell with no opportunity to inspect or verify it. A MITM, a DNS hijack, or a compromised CDN delivers code that runs immediately.

We changed this to download-then-execute:

```bash
installer=$(mktemp "${TMPDIR:-/tmp}/installer.XXXXXX.sh")
curl -fsSL --max-time 60 https://claude.ai/install.sh -o "$installer" || abort
# scan and verify before running
bash "$installer"
```

The installer lands in a temp file at mode 600 (owner read/write only — no other user can see or modify it) before anything executes. We use `$TMPDIR` rather than `/tmp` because on macOS `$TMPDIR` resolves to a user-private directory under `/var/folders`, whereas `/tmp` is world-accessible. The curl exit code is checked — a failed download aborts immediately rather than executing an empty or partial file.

A `trap cleanup EXIT` at the top of the script ensures the temp file is removed on every exit path, including Ctrl+C.

### Step 3 — Scan every installer with Microsoft Defender before running it

Once the installer is on disk, we pass it to Microsoft Defender for Endpoint's command-line scanner before executing it:

```bash
mdatp scan custom --path "$installer"
```

There is no bypass path — if Defender is not installed, the install aborts. The threat count in the scan output is always checked regardless of the exit code (some `mdatp` versions may exit zero even when threats are found). If the threat count is greater than zero, the install aborts. If the scan command returns a non-zero exit code, the install aborts. The file is deleted on any of these paths.

This catches known malware signatures in the installer script itself — a layer that sits between download and execution.

### Step 4 — Verify the binary's code signature and publisher identity

After installation, and again on every subsequent launch, we verify the installed binary before allowing it to run. For Claude Code, this is a two-part check.

First, we resolve the real binary on disk. The Claude Code installer places a versioned binary at `~/.local/share/claude/versions/<version>` and creates a symlink at `~/.local/bin/claude`. We use `codesign -dv` to find the actual executable path rather than trusting the symlink.

Then we verify the signature:

```bash
codesign --verify --strict "$real_bin"
```

And check the Apple Developer team ID matches Anthropic's:

```bash
team=$(codesign -dv "$real_bin" 2>&1 | awk -F= '/TeamIdentifier/{print $2}')
# must equal Q6L2SF6YDW
```

The team ID `Q6L2SF6YDW` is Anthropic's identifier. It is stable across all Claude Code releases — a new version of the app will still carry this ID. Hardcoding it gives us a publisher identity check that survives upgrades without maintenance.

The Basecamp CLI is signature-verified (`codesign --verify --strict`) and the signing authority is checked against Basecamp, LLC's Developer ID (`2WNYUYRS7G`). Unlike Claude Code, the Basecamp binary does not embed a `TeamIdentifier` in its codesign metadata, so we verify the full authority chain instead — specifically that the `Developer ID Application` authority contains the expected team ID.

### Step 5 — Verify the binary's checksum against Anthropic's release manifest

A binary can have a valid Anthropic signature and still not match what Anthropic actually shipped for a given version. To catch this case, we fetch the release manifest for the exact installed version:

```
https://storage.googleapis.com/claude-code-dist-.../claude-code-releases/{VERSION}/manifest.json
```

The manifest contains per-platform SHA-256 checksums. We detect the current platform from `uname`, validate it against an allowlist (`darwin-arm64`, `darwin-x64`), extract the expected checksum via Python's `json` module (with the platform string passed as an argument — never interpolated into code), and compare it against `shasum -a 256` of the binary on disk.

A mismatch hard-aborts. The code signature check and the checksum check are independent layers — a compromised binary would have to defeat both.

### Step 6 — Add timeouts to every network call

All `curl` calls include `--max-time` to prevent the launcher from hanging indefinitely:

- Manifest fetch: 30 seconds (small JSON file)
- Installer downloads: 60 seconds (reasonable for a shell script over a typical connection)

A server that never responds is treated the same as a server that returns an error.

### Step 7 — Validate inputs before using them in network requests

The version string extracted from `claude --version` is validated against a strict regex (`^[0-9]+\.[0-9]+\.[0-9]+$`) before being interpolated into the manifest URL. If the output of `claude --version` is unexpected or malformed, we abort rather than constructing a potentially bad URL.

Similarly, the platform string derived from `uname` is checked against a fixed allowlist before being used as a JSON key. An unrecognised platform aborts rather than producing a silent lookup failure.

## Known limitations

**The installer script has no cryptographic verification.** The Defender scan checks for known malware signatures, but the installer has no GPG signature or published checksum we can verify before running it. A compromised CDN could deliver a malicious installer that causes damage before the binary verification step runs. This is a fundamental limitation of the curl-based installer model used by both Anthropic and Basecamp — the controls downstream (signature, team ID, checksum) verify the *result* of installation, not the installer itself.

**The manifest is trusted via TLS, not a separate signature.** The release manifest is fetched over HTTPS from Google Cloud Storage. Transport security protects against MITM, but a compromised GCS bucket could serve a manifest with attacker-controlled checksums. In that scenario, the checksum check would pass for a malicious binary. The code signature + team ID check is an independent layer that would still catch this for `claude` specifically, since forging Anthropic's Apple Developer signature would require compromising their signing certificate.

**Basecamp CLI has no manifest or checksum verification.** Unlike Claude Code, the Basecamp CLI does not publish a release manifest with per-platform checksums. The signing authority check (`Developer ID Application: Basecamp, LLC (2WNYUYRS7G)`) confirms publisher identity, but there is no independent checksum layer. If Basecamp publishes release manifests in the future, checksum verification should be added.

**The version used for manifest lookup comes from executing the binary under verification.** The checksum verification in Step 5 relies on `claude --version` to determine which manifest to fetch. A malicious binary could lie about its version to match a known-good manifest checksum. This is mitigated by the code signature + team ID check (Step 4), which is an independent layer — a binary that lies about its version would still need Anthropic's valid signing certificate. The checksum is a supplementary layer, not standalone.

**Certificate revocation is not checked.** The `codesign --verify --strict` call does not check certificate revocation lists by default. A signing certificate that Apple has revoked could still pass verification. Adding `--check-revocation` requires network access and may fail on offline machines. The checksum verification against Anthropic's release manifest provides an independent layer that partially compensates for this gap.

**Installer scripts run with full shell capabilities.** The `bash "$installer"` call at installation time runs without restricted mode. This is necessary because installer scripts typically need to create directories, write files, modify PATH, and download additional assets — all of which `bash --restricted` would block. The Defender scan (Step 3) is the primary control that runs before execution.

**Installer URLs are mutable.** The installer URLs (`https://claude.ai/install.sh`, `https://basecamp.com/install-cli`) point to whatever version the vendor is currently serving. A compromised CDN could deliver a novel payload that passes the Defender scan (which only catches known signatures). The post-install binary verification (Steps 4-5) catches tampering with the installed binary, but cannot protect against damage done by the installer script itself before the binary is placed on disk. Neither vendor publishes stable versioned installer URLs that would allow pinning.
