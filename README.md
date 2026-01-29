# MoltNotch 🦞 - Chat with your Moltbot from the MacBook notch

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0078d7)](https://developer.apple.com/macos/)
[![Swift 5.0](https://img.shields.io/badge/Swift-5.0-F05138)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-ffd60a)](LICENSE)

<p align="center">
  <img src="assets/demo.gif" alt="MoltNotch demo - chat from the MacBook notch" width="600" />
</p>

macOS notch assistant that plugs into your [MoltBot](https://github.com/moltbot/moltbot) (Clawdbot) gateway. Ctrl+Space opens a glass chat popup from the notch - ask questions, attach your screen as context, and pick up the conversation anywhere MoltBot runs.

Runs as a menu bar app (✦ icon). No windows, no dock icon. Just a hotkey away.

## Install

```sh
brew install xcodegen

git clone https://github.com/moltbot/moltnotch.git
cd moltnotch
xcodegen generate

# Build app + CLI
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotch -configuration Release -derivedDataPath build/derived
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotchCLI -configuration Release -derivedDataPath build/derived

# Put the CLI on your PATH
cp build/derived/Build/Products/Release/moltnotch /usr/local/bin/
```

Requires Xcode 16+ and a running [MoltBot](https://github.com/moltbot/moltbot) gateway (v0.8+).

## Quick Start

```sh
# 1. Point MoltNotch at your gateway (asks URL, auth token, SSH tunnel)
moltnotch setup

# 2. Launch the app
open build/derived/Build/Products/Release/MoltNotch.app

# 3. Press Ctrl+Space - that's it
```

Your auth token lives in `~/.moltbot/moltbot.json` → `gateway.auth.token` on the gateway host. The setup wizard will ask for it.

### macOS Permissions

On first launch, macOS will ask for **Screen Recording** access. Grant it, then relaunch. You'll also want **Accessibility** for the global hotkey:

| Permission | What it enables | Without it |
|------------|-----------------|------------|
| **Accessibility** | Ctrl+Space hotkey | Click the ✦ menu bar icon instead |
| **Screen Recording** | Screenshot attachments | Screenshot sends fail with an error |

System Settings → Privacy & Security → grant both → relaunch.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **Ctrl+Space** | Toggle popup |
| **Enter** | Send message |
| **Tab** | Toggle screenshot attachment (📷 icon appears) |
| **Shift+Enter** | Send with screenshot (always) |
| **Ctrl × 2** | Clear visible chat (backend session preserved) |
| **Escape** | Stop stream → clear input → dismiss (cascading) |

## Configuration

`~/.moltnotch.toml` - created by `moltnotch setup`, or edit by hand:

```toml
[gateway]
url = "ws://127.0.0.1:18789"
token = "your-auth-token"
health-check-interval = 15
reconnect-max-attempts = 10

[hotkey]
key = "space"
modifiers = ["control"]

# Optional - remote gateway behind SSH
[tunnel]
host = "myserver.example.com"
user = "username"
port = 22
remote-port = 18789
local-port = 18789
```

### Finding Your Auth Token

MoltBot always requires auth. The onboarding wizard (`moltbot onboard`) generates a token by default, even on loopback.

| Auth Mode | Where to find it |
|-----------|------------------|
| `token` (default) | `gateway.auth.token` in `~/.moltbot/moltbot.json`, or `CLAWDBOT_GATEWAY_TOKEN` env var |
| `password` | `gateway.auth.password` in `~/.moltbot/moltbot.json`, or `CLAWDBOT_GATEWAY_PASSWORD` env var |

Generate a fresh token: `moltbot doctor --generate-gateway-token`

MoltNotch sends the credential as both `auth.password` and `auth.token` in the connect handshake, so it works regardless of gateway auth mode.

> **Tip:** "Gateway disconnected" right after connecting? Wrong token. Check `~/.moltbot/moltbot.json` on the gateway host.

## Troubleshooting

```sh
moltnotch doctor    # checks config, TCP, WebSocket, SSH
```

| Symptom | Fix |
|---------|-----|
| "Not connected to gateway" | Start your MoltBot gateway, run `moltnotch doctor` |
| Connects then disconnects | Wrong auth token - see [Finding Your Auth Token](#finding-your-auth-token) |
| Ctrl+Space doesn't work | Grant Accessibility permission, relaunch |
| Screenshot sends fail | Grant Screen Recording permission, relaunch |
| WebSocket fails after TCP passes | Upgrade to MoltBot gateway v0.8+ |
| "Config not found" | Run `moltnotch setup` |
| Can't find the app | It's a menu bar app - look for ✦ in the top-right |

## Agent-Assisted Setup

Want an AI agent (Claude Code, Codex, OpenCode, etc.) to walk you through the entire setup interactively? Point it at the setup prompt:

```
Use the instructions in SETUP_AGENT_PROMPT.md to help me set up MoltNotch and MoltBot from scratch.
```

The prompt covers both MoltBot gateway and MoltNotch client setup, with verification at each stage. See [`SETUP_AGENT_PROMPT.md`](SETUP_AGENT_PROMPT.md).

## Building a Release DMG

```sh
./Scripts/build-release.sh    # outputs build/MoltNotch.dmg
```

## License

MIT - [Sohail Mohammad](https://github.com/Sohailm25)
