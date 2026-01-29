# MoltNotch

A macOS notch assistant that connects to your [MoltBot](https://github.com/moltbot/moltbot) gateway. Chat with your AI assistant from a sleek popup that emerges from your MacBook's notch.

MoltNotch runs as a **menu bar app** — look for the ✦ icon in your menu bar, not a window. Press **Ctrl+Space** (or click the icon) to open the chat popup.

## Requirements

- macOS 14.0+ (macOS 26 for Liquid Glass effects)
- Xcode 16+ (for ScreenCaptureKit APIs)
- [Homebrew](https://brew.sh) (to install xcodegen)
- A running [MoltBot](https://github.com/moltbot/moltbot) gateway (v0.8+)

## Quick Start

### 1. Build from source

```sh
brew install xcodegen

git clone https://github.com/moltbot/moltnotch.git
cd moltnotch
xcodegen generate
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotch -configuration Release -derivedDataPath build/derived
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotchCLI -configuration Release -derivedDataPath build/derived
```

After building, the binaries are at:
- **App:** `build/derived/Build/Products/Release/MoltNotch.app`
- **CLI:** `build/derived/Build/Products/Release/moltnotch`

### 2. Install the CLI

The CLI (`moltnotch`) provides the setup wizard and diagnostics. Copy it somewhere on your PATH:

```sh
cp build/derived/Build/Products/Release/moltnotch /usr/local/bin/
```

### 3. Run the setup wizard

The wizard asks three questions — gateway URL, auth token, and whether you need an SSH tunnel:

```sh
moltnotch setup
```

This writes `~/.moltnotch.toml` and tests both TCP reachability and WebSocket handshake with your gateway.

### 4. Grant macOS permissions

MoltNotch needs two macOS permissions to function properly. Open **System Settings → Privacy & Security** and enable MoltNotch under:

| Permission | Why | What breaks without it |
|------------|-----|------------------------|
| **Accessibility** | Global hotkey (Ctrl+Space) | Hotkey won't trigger — you can only open the popup by clicking the menu bar icon |
| **Screen Recording** | Screenshot attachment feature | Screenshot sends will fail silently or show an error |

> **Note:** macOS requires you to **relaunch the app** after granting either permission.

On first launch, MoltNotch will prompt for Screen Recording permission automatically. For Accessibility, you may need to add the app manually (click `+`, navigate to `MoltNotch.app`).

### 5. Launch

```sh
open build/derived/Build/Products/Release/MoltNotch.app
```

Or move `MoltNotch.app` to `/Applications` and launch from there. Press **Ctrl+Space** to open the chat popup.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Ctrl+Space** | Toggle the chat popup |
| **Enter** | Send message |
| **Tab** | Toggle screenshot attachment (cyan 📷 icon appears in input field) |
| **Shift+Enter** | Send message with screenshot (regardless of Tab toggle) |
| **Ctrl tap twice** | Clear visible chat (first tap shows confirmation, second clears). Backend conversation is preserved. |
| **Escape** | Stop streaming → clear input → dismiss popup (cascading) |

## Configuration

MoltNotch reads from `~/.moltnotch.toml`. The setup wizard generates this automatically, but you can edit it by hand:

```toml
[gateway]
url = "ws://127.0.0.1:18789"
token = "your-auth-token"
health-check-interval = 15
reconnect-max-attempts = 10

[hotkey]
key = "space"
modifiers = ["control"]
```

The default gateway port is **18789**. If your gateway runs locally, you likely don't need to change the URL.

### Finding Your Auth Token

MoltBot **always requires authentication** — the onboarding wizard (`moltbot onboard`) generates a token by default, even on loopback. Find it in one of these places:

| Gateway Auth Mode | Where to Find the Credential |
|-------------------|------------------------------|
| `token` (default) | `gateway.auth.token` in `~/.moltbot/moltbot.json`, or `CLAWDBOT_GATEWAY_TOKEN` env var |
| `password` | `gateway.auth.password` in `~/.moltbot/moltbot.json`, or `CLAWDBOT_GATEWAY_PASSWORD` env var |

You can also generate a new token: `moltbot doctor --generate-gateway-token`.

Set whichever credential your gateway uses as `token = "..."` in `~/.moltnotch.toml` under `[gateway]`. MoltNotch sends it as both `auth.password` and `auth.token` in the connect handshake, so it works regardless of mode.

> **Tip:** If you see "Gateway disconnected" after connecting, the token is likely missing or wrong. Check `gateway.auth.token` in `~/.moltbot/moltbot.json` on the gateway host.

### SSH Tunnel (Advanced)

If your gateway runs on a remote machine behind a firewall, add a `[tunnel]` section and MoltNotch will automatically establish an SSH tunnel on launch:

```toml
[tunnel]
host = "myserver.example.com"
user = "username"
port = 22
remote-port = 18789
local-port = 18789
```

## Troubleshooting

Run the diagnostics command:

```sh
moltnotch doctor
```

This checks:
- Config file exists and parses correctly
- Gateway is reachable (TCP)
- WebSocket handshake succeeds (protocol-level)
- SSH host is reachable (if tunnel configured)

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Not connected to gateway" | Gateway not running or unreachable | Start your MoltBot gateway, then run `moltnotch doctor` |
| Connects then immediately disconnects | Auth token/password missing or wrong | Check [Finding Your Auth Token](#finding-your-auth-token) — set the correct credential in `~/.moltnotch.toml` |
| Ctrl+Space doesn't open popup | Accessibility permission not granted | System Settings → Privacy & Security → Accessibility → enable MoltNotch, then relaunch |
| Screenshot sends fail or show error | Screen Recording permission not granted | System Settings → Privacy & Security → Screen Recording → enable MoltNotch, then relaunch |
| TCP passes but WebSocket fails | Wrong port, or gateway hasn't registered MoltNotch as a client | Ensure your MoltBot gateway is v0.8+ (includes `moltnotch-macos` client ID) |
| "Config not found" | Missing `~/.moltnotch.toml` | Run `moltnotch setup` |
| App doesn't appear anywhere | MoltNotch is a menu bar app, not a windowed app | Look for the ✦ icon in the menu bar (top-right of screen) |

## Building a Release DMG

To build a distributable DMG with both the app and CLI:

```sh
./Scripts/build-release.sh
```

Output: `build/MoltNotch.dmg`

## License

[MIT](LICENSE)
