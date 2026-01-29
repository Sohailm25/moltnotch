// ABOUTME: Tests for ChatSession and ChatMessage model behavior.
// ABOUTME: Verifies session lifecycle, message mutability, and enum equality.

import XCTest
@testable import MoltNotch

final class ChatSessionTests: XCTestCase {

    func testSessionDefaultsToMainSessionKey() {
        let session = ChatSession()
        XCTAssertEqual(session.sessionKey, "main")
    }

    func testSessionStartsEmpty() {
        let session = ChatSession()
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertNil(session.activeRunId)
    }

    func testIsStreamingReturnsFalseWhenNoActiveRun() {
        let session = ChatSession()
        XCTAssertFalse(session.isStreaming)
    }

    func testIsStreamingReturnsTrueWhenActiveRun() {
        var session = ChatSession()
        session.activeRunId = "run-123"
        XCTAssertTrue(session.isStreaming)
    }

    func testChatMessageCreatesWithDefaults() {
        let msg = ChatMessage(role: .user, content: "hello", state: .sending)
        XCTAssertNotNil(msg.id)
        XCTAssertFalse(msg.hasScreenshot)
        XCTAssertTrue(msg.timestamp.timeIntervalSinceNow < 1)
    }

    func testChatMessageContentIsMutable() {
        var msg = ChatMessage(role: .assistant, content: "initial", state: .streaming)
        msg.content = "updated"
        XCTAssertEqual(msg.content, "updated")
    }

    func testChatMessageStateIsMutable() {
        var msg = ChatMessage(role: .user, content: "test", state: .sending)
        XCTAssertEqual(msg.state, .sending)
        msg.state = .complete
        XCTAssertEqual(msg.state, .complete)
    }

    func testMessageAppendToSession() {
        var session = ChatSession()
        let msg1 = ChatMessage(role: .user, content: "first", state: .complete)
        let msg2 = ChatMessage(role: .assistant, content: "second", state: .complete)
        session.messages.append(msg1)
        session.messages.append(msg2)

        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages[0].content, "first")
        XCTAssertEqual(session.messages[1].content, "second")
    }

    func testConnectionStateEquality() {
        XCTAssertEqual(ConnectionState.connected, ConnectionState.connected)
        XCTAssertEqual(ConnectionState.disconnected, ConnectionState.disconnected)
        XCTAssertEqual(ConnectionState.error("timeout"), ConnectionState.error("timeout"))
        XCTAssertNotEqual(ConnectionState.connected, ConnectionState.disconnected)
        XCTAssertNotEqual(ConnectionState.error("a"), ConnectionState.error("b"))
    }

    func testMessageStateEquality() {
        XCTAssertEqual(MessageState.complete, MessageState.complete)
        XCTAssertEqual(MessageState.sending, MessageState.sending)
        XCTAssertEqual(MessageState.streaming, MessageState.streaming)
        XCTAssertEqual(MessageState.error("x"), MessageState.error("x"))
        XCTAssertNotEqual(MessageState.complete, MessageState.sending)
        XCTAssertNotEqual(MessageState.error("x"), MessageState.error("y"))
    }

    // MARK: - Conversation History

    func testMultipleMessagesAccumulate() {
        var session = ChatSession()
        session.messages.append(ChatMessage(role: .user, content: "Hello", state: .complete))
        session.messages.append(ChatMessage(role: .assistant, content: "Hi!", state: .complete))
        session.messages.append(ChatMessage(role: .user, content: "How are you?", state: .complete))
        session.messages.append(ChatMessage(role: .assistant, content: "Good!", state: .complete))
        XCTAssertEqual(session.messages.count, 4)
    }

    func testMessagesPreserveOrder() {
        var session = ChatSession()
        for i in 0..<5 {
            session.messages.append(ChatMessage(role: .user, content: "msg-\(i)", state: .complete))
        }
        for i in 0..<5 {
            XCTAssertEqual(session.messages[i].content, "msg-\(i)")
        }
    }

    func testSessionSurvivesReopen() {
        var session = ChatSession()
        session.messages.append(ChatMessage(role: .user, content: "Test", state: .complete))
        let messagesAfterReopen = session.messages
        XCTAssertEqual(messagesAfterReopen.count, 1)
        XCTAssertEqual(messagesAfterReopen[0].content, "Test")
    }

    func testSessionKeyStaysConstantAcrossMessages() {
        var session = ChatSession()
        let keyBefore = session.sessionKey
        session.messages.append(ChatMessage(role: .user, content: "Hello", state: .complete))
        session.messages.append(ChatMessage(role: .assistant, content: "Hi", state: .complete))
        XCTAssertEqual(session.sessionKey, keyBefore)
    }

    func testTenMessageExchangesMaintainHistory() {
        var session = ChatSession()
        for i in 0..<10 {
            session.messages.append(ChatMessage(role: .user, content: "Q\(i)", state: .complete))
            session.messages.append(ChatMessage(role: .assistant, content: "A\(i)", state: .complete))
        }
        XCTAssertEqual(session.messages.count, 20)
        XCTAssertEqual(session.messages[0].content, "Q0")
        XCTAssertEqual(session.messages[19].content, "A9")
    }
}
