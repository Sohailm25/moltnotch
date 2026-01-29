// ABOUTME: Entry point for the moltnotch CLI tool.
// ABOUTME: Provides 'setup' wizard and 'doctor' diagnostic commands.

import Foundation
import TOMLDecoder

let configPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".moltnotch.toml")

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "help"

switch command {
case "setup":
    runSetup()
case "doctor":
    runDoctor()
default:
    printHelp()
}

// MARK: - ANSI Colors

func bold(_ text: String) -> String { "\u{001B}[1m\(text)\u{001B}[0m" }
func green(_ text: String) -> String { "\u{001B}[32m\(text)\u{001B}[0m" }
func yellow(_ text: String) -> String { "\u{001B}[33m\(text)\u{001B}[0m" }
func red(_ text: String) -> String { "\u{001B}[31m\(text)\u{001B}[0m" }
func cyan(_ text: String) -> String { "\u{001B}[36m\(text)\u{001B}[0m" }

func prompt(_ message: String, defaultValue: String? = nil) -> String {
    if let def = defaultValue {
        print("\(message) [\(cyan(def))]: ", terminator: "")
    } else {
        print("\(message): ", terminator: "")
    }
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
        return defaultValue ?? ""
    }
    return line
}

func promptChoice(_ message: String, options: [(key: String, label: String)]) -> String {
    print(message)
    for (i, option) in options.enumerated() {
        print("  \(cyan("\(i + 1)")) \(option.label)")
    }
    print("Choose [1-\(options.count)]: ", terminator: "")
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          let idx = Int(line), idx >= 1, idx <= options.count else {
        return options[0].key
    }
    return options[idx - 1].key
}

// MARK: - Setup

func runSetup() {
    print("")
    print(bold("🔧 MoltNotch Setup"))
    print("─────────────────────────────────")
    print("")

    let location = promptChoice("Where is your MoltBot gateway running?", options: [
        ("local", "On this computer (localhost)"),
        ("remote", "On a remote server")
    ])

    var gatewayURL: String
    var tunnelConfig: String? = nil

    if location == "local" {
        let port = prompt("Gateway port", defaultValue: "18789")
        gatewayURL = "ws://127.0.0.1:\(port)"
    } else {
        let method = promptChoice("Connection method?", options: [
            ("direct", "Direct WebSocket (server is publicly accessible)"),
            ("tunnel", "SSH tunnel (server is behind firewall)")
        ])

        if method == "direct" {
            gatewayURL = prompt("WebSocket URL (e.g. wss://myserver.com:18789)")
        } else {
            let sshHost = prompt("SSH host (e.g. myserver.com)")
            let sshUser = prompt("SSH user")
            let sshPort = prompt("SSH port", defaultValue: "22")
            let remotePort = prompt("Remote gateway port", defaultValue: "18789")
            let localPort = prompt("Local tunnel port", defaultValue: "18789")

            gatewayURL = "ws://127.0.0.1:\(localPort)"

            tunnelConfig = """

            [tunnel]
            host = "\(sshHost)"
            user = "\(sshUser)"
            port = \(sshPort)
            remote-port = \(remotePort)
            local-port = \(localPort)
            """
        }
    }

    let token = prompt("Gateway auth token (press Enter to skip)", defaultValue: "")

    let hotkeyKey = prompt("Hotkey key", defaultValue: "space")
    let hotkeyMod = prompt("Hotkey modifier (control/option/command)", defaultValue: "control")

    var toml = """
    [gateway]
    url = "\(gatewayURL)"
    token = "\(token)"
    health-check-interval = 15
    reconnect-max-attempts = 10

    [hotkey]
    key = "\(hotkeyKey)"
    modifiers = ["\(hotkeyMod)"]
    """

    if let tunnel = tunnelConfig {
        toml += tunnel
    }

    toml += "\n"

    do {
        try toml.write(to: configPath, atomically: true, encoding: .utf8)
        print("")
        print(green("✓") + " Config written to \(configPath.path)")
    } catch {
        print(red("✗") + " Failed to write config: \(error.localizedDescription)")
        exit(1)
    }

    print("")
    print(bold("Testing connection..."))
    testGatewayConnection(url: gatewayURL)

    print("")
    print(green("Setup complete!") + " Launch MoltNotch.app to get started.")
    print("")
}

