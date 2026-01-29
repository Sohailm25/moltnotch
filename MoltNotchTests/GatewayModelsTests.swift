// ABOUTME: Tests for gateway frame encoding and decoding (protocol v3). Ported from Barik.
// ABOUTME: Verifies JSON serialization of outgoing requests and deserialization of incoming frames.

import XCTest
@testable import MoltNotch

final class GatewayModelsTests: XCTestCase {

    // MARK: - Outgoing Frame Encoding

    func testGatewayRequestEncodesCorrectJSON() throws {
        let params = ChatSendParams(
            sessionKey: "sess-1",
            message: "hello",
            attachments: nil,
            idempotencyKey: "idem-1"
        )
        let request = GatewayRequest(id: "req-1", method: "chat.send", params: params)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "req")
        XCTAssertEqual(dict["id"] as? String, "req-1")
        XCTAssertEqual(dict["method"] as? String, "chat.send")
        XCTAssertNotNil(dict["params"])
    }

    func testConnectParamsEncodesProtocolVersion() throws {
        let clientInfo = ConnectParams.ClientInfo(
            id: GatewayClientId.macosApp,
            displayName: "MoltNotch",
            version: "1.0.0"
        )
        let params = ConnectParams(
            client: clientInfo,
            caps: [],
            role: "operator",
            scopes: ["operator.admin"],
            auth: ConnectParams.AuthInfo(password: "test-pw"),
            device: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["minProtocol"] as? Int, 3)
        XCTAssertEqual(dict["maxProtocol"] as? Int, 3)
        XCTAssertEqual(dict["role"] as? String, "operator")

        let client = dict["client"] as! [String: Any]
        XCTAssertEqual(client["id"] as? String, "moltnotch-macos")
        XCTAssertEqual(client["displayName"] as? String, "MoltNotch")
        XCTAssertEqual(client["version"] as? String, "1.0.0")
        XCTAssertEqual(client["platform"] as? String, "macOS")
        XCTAssertEqual(client["mode"] as? String, "webchat")

        let auth = dict["auth"] as! [String: Any]
        XCTAssertEqual(auth["password"] as? String, "test-pw")
    }

    func testChatSendParamsEncodesSessionKey() throws {
        let params = ChatSendParams(
            sessionKey: "key-abc",
            message: "test message",
            attachments: nil,
            idempotencyKey: "idem-xyz"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["sessionKey"] as? String, "key-abc")
        XCTAssertEqual(dict["message"] as? String, "test message")
        XCTAssertEqual(dict["idempotencyKey"] as? String, "idem-xyz")
    }

    func testChatSendParamsEncodesAttachments() throws {
        let attachment = ChatAttachment(
            type: "file",
            mimeType: "text/plain",
            fileName: "test.txt",
            content: "SGVsbG8="
        )
        let params = ChatSendParams(
            sessionKey: "key-1",
            message: "see attached",
            attachments: [attachment],
            idempotencyKey: "idem-2"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let attachments = dict["attachments"] as? [[String: Any]]
        XCTAssertNotNil(attachments)
        XCTAssertEqual(attachments?.count, 1)
        XCTAssertEqual(attachments?[0]["type"] as? String, "file")
        XCTAssertEqual(attachments?[0]["fileName"] as? String, "test.txt")
    }

    func testChatSendParamsOmitsNilAttachments() throws {
        let params = ChatSendParams(
            sessionKey: "key-1",
            message: "no attachments",
            attachments: nil,
            idempotencyKey: "idem-3"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let hasKey = dict.keys.contains("attachments")
        if hasKey {
            XCTAssertTrue(dict["attachments"] is NSNull)
        }
    }

    // MARK: - Incoming Frame Decoding

    func testResponseFrameDecodesOk() throws {
        let json = """
        {"type":"res","id":"abc","ok":true}
        """
        let data = json.data(using: .utf8)!
        let frame = try JSONDecoder().decode(ResponseFrame.self, from: data)

        XCTAssertEqual(frame.type, "res")
        XCTAssertEqual(frame.id, "abc")
        XCTAssertTrue(frame.ok)
        XCTAssertNil(frame.error)
    }

    func testResponseFrameDecodesError() throws {
        let json = """
        {"type":"res","id":"def","ok":false,"error":{"code":"RATE_LIMIT","message":"Too many requests","retryable":true,"retryAfterMs":5000}}
        """
        let data = json.data(using: .utf8)!
        let frame = try JSONDecoder().decode(ResponseFrame.self, from: data)

        XCTAssertEqual(frame.type, "res")
        XCTAssertEqual(frame.id, "def")
        XCTAssertFalse(frame.ok)
        XCTAssertNotNil(frame.error)
        XCTAssertEqual(frame.error?.code, "RATE_LIMIT")
        XCTAssertEqual(frame.error?.message, "Too many requests")
        XCTAssertEqual(frame.error?.retryable, true)
        XCTAssertEqual(frame.error?.retryAfterMs, 5000)
    }

    func testHelloOkFrameDecodes() throws {
        let json = """
        {
            "type": "hello-ok",
            "protocol": 3,
            "server": {"version": "1.2.3", "connId": "conn-abc"},
            "features": {"methods": ["chat.send", "chat.abort"], "events": ["chat", "tick"]},
            "policy": {"maxPayload": 65536, "maxBufferedBytes": 131072, "tickIntervalMs": 30000}
        }
        """
        let data = json.data(using: .utf8)!
        let frame = try JSONDecoder().decode(HelloOkFrame.self, from: data)

        XCTAssertEqual(frame.type, "hello-ok")
        XCTAssertEqual(frame.protocol, 3)
        XCTAssertEqual(frame.server.version, "1.2.3")
        XCTAssertEqual(frame.server.connId, "conn-abc")
        XCTAssertEqual(frame.features.methods, ["chat.send", "chat.abort"])
        XCTAssertEqual(frame.features.events, ["chat", "tick"])
        XCTAssertEqual(frame.policy.maxPayload, 65536)
        XCTAssertEqual(frame.policy.tickIntervalMs, 30000)
    }

    func testChatEventDecodesDelta() throws {
        let json = """
        {"runId":"run-1","sessionKey":"sess-1","seq":5,"state":"delta","message":{"role":"assistant","content":[{"type":"text","text":"Hello "}]}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatEvent.self, from: data)

        XCTAssertEqual(event.runId, "run-1")
        XCTAssertEqual(event.sessionKey, "sess-1")
        XCTAssertEqual(event.seq, 5)
        XCTAssertEqual(event.state, "delta")
        XCTAssertEqual(event.message?.content?.first?.text, "Hello ")
        XCTAssertNil(event.stopReason)
    }

    func testChatEventDecodesFinal() throws {
        let json = """
        {"runId":"run-1","sessionKey":"sess-1","seq":10,"state":"final","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]},"stopReason":"end_turn"}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(ChatEvent.self, from: data)

        XCTAssertEqual(event.state, "final")
        XCTAssertEqual(event.message?.content?.first?.text, "Done.")
        XCTAssertEqual(event.stopReason, "end_turn")
        XCTAssertNil(event.errorMessage)
    }

    func testEventFrameDecodesWithChatPayload() throws {
        let json = """
        {"type":"event","event":"chat","seq":1,"payload":{"runId":"run-1","sessionKey":"sess-1","seq":1,"state":"delta","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}}
        """
        let data = json.data(using: .utf8)!
        let frame = try JSONDecoder().decode(EventFrame.self, from: data)

        XCTAssertEqual(frame.type, "event")
        XCTAssertEqual(frame.event, "chat")
        XCTAssertNotNil(frame.chatEvent)
        XCTAssertEqual(frame.chatEvent?.runId, "run-1")
        XCTAssertEqual(frame.chatEvent?.message?.content?.first?.text, "Hi")
    }

    func testEventFrameIgnoresNonChatPayload() throws {
        let json = """
        {"type":"event","event":"tick","seq":42}
        """
        let data = json.data(using: .utf8)!
        let frame = try JSONDecoder().decode(EventFrame.self, from: data)

        XCTAssertEqual(frame.type, "event")
        XCTAssertEqual(frame.event, "tick")
        XCTAssertEqual(frame.seq, 42)
        XCTAssertNil(frame.chatEvent)
    }

    func testEventFrameDecodesConnectChallenge() throws {
        let json = """
        {"type":"event","event":"connect.challenge","payload":{"nonce":"abc-123","ts":1700000000000}}
        """
        let data = json.data(using: .utf8)!
        let frame = try JSONDecoder().decode(EventFrame.self, from: data)

        XCTAssertEqual(frame.event, "connect.challenge")
        XCTAssertEqual(frame.challengeNonce, "abc-123")
        XCTAssertNil(frame.chatEvent)
    }
}
