// ABOUTME: Tests for MoltNotchManager orchestrator covering message lifecycle and connection state.
// ABOUTME: Validates send flow, streaming events, message queueing, and error handling.

import XCTest
@testable import MoltNotch

final class MoltNotchManagerTests: XCTestCase {

    private func makeManager() -> MoltNotchManager {
        return MoltNotchManager(connectionManager: nil)
    }

    private func makeChatEvent(
        runId: String = "run-1",
        sessionKey: String,
        seq: Int = 1,
        state: String,
        text: String? = nil,
        errorMessage: String? = nil,
        stopReason: String? = nil
    ) -> ChatEvent {
        let message: ChatEventMessage?
        if let text = text {
            message = ChatEventMessage(
                role: "assistant",
                content: [ChatContentBlock(type: "text", text: text)]
            )
        } else {
            message = nil
        }
        return ChatEvent(
            runId: runId,
            sessionKey: sessionKey,
            seq: seq,
            state: state,
            message: message,
            errorMessage: errorMessage,
            stopReason: stopReason
        )
    }

    // MARK: - Send Message Lifecycle

    func testSendMessageCreatesUserMessage() {
        let manager = makeManager()

        manager.sendMessage("Hello")

        let expectation = XCTestExpectation(description: "User message appended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(manager.session.messages.count, 1)
            XCTAssertEqual(manager.session.messages[0].content, "Hello")
            XCTAssertTrue(manager.session.messages[0].role == .user)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testSendMessageSetsErrorWhenNoGateway() {
        let manager = makeManager()

        manager.sendMessage("Hello")

        let expectation = XCTestExpectation(description: "User message set to error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(manager.session.messages.count, 1)
            XCTAssertEqual(manager.session.messages[0].state, .error("No gateway connection"))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Chat Event Handling

    func testChatEventDeltaReplacesContent() {
        let manager = makeManager()

        let assistantMsg = ChatMessage(role: .assistant, content: "Hello", state: .streaming)
        manager.session.messages.append(assistantMsg)
        manager.session.activeRunId = "run-1"

        let event = makeChatEvent(
            sessionKey: manager.session.sessionKey,
            state: "delta",
            text: "Hello world"
        )
        manager.handleChatEvent(event)

        let expectation = XCTestExpectation(description: "Delta replaced")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(manager.session.messages[0].content, "Hello world")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testChatEventFinalCompletesMessage() {
        let manager = makeManager()

        let assistantMsg = ChatMessage(role: .assistant, content: "Done", state: .streaming)
        manager.session.messages.append(assistantMsg)
        manager.session.activeRunId = "run-1"

        let event = makeChatEvent(
            sessionKey: manager.session.sessionKey,
            seq: 2,
            state: "final",
            stopReason: "end_turn"
        )
        manager.handleChatEvent(event)

        let expectation = XCTestExpectation(description: "Final completes message")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(manager.session.messages[0].state, .complete)
            XCTAssertNil(manager.session.activeRunId)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testChatEventErrorSetsErrorState() {
        let manager = makeManager()

        let assistantMsg = ChatMessage(role: .assistant, content: "", state: .streaming)
        manager.session.messages.append(assistantMsg)
        manager.session.activeRunId = "run-1"

        let event = makeChatEvent(
            sessionKey: manager.session.sessionKey,
            state: "error",
            errorMessage: "Rate limited"
        )
        manager.handleChatEvent(event)

        let expectation = XCTestExpectation(description: "Error state set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(manager.session.messages[0].state, .error("Rate limited"))
            XCTAssertNil(manager.session.activeRunId)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Connection State

    func testConnectionStateDefaultsToDisconnected() {
        let manager = makeManager()
        XCTAssertEqual(manager.connectionState, .disconnected)
    }

    // MARK: - Session Persistence

    func testSessionKeyIsPersistent() {
        let manager = makeManager()
        let key1 = manager.session.sessionKey
        let key2 = manager.session.sessionKey
        XCTAssertEqual(key1, key2)
        XCTAssertFalse(key1.isEmpty)
    }

    func testIsStreamingDuringActiveRun() {
        let manager = makeManager()
        XCTAssertFalse(manager.isStreaming)

        manager.session.activeRunId = "run-42"
        XCTAssertTrue(manager.isStreaming)
    }

    // MARK: - Message Queueing

    func testMessageQueueWhenAlreadyStreaming() {
        let manager = makeManager()

        manager.session.activeRunId = "run-1"
        let assistantMsg = ChatMessage(role: .assistant, content: "", state: .streaming)
        manager.session.messages.append(assistantMsg)

        manager.sendMessage("queued message")

        let expectation = XCTestExpectation(description: "Message queued, not sent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(manager.session.messages.count, 1,
                           "No new message should be added when streaming")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testQueuedMessageSentAfterComplete() {
        let manager = makeManager()

        manager.session.activeRunId = "run-1"
        let assistantMsg = ChatMessage(role: .assistant, content: "response", state: .streaming)
        manager.session.messages.append(assistantMsg)

        manager.sendMessage("queued message")

        XCTAssertEqual(manager.session.messages.count, 1)

        let finalEvent = makeChatEvent(
            sessionKey: manager.session.sessionKey,
            seq: 2,
            state: "final",
            stopReason: "end_turn"
        )
        manager.handleChatEvent(finalEvent)

        let expectation = XCTestExpectation(description: "Queued message sent after final")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(manager.session.messages.count >= 2,
                          "Queued message should have been sent after stream completed")
            let lastUserMsg = manager.session.messages.last(where: { $0.role == .user })
            XCTAssertEqual(lastUserMsg?.content, "queued message")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
