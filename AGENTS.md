# MoltNotch - Agent Setup Guide

Instructions for AI coding assistants (Claude Code, Codex, etc.) working on this repo.

## Project Overview

MoltNotch is a macOS notch assistant app. It opens a chat popup from the MacBook notch area, connected to a [MoltBot](https://github.com/moltbot/moltbot) gateway via WebSocket.

**Three build targets:**
- `MoltNotch` - The macOS app (SwiftUI + AppKit)
- `MoltNotchCLI` - CLI tool (`moltnotch setup`, `moltnotch doctor`)
- `MoltNotchTests` - Unit tests (56 tests)

## Build & Test

```sh
# Prerequisites
brew install xcodegen

# Generate Xcode project (REQUIRED after adding/removing source files)
cd /path/to/moltnotch
xcodegen generate

# Build both targets
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotch -configuration Debug
xcodebuild build -project MoltNotch.xcodeproj -scheme MoltNotchCLI -configuration Debug

# Run tests
xcodebuild test -project MoltNotch.xcodeproj -scheme MoltNotch -destination 'platform=macOS'

# Debug binaries land in:
#   build/derived/Build/Products/Debug/MoltNotch.app
#   build/derived/Build/Products/Debug/moltnotch
```

> **Important:** Always run `xcodegen generate` after adding or removing `.swift` files. The `project.yml` defines all targets, dependencies, and settings.

## Project Structure

```
MoltNotch/
  App/              - App entry point, AppDelegate
  Models/           - Config.swift (TOML config model), data types
  Services/         - GatewayConnection.swift (WebSocket client), SSHTunnel, ScreenCapture
  Views/            - SwiftUI views (NotchPanel, ChatView, etc.)
  Resources/        - Assets.xcassets, Info.plist

MoltNotchCLI/
  main.swift        - CLI entry point (setup wizard + doctor command)

MoltNotchTests/     - Unit tests

project.yml         - XcodeGen project definition
Package.resolved    - SPM dependency lock
```

## Key Files

| File | Purpose |
|------|---------|
| `MoltNotch/Services/GatewayConnection.swift` | WebSocket client - connect handshake, challenge-response auth, device pairing, chat events |
| `MoltNotch/Models/Config.swift` | `MoltNotchConfig` struct parsed from `~/.moltnotch.toml` |
| `MoltNotch/Services/SSHTunnelService.swift` | Auto-establishes SSH tunnel on launch if `[tunnel]` configured |
| `MoltNotchCLI/main.swift` | Setup wizard and doctor diagnostics |
| `project.yml` | XcodeGen spec - targets, dependencies, build settings |

## Architecture

### Connection Flow
1. App launches → reads `~/.moltnotch.toml`
2. If `[tunnel]` configured → opens SSH port forward (local → remote)
3. Opens WebSocket to gateway URL
4. Gateway sends `connect.challenge` with nonce
5. App signs nonce with Ed25519 device key, sends `connect` frame with:
   - `client.id: "moltnotch-macos"`
   - `role: "operator"`, `scopes: ["operator.admin"]`
   - `auth.password` (from config `token` field)
   - `device.id`, `device.publicKey`, `device.signature`
6. Gateway verifies auth + auto-approves device → sends `connect.ok`
7. Bidirectional chat via `chat.message` / `chat.response` frames

### Auth
The `token` field in `~/.moltnotch.toml` is sent as `auth.password` in the connect handshake. It works for both `password` and `token` auth modes on the gateway side. See `GatewayConnection.swift` lines 174-179.

## Configuration File

`~/.moltnotch.toml` - created by `moltnotch setup`:

```toml
[gateway]
url = "ws://127.0.0.1:18789"
token = "your-gateway-auth-token"
health-check-interval = 15
reconnect-max-attempts = 10

[hotkey]
key = "space"
modifiers = ["control"]

# Optional - for remote gateways behind SSH
[tunnel]
host = "server-ip-or-hostname"
user = "ssh-user"
port = 22
remote-port = 18789
local-port = 18789
```

### Where to Find the Auth Token

MoltBot always requires auth (token or password). The onboarding wizard generates a token by default.

- `gateway.auth.token` in `~/.moltbot/moltbot.json` on the gateway host
- `gateway.auth.password` in `~/.moltbot/moltbot.json` (if password mode)
- `CLAWDBOT_GATEWAY_TOKEN` or `CLAWDBOT_GATEWAY_PASSWORD` environment variables on the gateway host
- Generate a new token: `moltbot doctor --generate-gateway-token`

## Dependencies

Managed via Swift Package Manager (SPM), declared in `project.yml`:

| Package | Purpose |
|---------|---------|
| [HotKey](https://github.com/soffes/HotKey) | Global keyboard shortcut (Ctrl+Space) |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | Render markdown in chat responses |
| [TOMLDecoder](https://github.com/dduan/TOMLDecoder) | Parse `~/.moltnotch.toml` config file |

## Conventions

- **Swift 5.0**, macOS 14.0+ deployment target
- Every `.swift` file starts with two `// ABOUTME:` comment lines describing the file
- Debug logging uses `os.log` with subsystem `com.moltbot.MoltNotch`, gated behind `#if DEBUG`
- No `NSLog` in production builds
- Config file permissions: `chmod 0600` (set by setup wizard)
- No hardcoded secrets or credentials in source

## Common Tasks

### Adding a new source file
1. Create the `.swift` file in the appropriate directory
2. Add the `// ABOUTME:` header
3. Run `xcodegen generate`
4. Build to verify

### Changing the connect handshake
Edit `GatewayConnection.swift` - the `ConnectParams` struct and the `connect()` method. The gateway expects specific fields; check the MoltBot gateway protocol docs.

### Modifying the setup wizard
Edit `MoltNotchCLI/main.swift` - the `runSetup()` function. The wizard writes TOML directly as a string template.