func testGatewayConnection(url urlString: String) {
    guard let url = URL(string: urlString) else {
        print(red("✗") + " Invalid URL: \(urlString)")
        return
    }

    let host = url.host ?? "127.0.0.1"
    let port = url.port ?? 18789

    let semaphore = DispatchSemaphore(value: 0)
    var success = false

    let queue = DispatchQueue(label: "moltnotch.connection-test")
    queue.async {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            semaphore.signal()
            return
        }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        success = (result == 0)
        semaphore.signal()
    }

    let timeout = DispatchTime.now() + .seconds(5)
    if semaphore.wait(timeout: timeout) == .timedOut {
        print(yellow("⚠") + " Connection timed out to \(host):\(port)")
    } else if success {
        print(green("✓") + " Gateway reachable at \(host):\(port)")
    } else {
        print(yellow("⚠") + " Could not reach \(host):\(port) — gateway may not be running yet")
    }
}

// MARK: - Doctor

func runDoctor() {
    print("")
    print(bold("🩺 MoltNotch Doctor"))
    print("─────────────────────────────────")
    print("")

    let fm = FileManager.default
    if fm.fileExists(atPath: configPath.path) {
        print(green("✓") + " Config file exists: \(configPath.path)")
    } else {
        print(red("✗") + " Config file missing: \(configPath.path)")
        print("  Run `moltnotch setup` to create it.")
        exit(1)
    }

    do {
        let data = try Data(contentsOf: configPath)
        let decoder = TOMLDecoder()

        struct DoctorConfig: Decodable {
            var gateway: Gateway
            var tunnel: Tunnel?

            struct Gateway: Decodable {
                var url: String
                var token: String?
            }
            struct Tunnel: Decodable {
                var host: String
                var user: String
            }
        }

        let config = try decoder.decode(DoctorConfig.self, from: data)
        print(green("✓") + " Config parses successfully")
        print("  Gateway URL: \(config.gateway.url)")
        if let token = config.gateway.token, !token.isEmpty {
            print("  Auth token: (set)")
        } else {
            print("  Auth token: (not set)")
        }

        testGatewayConnection(url: config.gateway.url)

        if let tunnel = config.tunnel {
            print("")
            print("  SSH tunnel: \(tunnel.user)@\(tunnel.host)")
            testSSHHost(host: tunnel.host)
        }

    } catch {
        print(red("✗") + " Config parse failed: \(error.localizedDescription)")
        exit(1)
    }

    print("")
}

func testSSHHost(host: String) {
    let semaphore = DispatchSemaphore(value: 0)
    var success = false

    let queue = DispatchQueue(label: "moltnotch.ssh-test")
    queue.async {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            semaphore.signal()
            return
        }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(22).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        success = (result == 0)
        semaphore.signal()
    }

    let timeout = DispatchTime.now() + .seconds(5)
    if semaphore.wait(timeout: timeout) == .timedOut {
        print(yellow("⚠") + " SSH host timed out: \(host)")
    } else if success {
        print(green("✓") + " SSH host reachable: \(host)")
    } else {
        print(yellow("⚠") + " SSH host unreachable: \(host)")
    }
}

// MARK: - Help

func printHelp() {
    print("")
    print(bold("moltnotch") + " — MoltBot Notch Assistant CLI")
    print("")
    print("Commands:")
    print("  \(cyan("setup"))    Interactive setup wizard")
    print("  \(cyan("doctor"))   Check configuration and connectivity")
    print("  \(cyan("help"))     Show this help message")
    print("")
}
