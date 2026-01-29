// ABOUTME: Spotlight-style popup for the chat assistant with query input and streamed response.
// ABOUTME: Supports compact (last response) and expanded (full conversation history) modes.

import SwiftUI
import MarkdownUI

struct ChatPopup: View {
    @ObservedObject var manager: MoltNotchManager
    @State private var inputText = ""
    @State private var isExpanded = false
    @State private var screenshotEnabled = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var showClearConfirm = false
    @State private var clearConfirmTimer: Timer?
    @State private var lastCtrlPressTime: Date?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !manager.session.messages.isEmpty {
                HStack {
                    Spacer()
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .glassButton()
                }
            }

            if isExpanded {
                expandedConversationView
                    .transition(
                        .opacity
                        .combined(with: .scale(scale: 0.95, anchor: .top))
                    )
            }

            if manager.connectionState != .connected {
                disconnectedBanner
            }

            if showClearConfirm {
                clearConfirmBanner
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            GlassControlContainer {
                inputField
            }

            if !isExpanded {
                compactResponseView
                    .transition(
                        .opacity
                        .combined(with: .scale(scale: 0.95, anchor: .bottom))
                    )
            }

            if isShowingIndicator {
                indicatorView
            }
        }
        .padding(20)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.bouncy(duration: 0.4), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: showClearConfirm)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                isInputFocused = true
            }
        }
        .onExitCommand {
            handleEscape()
        }
    }

    // MARK: - Input

    private var inputField: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if inputText.isEmpty {
                    ShimmerText("Ask anything...")
                }
                TextField("", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .focused($isInputFocused)
                    .onSubmit {
                        submitWithCurrentMode()
                    }
            }

            if screenshotEnabled {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.cyan)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: screenshotEnabled)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 48 && !event.modifierFlags.contains(.shift) {
                screenshotEnabled.toggle()
                return nil
            }
            if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
                submitWithScreenshot()
                return nil
            }
            return event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleCtrlTap(event)
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    private func handleCtrlTap(_ event: NSEvent) {
        let ctrlOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control
        let ctrlPressed = event.modifierFlags.contains(.control)

        guard ctrlPressed && ctrlOnly else { return }
        guard !manager.session.messages.isEmpty && !manager.isStreaming else { return }

        let now = Date()
        if showClearConfirm, let last = lastCtrlPressTime, now.timeIntervalSince(last) < 2.0 {
            clearVisibleChat()
            dismissClearConfirm()
        } else {
            showClearConfirm = true
            lastCtrlPressTime = now
            clearConfirmTimer?.invalidate()
            clearConfirmTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    dismissClearConfirm()
                }
            }
        }
    }

    private func dismissClearConfirm() {
        showClearConfirm = false
        lastCtrlPressTime = nil
        clearConfirmTimer?.invalidate()
        clearConfirmTimer = nil
    }

    // MARK: - Expanded Conversation

    private var expandedConversationView: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.session.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .onChange(of: manager.session.messages.count) { _, _ in
                    if let lastId = manager.session.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    assistantContent(message)
                } else {
                    HStack(spacing: 4) {
                        Text(message.content)
                            .foregroundColor(.white)
                        if message.hasScreenshot {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(message.role == .user
                        ? Color.blue.opacity(0.3)
                        : Color.white.opacity(0.1))
            )
            .frame(maxWidth: 400, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
    }

    // MARK: - Compact Response

    @ViewBuilder
    private var compactResponseView: some View {
        if let lastAssistant = lastAssistantMessage, !lastAssistant.content.isEmpty {
            Divider()
                .background(Color.white.opacity(0.3))

            ScrollView {
                assistantContent(lastAssistant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
        }
    }

    @ViewBuilder
    private func assistantContent(_ message: ChatMessage) -> some View {
        switch message.state {
        case .error(let msg):
            Text(msg)
                .foregroundColor(.red)
                .font(.subheadline)

        default:
            if !message.content.isEmpty {
                Markdown(message.content)
                    .markdownTextStyle {
                        ForegroundColor(.white)
                    }
            }
        }
    }

    // MARK: - Indicator

    private var indicatorView: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
                .colorScheme(.dark)
            Text(indicatorText)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var clearConfirmBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .foregroundColor(.white.opacity(0.6))
            Text("Press Ctrl again to clear chat")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
        )
        .frame(maxWidth: .infinity)
    }

    private var disconnectedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                if let errorDetail = manager.errorMessage {
                    Text(errorDetail)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("Not connected to gateway")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Text("Run `moltnotch doctor` to diagnose")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.2))
        )
    }

    // MARK: - Helpers

    private var lastAssistantMessage: ChatMessage? {
        manager.session.messages.last(where: { $0.role == .assistant })
    }

    private var isShowingIndicator: Bool {
        if let lastUser = manager.session.messages.last(where: { $0.role == .user }),
           lastUser.state == .sending {
            return true
        }
        if let lastAssistant = lastAssistantMessage,
           lastAssistant.state == .streaming, lastAssistant.content.isEmpty {
            return true
        }
        return false
    }

    private var indicatorText: String {
        if let lastUser = manager.session.messages.last(where: { $0.role == .user }),
           lastUser.state == .sending {
            return "Sending..."
        }
        return "Thinking..."
    }

    private func clearVisibleChat() {
        guard !manager.isStreaming else { return }
        manager.session.messages.removeAll()
        isExpanded = false
    }

    private func submitWithCurrentMode() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        NSLog("[ChatPopup] submitWithCurrentMode screenshotEnabled=\(screenshotEnabled) text=\(trimmed.prefix(30))")
        #endif
        manager.sendMessage(trimmed, includeScreenshot: screenshotEnabled)
        inputText = ""
        screenshotEnabled = false
    }

    private func submitWithScreenshot() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manager.sendMessage(trimmed, includeScreenshot: true)
        inputText = ""
        screenshotEnabled = false
    }

    private func handleEscape() {
        if manager.session.isStreaming {
            manager.abortStream()
        } else if !inputText.isEmpty {
            inputText = ""
        } else {
            manager.dismissPanel()
        }
    }
}
