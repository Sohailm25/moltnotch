# MoltNotch

A macOS notch assistant that connects to your [MoltBot](https://github.com/moltbot/moltbot) gateway. Chat with your AI assistant from a sleek popup that emerges from your MacBook's notch.

## Requirements

- macOS 14.0+ (macOS 26 for Liquid Glass effects)
- A running [MoltBot](https://github.com/moltbot/moltbot) gateway (v0.8+)

## Quick Start

1. **Start your MoltBot gateway** on the machine where it's installed.
2. **Download MoltNotch** from [Releases](https://github.com/moltbot/moltnotch/releases), or [build from source](#building-from-source).
3. **Run the setup wizard** — it asks three questions (gateway URL, auth token, SSH tunnel yes/no):
   ```sh
   moltnotch setup
   ```
4. **Launch MoltNotch.app**
5. **Press Ctrl+Space** to open the notch popup

The setup wizard writes `~/.moltnotch.toml` and tests both TCP reachability and WebSocket handshake with your gateway.

## Configuration

MoltNotch reads from `~/.moltnotch.toml`. The setup wizard generates this automatically, but you can also edit it by hand:

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
| TCP passes but WebSocket fails | Wrong port, or gateway hasn't registered MoltNotch as a client | Ensure your MoltBot gateway is v0.8+ (includes `moltnotch-macos` client ID) |
| "Config not found" | Missing `~/.moltnotch.toml` | Run `moltnotch setup` |

## Building from Source

```sh
brew install xcodegen

git clone https://github.com/moltbot/moltnotch.git
cd moltnotch
xcodegen generate
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotch -configuration Release
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotchCLI -configuration Release
```

## License

[MIT](LICENSE)
