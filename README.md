# MoltNotch

A macOS notch assistant that connects to your [MoltBot](https://github.com/moltbot/moltbot) gateway. Chat with your AI assistant from a sleek popup that emerges from your MacBook's notch.

## Requirements

- macOS 14.0+ (macOS 26 for Liquid Glass effects)
- A running [MoltBot](https://github.com/moltbot/moltbot) gateway instance

## Quick Start

1. Download MoltNotch from [Releases](https://github.com/moltbot/moltnotch/releases)
2. Run the setup wizard:
   ```sh
   moltnotch setup
   ```
3. Launch **MoltNotch.app**
4. Press **Ctrl+Space** to open the notch popup

## Configuration

MoltNotch reads from `~/.moltnotch.toml`:

```toml
[gateway]
url = "ws://127.0.0.1:18789"
token = "your-auth-token"
health-check-interval = 15
reconnect-max-attempts = 10

[hotkey]
key = "space"
modifiers = ["control"]

# Optional — only needed for SSH tunnel connections
[tunnel]
host = "myserver.example.com"
user = "username"
port = 22
remote-port = 18789
local-port = 18789
```

### Connection Modes

**Local**: Gateway running on localhost — set `url = "ws://127.0.0.1:18789"`.

**Direct remote**: Gateway publicly accessible — set `url = "wss://myserver.com:18789"`.

**SSH tunnel**: Gateway behind a firewall — configure the `[tunnel]` section and MoltNotch will automatically establish an SSH tunnel before connecting.

## Troubleshooting

Run the diagnostics command:

```sh
moltnotch doctor
```

This checks:
- Config file exists and parses correctly
- Gateway is reachable
- SSH host is reachable (if tunnel configured)

## Building from Source

```sh
# Install xcodegen
brew install xcodegen

# Clone and build
git clone https://github.com/moltbot/moltnotch.git
cd moltnotch
xcodegen generate
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotch -configuration Release

# Build the CLI tool
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotchCLI -configuration Release
```

## License

[MIT](LICENSE)
