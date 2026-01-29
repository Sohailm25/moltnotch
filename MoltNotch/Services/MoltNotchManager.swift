// ABOUTME: Central orchestrator for MoltNotch, managing connection, chat session, and screen capture.
// ABOUTME: ObservableObject that owns ConnectionManager, ChatSession, and message lifecycle.

import Foundation
import Combine
import SwiftUI

class MoltNotchManager: ObservableObject {
    static let shared = MoltNotchManager()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var session = ChatSession()
    @Published var reconnectAttempt: Int = 0

    private var connectionManager: ConnectionManager?
    private var messageQueue: [String] = []
    private var cancellables = Set<AnyCancellable>()

    var isStreaming: Bool { session.isStreaming }
    var errorMessage: String? {
        if case .error(let msg) = connectionState { return msg }
        return nil
    }

    private init() {}

    /// Test-only initializer that skips config loading
    init(connectionManager: ConnectionManager?) {
        self.connectionManager = connectionManager
    }

    // MARK: - Connection

    func startConnection() {
        guard let config = try? MoltNotchConfig.load() else {
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .error("Config not found — run `moltnotch setup`")
            }
            return
        }

        let cm = ConnectionManager(config: config)
        self.connectionManager = cm

        cm.onChatEvent = { [weak self] event in
            self?.handleChatEvent(event)
        }

        cm.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                if case .connected = state {
                    self?.reconnectAttempt = 0
                } else if case .error = state {
                    self?.reconnectAttempt += 1
                    // If streaming was interrupted, mark last assistant message
                    if self?.session.isStreaming == true {
                        if let lastIndex = self?.lastAssistantMessageIndex() {
                            self?.session.messages[lastIndex].state = .error("Connection interrupted")
                        }
                        self?.session.activeRunId = nil
                    }
                }
            }
            .store(in: &cancellables)

        cm.connect()
    }

    func disconnect() {
        connectionManager?.disconnect()
        connectionManager = nil
        cancellables.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .disconnected
        }
    }

    // MARK: - Send Message

    func sendMessage(_ text: String, includeScreenshot: Bool = false) {
        if session.isStreaming {
            messageQueue.append(text)
            return
        }

        let userMessage = ChatMessage(role: .user, content: text, state: .sending, hasScreenshot: includeScreenshot)
        DispatchQueue.main.async { [weak self] in
            self?.session.messages.append(userMessage)
        }

        var attachments: [ChatAttachment]? = nil
        if includeScreenshot {
            NSLog("[MoltNotchManager] includeScreenshot=true, attempting capture")
            if let base64 = ScreenCaptureService.captureAsBase64() {
                NSLog("[MoltNotchManager] screenshot captured, base64 length=\(base64.count)")
                attachments = [ChatAttachment(
                    type: "screenshot",
                    mimeType: "image/jpeg",
                    fileName: "screen-capture.jpg",
                    content: base64
                )]
            }
        }

        let params = ChatSendParams(
            sessionKey: session.sessionKey,
            message: text,
            attachments: attachments,
            idempotencyKey: UUID().uuidString
        )

        guard let gateway = connectionManager?.gateway else {
            DispatchQueue.main.async { [weak self] in
                self?.markLastUserMessageError("No gateway connection")
            }
            return
        }

        gateway.send(method: "chat.send", params: params) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    if response.ok {
                        self.markLastUserMessageComplete()
                        let assistantMessage = ChatMessage(
                            role: .assistant,
                            content: "",
                            state: .streaming
                        )
                        self.session.messages.append(assistantMessage)
                        self.session.activeRunId = response.id
                    } else {
                        let errorMsg = response.error?.message ?? "Request failed"
                        self.markLastUserMessageError(errorMsg)
                    }
                case .failure(let error):
                    self.markLastUserMessageError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Chat Event Handling

    func handleChatEvent(_ event: ChatEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let lastIdx = self.lastAssistantMessageIndex()

            switch event.state {
            case "delta":
                if let lastIndex = lastIdx {
                    let text = self.extractTextFromMessage(event.message)
                    // Gateway sends cumulative text in each delta, not incremental
                    self.session.messages[lastIndex].content = text
                }

            case "final":
                if let lastIndex = lastIdx {
                    let text = self.extractTextFromMessage(event.message)
                    if !text.isEmpty {
                        self.session.messages[lastIndex].content = text
                    }
                    self.session.messages[lastIndex].state = .complete
                }
                self.session.activeRunId = nil
                self.processMessageQueue()

            case "aborted":
                if let lastIndex = lastIdx {
                    self.session.messages[lastIndex].state = .complete
                }
                self.session.activeRunId = nil
                self.processMessageQueue()

            case "error":
                if let lastIndex = lastIdx {
                    let errorMsg = event.errorMessage ?? "Unknown error"
                    self.session.messages[lastIndex].state = .error(errorMsg)
                }
                self.session.activeRunId = nil
                self.processMessageQueue()

            default:
                break
            }
        }
    }

    private func extractTextFromMessage(_ message: ChatEventMessage?) -> String {
        guard let message = message else { return "" }
        guard let content = message.content else { return "" }
        return content.compactMap { block in
            block.type == "text" ? block.text : nil
        }.joined()
    }

    func abortStream() {
        guard let runId = session.activeRunId else { return }
        let params = ChatAbortParams(sessionKey: session.sessionKey, runId: runId)
        connectionManager?.gateway?.send(method: "chat.abort", params: params) { _ in }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let lastIndex = self.lastAssistantMessageIndex() {
                self.session.messages[lastIndex].state = .complete
            }
            self.session.activeRunId = nil
        }
    }

    // MARK: - Panel

    func dismissPanel() {
        NotchPanelManager.hide()
    }

    // MARK: - Helpers

    private func lastAssistantMessageIndex() -> Int? {
        return session.messages.lastIndex(where: { $0.role == .assistant })
    }

    private func markLastUserMessageComplete() {
        if let idx = session.messages.lastIndex(where: { $0.role == .user }) {
            session.messages[idx].state = .complete
        }
    }

    private func markLastUserMessageError(_ message: String) {
        if let idx = session.messages.lastIndex(where: { $0.role == .user }) {
            session.messages[idx].state = .error(message)
        }
    }

    private func processMessageQueue() {
        guard !messageQueue.isEmpty else { return }
        let nextMessage = messageQueue.removeFirst()
        sendMessage(nextMessage)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let dismissMoltNotchPanel = Notification.Name("dismissMoltNotchPanel")
}
