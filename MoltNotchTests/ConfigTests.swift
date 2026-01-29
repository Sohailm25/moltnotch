// ABOUTME: Tests for MoltNotchConfig TOML parsing and defaults.
// ABOUTME: Verifies minimal/full TOML, missing fields, and config file path.

import XCTest
import TOMLDecoder
@testable import MoltNotch

final class ConfigTests: XCTestCase {

    private func parseTOML(_ toml: String) throws -> MoltNotchConfig {
        let data = toml.data(using: .utf8)!
        let decoder = TOMLDecoder()
        return try decoder.decode(MoltNotchConfig.self, from: data)
    }

    func testMinimalTOMLParses() throws {
        let toml = """
        [gateway]
        url = "ws://localhost:8080"
        """
        let config = try parseTOML(toml)
        XCTAssertEqual(config.gateway.url, "ws://localhost:8080")
        XCTAssertNil(config.gateway.token)
        XCTAssertNil(config.tunnel)
        XCTAssertNil(config.hotkey)
    }

    func testFullTOMLParses() throws {
        let toml = """
        [gateway]
        url = "ws://example.com:9000"
        token = "secret-token"
        health-check-interval = 30
        reconnect-max-attempts = 5
        reconnect-base-delay = 2.0
        reconnect-max-delay = 60.0

        [tunnel]
        host = "myhost.example.com"
        user = "testuser"
        port = 2222
        remote-port = 19000
        local-port = 19000

        [hotkey]
        key = "space"
        modifiers = ["control", "option"]
        """
        let config = try parseTOML(toml)

        XCTAssertEqual(config.gateway.url, "ws://example.com:9000")
        XCTAssertEqual(config.gateway.token, "secret-token")
        XCTAssertEqual(config.gateway.healthCheckInterval, 30)
        XCTAssertEqual(config.gateway.reconnectMaxAttempts, 5)
        XCTAssertEqual(config.gateway.reconnectBaseDelay, 2.0)
        XCTAssertEqual(config.gateway.reconnectMaxDelay, 60.0)

        XCTAssertEqual(config.tunnel?.host, "myhost.example.com")
        XCTAssertEqual(config.tunnel?.user, "testuser")
        XCTAssertEqual(config.tunnel?.port, 2222)
        XCTAssertEqual(config.tunnel?.remotePort, 19000)
        XCTAssertEqual(config.tunnel?.localPort, 19000)

        XCTAssertEqual(config.hotkey?.key, "space")
        XCTAssertEqual(config.hotkey?.modifiers, ["control", "option"])
    }

    func testMissingGatewayURLThrows() {
        let toml = """
        [tunnel]
        host = "example.com"
        user = "test"
        """
        XCTAssertThrowsError(try parseTOML(toml))
    }

    func testConfigFilePathIsHomeDotMoltnotch() {
        let path = MoltNotchConfig.configFilePath()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expected = home.appendingPathComponent(".moltnotch.toml")
        XCTAssertEqual(path, expected)
    }

    func testOptionalFieldsDefaultToNil() throws {
        let toml = """
        [gateway]
        url = "ws://localhost:8080"
        """
        let config = try parseTOML(toml)
        XCTAssertNil(config.tunnel)
        XCTAssertNil(config.hotkey)
        XCTAssertNil(config.gateway.token)
        XCTAssertNil(config.gateway.healthCheckInterval)
        XCTAssertNil(config.gateway.reconnectMaxAttempts)
        XCTAssertNil(config.gateway.reconnectBaseDelay)
        XCTAssertNil(config.gateway.reconnectMaxDelay)
    }
}
