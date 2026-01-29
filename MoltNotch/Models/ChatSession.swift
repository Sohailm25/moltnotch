// ABOUTME: In-memory chat session model for the MoltBot assistant.
// ABOUTME: Tracks connection state, messages, and active streaming runs.

import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case tunnelConnecting
    case tunnelConnected
    case connecting
    case connected
    case error(String)
}

enum MessageRole {
    case user
    case assistant
}

enum MessageState: Equatable {
    case sending
    case streaming
    case complete
    case error(String)
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var state: MessageState
    let hasScreenshot: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        state: MessageState,
        hasScreenshot: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.state = state
        self.hasScreenshot = hasScreenshot
    }
}

struct ChatSession {
    let sessionKey: String
    var messages: [ChatMessage]
    var activeRunId: String?

    var isStreaming: Bool {
        activeRunId != nil
    }

    init(sessionKey: String = "main") {
        self.sessionKey = sessionKey
        self.messages = []
        self.activeRunId = nil
    }
}
