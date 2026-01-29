// ABOUTME: WebSocket protocol frame types for the gateway (protocol v3). Ported from Barik.
// ABOUTME: Encodes outgoing requests and decodes incoming events/responses.

import Foundation

// MARK: - Outgoing Frames

struct GatewayRequest<P: Encodable>: Encodable {
    let type: String = "req"
    let id: String
    let method: String
    let params: P
}

// MARK: - Connect

struct ConnectParams: Encodable {
    let minProtocol: Int = 3
    let maxProtocol: Int = 3
    let client: ClientInfo
    let caps: [String]
    let role: String
    let scopes: [String]
    let auth: AuthInfo?
    let device: DeviceInfo?

    struct ClientInfo: Encodable {
        let id: String
        let displayName: String?
        let version: String
        let platform: String = "macOS"
        let mode: String = "webchat"
    }

    struct AuthInfo: Encodable {
        let password: String?
        let token: String?

        init(password: String? = nil, token: String? = nil) {
            self.password = password
            self.token = token
        }
    }

    struct DeviceInfo: Encodable {
        let id: String
        let publicKey: String
        let signature: String
        let signedAt: Int
        let nonce: String?
    }
}

/// Known gateway client IDs (must match server enum).
enum GatewayClientId {
    static let macosApp = "moltnotch-macos"
    static let webchatUI = "webchat-ui"
    static let webchat = "webchat"
}

// MARK: - Chat

struct ChatSendParams: Encodable {
    let sessionKey: String
    let message: String
    let attachments: [ChatAttachment]?
    let idempotencyKey: String
}

struct ChatAttachment: Encodable {
    let type: String
    let mimeType: String
    let fileName: String
    let content: String
}

struct ChatAbortParams: Encodable {
    let sessionKey: String
    let runId: String?
}

struct ChatHistoryParams: Encodable {
    let sessionKey: String
    let limit: Int?
}

// MARK: - Incoming Frames

struct GatewayFrame: Decodable {
    let type: String
}

struct HelloOkFrame: Decodable {
    let type: String
    let `protocol`: Int
    let server: ServerInfo
    let features: Features
    let policy: Policy
    let auth: HelloAuth?

    struct ServerInfo: Decodable {
        let version: String
        let connId: String
    }

    struct Features: Decodable {
        let methods: [String]
        let events: [String]
    }

    struct Policy: Decodable {
        let maxPayload: Int
        let maxBufferedBytes: Int
        let tickIntervalMs: Int
    }

    struct HelloAuth: Decodable {
        let deviceToken: String?
        let role: String?
        let scopes: [String]?
    }
}

struct ResponseFrame: Decodable {
    let type: String
    let id: String
    let ok: Bool
    let payload: AnyCodable?
    let error: GatewayError?
}

struct GatewayError: Decodable {
    let code: String
    let message: String
    let retryable: Bool?
    let retryAfterMs: Int?
}

/// Chat event from the gateway. The `message` field is an object (role + content array),
/// not a plain string.
struct ChatEvent: Decodable {
    let runId: String
    let sessionKey: String
    let seq: Int
    let state: String
    let message: ChatEventMessage?
    let errorMessage: String?
    let stopReason: String?
}

/// The message object inside a chat event.
struct ChatEventMessage: Decodable {
    let role: String?
    let content: [ChatContentBlock]?
}

/// A content block inside a chat event message (text, image, etc.).
struct ChatContentBlock: Decodable {
    let type: String
    let text: String?
}

struct EventFrame {
    let type: String
    let event: String
    let seq: Int?
    let chatEvent: ChatEvent?
    let challengeNonce: String?
}

extension EventFrame: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, event, seq, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        event = try container.decode(String.self, forKey: .event)
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)

        if event == "chat" {
            chatEvent = try container.decodeIfPresent(ChatEvent.self, forKey: .payload)
            challengeNonce = nil
        } else if event == "connect.challenge" {
            chatEvent = nil
            let challengePayload = try container.decodeIfPresent(ChallengePayload.self, forKey: .payload)
            challengeNonce = challengePayload?.nonce
        } else {
            chatEvent = nil
            challengeNonce = nil
        }
    }
}

private struct ChallengePayload: Decodable {
    let nonce: String
    let ts: Int?
}

// MARK: - AnyCodable helper for dynamic JSON payloads

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }
}
