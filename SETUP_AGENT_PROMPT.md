# MoltNotch + MoltBot — Interactive Setup Guide

You are helping a user set up **MoltNotch**, a macOS notch chat assistant that connects to a **MoltBot** (also known as **Clawdbot**) gateway. Follow this guide step by step, interactively confirming each stage with the user before proceeding.

## What You're Setting Up

| Component | What it is | Where it runs |
|-----------|-----------|---------------|
| **MoltBot Gateway** | AI assistant backend (Node.js WebSocket server) | The user's Mac (or a remote server) |
| **MoltNotch** | macOS notch chat client (SwiftUI app) | The user's MacBook |

MoltNotch connects to MoltBot via WebSocket. The user presses Ctrl+Space to open a glass chat popup from the MacBook notch, types a question, and gets streamed responses. Screenshots can be attached as context.

---

## Phase 1: MoltBot Gateway

> **If the user already has MoltBot/Clawdbot running**, skip to [Phase 2](#phase-2-moltnotch-client). Ask them first.

### 1.1 Prerequisites

```sh
# Node 22+ is required
node --version    # must be >= 22.12.0
```

If Node is missing or too old, install via nvm or Homebrew:
```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
nvm install 22
```

### 1.2 Install MoltBot

```sh
npm install -g moltbot@latest
```

This installs both `moltbot` and `clawdbot` binaries (they're the same).

### 1.3 Run the Onboarding Wizard

```sh
moltbot onboard --install-daemon
```

The wizard will:
1. Ask for an AI provider and auth credentials (API key, OAuth, etc.)
2. Configure the gateway (port, bind mode, auth token)
3. Install a background daemon (launchd on macOS, systemd on Linux)
4. Run a health check

**Important outputs to note:**
- **Gateway port**: Default `18789`
- **Auth token**: Auto-generated 48-character hex string
- **Config file**: Written to `~/.moltbot/moltbot.json` (or `~/.clawdbot/moltbot.json` for legacy installs)

> **Non-interactive alternative** (for automation):
> ```sh
> moltbot onboard \
>   --non-interactive \
>   --accept-risk \
>   --auth-choice setup-token \
>   --gateway-auth token \
>   --install-daemon
> ```

### 1.4 Verify the Gateway

```sh
moltbot health --verbose
moltbot doctor
```

**Ask the user:** "Is MoltBot running? Does `moltbot health` show `ok: true`?"

### 1.5 Get the Auth Token

The auth token is needed for MoltNotch to connect. Help the user find it:

```sh
# Option A: Read from config
cat ~/.moltbot/moltbot.json | grep -A2 '"auth"'
# or for legacy installs:
cat ~/.clawdbot/moltbot.json | grep -A2 '"auth"'

# Option B: Check environment
echo $CLAWDBOT_GATEWAY_TOKEN

# Option C: Generate a new one
moltbot doctor --generate-gateway-token
```

The token is at `gateway.auth.token` in the JSON config. Save it — you'll need it in Phase 2.

---

## Phase 2: MoltNotch Client

### 2.1 Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 16+** with command-line tools
- **Homebrew** (for xcodegen)

```sh
# Verify Xcode CLI tools
xcode-select -p

# Install xcodegen
brew install xcodegen
```

### 2.2 Clone and Build

```sh
git clone https://github.com/moltbot/moltnotch.git
cd moltnotch
xcodegen generate

# Build the app
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotch -configuration Release -derivedDataPath build/derived

# Build the CLI tool
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotchCLI -configuration Release -derivedDataPath build/derived
```

**Built binaries:**
- App: `build/derived/Build/Products/Release/MoltNotch.app`
- CLI: `build/derived/Build/Products/Release/moltnotch`

### 2.3 Install the CLI

```sh
cp build/derived/Build/Products/Release/moltnotch /usr/local/bin/
```

Verify: `moltnotch --help`

### 2.4 Run the Setup Wizard

```sh
moltnotch setup
```

The wizard asks three things:

| Question | What to enter |
|----------|---------------|
| **Gateway URL** | `ws://127.0.0.1:18789` if MoltBot runs locally. If remote, use the server's IP/hostname. |
| **Auth token** | The token from [Phase 1.5](#15-get-the-auth-token) |
| **SSH tunnel?** | Yes if the gateway is on a remote machine behind a firewall |

This writes `~/.moltnotch.toml` with permissions `0600`.

**If the gateway is remote and needs SSH tunneling**, the wizard will also ask:
- SSH host (IP or hostname)
- SSH user
- SSH port (default: 22)
- Remote gateway port (default: 18789)
- Local port to forward to (default: 18789)

### 2.5 Verify Connection

```sh
moltnotch doctor
```

This checks:
1. Config file exists and parses
2. Gateway is reachable (TCP)
3. WebSocket handshake succeeds
4. SSH host is reachable (if tunnel configured)

**Ask the user:** "Does `moltnotch doctor` pass all checks? If WebSocket fails, double-check the auth token."

### 2.6 Grant macOS Permissions

MoltNotch needs two permissions. Open **System Settings → Privacy & Security**:

| Permission | Where to grant | What it enables |
|------------|----------------|-----------------|
| **Screen Recording** | Privacy & Security → Screen Recording | Screenshot attachments (Tab key) |
| **Accessibility** | Privacy & Security → Accessibility | Global hotkey (Ctrl+Space) |

Steps:
1. Launch MoltNotch — it will prompt for Screen Recording on first run
2. Grant it, then **quit and relaunch** (macOS requires restart after granting)
3. For Accessibility, click `+` in the preference pane and add `MoltNotch.app`
4. **Quit and relaunch** again

### 2.7 Launch

```sh
# Option A: From build directory
open build/derived/Build/Products/Release/MoltNotch.app

# Option B: Move to Applications first
cp -R build/derived/Build/Products/Release/MoltNotch.app /Applications/
open /Applications/MoltNotch.app
```

MoltNotch is a **menu bar app** — look for the ✦ icon in the top-right of your screen. There is no dock icon or window.

---

## Phase 3: Verify Everything Works

Walk the user through this sequence:

1. **Press Ctrl+Space** — the chat popup should emerge from the notch
2. **Type "Hello"** and press Enter — you should see "Thinking..." then a streamed response
3. **Press Tab** — a cyan 📷 icon should appear in the input field
4. **Type "What's on my screen?"** and press Enter — the response should reference screen content
5. **Press Escape** — popup should dismiss

**If something fails:**

| Failure | Diagnosis |
|---------|-----------|
| Ctrl+Space doesn't work | Accessibility permission not granted. Check System Settings. |
| "Not connected to gateway" | Run `moltnotch doctor`. Check that MoltBot is running (`moltbot health`). |
| Connects then disconnects | Auth token mismatch. Compare `~/.moltnotch.toml` token with `~/.moltbot/moltbot.json` gateway.auth.token |
| Screenshot fails | Screen Recording permission not granted. Check System Settings, relaunch. |
| Bot says "No image attached" | Screen Recording permission denied at OS level. Grant and **relaunch**. |

---

## Keyboard Shortcuts Reference

| Key | Action |
|-----|--------|
| **Ctrl+Space** | Toggle popup |
| **Enter** | Send message |
| **Tab** | Toggle screenshot attachment |
| **Shift+Enter** | Send with screenshot (always) |
| **Ctrl × 2** | Clear visible chat (backend preserved) |
| **Escape** | Stop stream → clear input → dismiss |

---

## Configuration Files Reference

### MoltBot Gateway (`~/.moltbot/moltbot.json`)

```json5
{
  "agent": {
    "model": "anthropic/claude-opus-4-5"
  },
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "<48-char-hex-token>"
    }
  }
}
```

Key paths:
- `gateway.auth.token` — the credential MoltNotch needs
- `gateway.port` — must match MoltNotch's gateway URL port
- `gateway.auth.mode` — "token" (default) or "password"

Legacy paths: `~/.clawdbot/moltbot.json` or `~/.clawdbot/clawdbot.json`

### MoltNotch Client (`~/.moltnotch.toml`)

```toml
[gateway]
url = "ws://127.0.0.1:18789"
token = "your-auth-token"
health-check-interval = 15
reconnect-max-attempts = 10

[hotkey]
key = "space"
modifiers = ["control"]

# Only if gateway is behind SSH
[tunnel]
host = "server-ip-or-hostname"
user = "ssh-user"
port = 22
remote-port = 18789
local-port = 18789
```

### Environment Variables (MoltBot)

| Variable | Purpose |
|----------|---------|
| `CLAWDBOT_GATEWAY_TOKEN` | Auth token (overrides config) |
| `CLAWDBOT_GATEWAY_PASSWORD` | Auth password (overrides config) |
| `CLAWDBOT_GATEWAY_PORT` | Gateway port (overrides config) |
| `MOLTBOT_STATE_DIR` | State directory override |

---

## Troubleshooting Commands

```sh
# MoltBot side
moltbot health --verbose       # gateway health check
moltbot doctor                 # comprehensive diagnostics
moltbot status                 # quick status
moltbot devices list           # show connected/pending devices

# MoltNotch side
moltnotch doctor               # connection diagnostics
moltnotch setup                # re-run setup wizard
```

## Source Repositories

| Repo | Purpose | URL |
|------|---------|-----|
| **MoltBot** | Gateway + AI backend | https://github.com/moltbot/moltbot |
| **MoltNotch** | macOS notch client | https://github.com/moltbot/moltnotch |
