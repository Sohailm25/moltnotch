// ABOUTME: Configuration model parsed from ~/.moltnotch.toml.
// ABOUTME: Defines gateway, tunnel, and hotkey settings with sensible defaults.

import Foundation
import TOMLDecoder

struct MoltNotchConfig: Decodable {
    var gateway: GatewayConfig
    var tunnel: TunnelConfig?
    var hotkey: HotkeyConfig?

    struct GatewayConfig: Decodable {
        var url: String
        var token: String?
        var healthCheckInterval: Int?
        var reconnectMaxAttempts: Int?
        var reconnectBaseDelay: Double?
        var reconnectMaxDelay: Double?

        enum CodingKeys: String, CodingKey {
            case url, token
            case healthCheckInterval = "health-check-interval"
            case reconnectMaxAttempts = "reconnect-max-attempts"
            case reconnectBaseDelay = "reconnect-base-delay"
            case reconnectMaxDelay = "reconnect-max-delay"
        }
    }

    struct TunnelConfig: Decodable {
        var host: String
        var user: String
        var port: Int?
        var remotePort: Int?
        var localPort: Int?

        enum CodingKeys: String, CodingKey {
            case host, user, port
            case remotePort = "remote-port"
            case localPort = "local-port"
        }
    }

    struct HotkeyConfig: Decodable {
        var key: String?
        var modifiers: [String]?
    }

    static func configFilePath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".moltnotch.toml")
    }

    static func load() throws -> MoltNotchConfig {
        let path = configFilePath()
        let data = try Data(contentsOf: path)
        let decoder = TOMLDecoder()
        return try decoder.decode(MoltNotchConfig.self, from: data)
    }
}
