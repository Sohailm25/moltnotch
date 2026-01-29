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
func dim(_ text: String) -> String { "\u{001B}[2m\(text)\u{001B}[0m" }

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

func promptYesNo(_ message: String, defaultYes: Bool = true) -> Bool {
    let hint = defaultYes ? "Y/n" : "y/N"
    print("\(message) [\(hint)]: ", terminator: "")
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !line.isEmpty else {
        return defaultYes
    }
    return line == "y" || line == "yes"
}

// MARK: - Setup

func runSetup() {
    print("")
    print(bold("🔧 MoltNotch Setup"))
    print("─────────────────────────────────")
    print("")
    print("This will create \(cyan("~/.moltnotch.toml")) to connect MoltNotch to your MoltBot gateway.")
    print("")

    let gatewayURL = prompt("Gateway URL", defaultValue: "ws://127.0.0.1:18789")
    let token = prompt("Auth token " + dim("(from your MoltBot config, or press Enter to skip)"), defaultValue: "")

    var tunnelConfig: String? = nil

    let needsTunnel = promptYesNo("Is the gateway on a remote server behind SSH?", defaultYes: false)
    if needsTunnel {
        print("")
        print(dim("  MoltNotch will open an SSH tunnel automatically on launch."))
        print("")
        let sshHost = prompt("SSH host (IP or hostname)")
        let sshUser = prompt("SSH user")
        let sshPort = prompt("SSH port", defaultValue: "22")
        let remotePort = prompt("Remote gateway port", defaultValue: "18789")
        let localPort = prompt("Local port to forward to", defaultValue: "18789")

        tunnelConfig = """

        [tunnel]
        host = "\(sshHost)"
        user = "\(sshUser)"
        port = \(sshPort)
        remote-port = \(remotePort)
        local-port = \(localPort)
        """
    }

    var toml = """
    [gateway]
    url = "\(gatewayURL)"
    token = "\(token)"
    health-check-interval = 15
    reconnect-max-attempts = 10

    [hotkey]
    key = "space"
    modifiers = ["control"]
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
    let testURL = needsTunnel ? "ws://127.0.0.1:\(tunnelConfig != nil ? "18789" : "18789")" : gatewayURL
    let tcpOk = testTCPConnection(url: testURL)

    if tcpOk {
        testWebSocketHandshake(url: testURL, token: token)
    }

    print("")
    print(green("Setup complete!"))
    print("")
    print("Next steps:")
    print("  1. Launch \(bold("MoltNotch.app"))")
    print("  2. Press \(bold("Ctrl+Space")) to open the assistant")
    print("")
    print("If something isn't working, run: \(cyan("moltnotch doctor"))")
    print("")
}

func testTCPConnection(url urlString: String) -> Bool {
    guard let url = URL(string: urlString) else {
        print(red("✗") + " Invalid URL: \(urlString)")
        return false
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
        return false
    } else if success {
        print(green("✓") + " Gateway reachable at \(host):\(port)")
        return true
    } else {
        print(yellow("⚠") + " Could not reach \(host):\(port) — gateway may not be running yet")
        return false
    }
}

func testWebSocketHandshake(url urlString: String, token: String) {
    guard let url = URL(string: urlString) else { return }

    let semaphore = DispatchSemaphore(value: 0)
    var resultMessage: String? = nil
    var isOk = false

    let session = URLSession(configuration: .default)
    let task = session.webSocketTask(with: url)
    task.resume()

    task.receive { result in
        switch result {
        case .success(let message):
            if case .string(let text) = message, text.contains("connect.challenge") {
                isOk = true
                resultMessage = nil
            } else {
                resultMessage = "Unexpected response from gateway"
            }
        case .failure(let error):
            resultMessage = error.localizedDescription
        }
        task.cancel(with: .goingAway, reason: nil)
        semaphore.signal()
    }

    let timeout = DispatchTime.now() + .seconds(5)
    if semaphore.wait(timeout: timeout) == .timedOut {
        print(yellow("⚠") + " WebSocket handshake timed out")
        task.cancel(with: .goingAway, reason: nil)
    } else if isOk {
        print(green("✓") + " WebSocket handshake OK — gateway is responding")
    } else if let msg = resultMessage {
        print(yellow("⚠") + " WebSocket connected but: \(msg)")
    } else {
        print(green("✓") + " WebSocket connected to gateway")
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
        print("  Run \(cyan("moltnotch setup")) to create it.")
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
            print("  Auth token: \(green("set"))")
        } else {
            print("  Auth token: \(yellow("not set")) — may be required by your gateway")
        }

        let tcpOk = testTCPConnection(url: config.gateway.url)
        if tcpOk {
            testWebSocketHandshake(url: config.gateway.url, token: config.gateway.token ?? "")
        }

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
