// ABOUTME: WebSocket client for the MoltBot gateway using URLSessionWebSocketTask.
// ABOUTME: Handles connection lifecycle, challenge-response auth, device identity, and chat event dispatch.

import Foundation
import Combine
import CryptoKit

// MARK: - Device Identity

struct DeviceIdentity {
    let deviceId: String
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKeyRawBase64Url: String

    init() {
        let key = Curve25519.Signing.PrivateKey()
        self.privateKey = key
        let rawPublicKey = key.publicKey.rawRepresentation
        self.deviceId = SHA256.hash(data: rawPublicKey)
            .compactMap { String(format: "%02x", $0) }
            .joined()
        self.publicKeyRawBase64Url = rawPublicKey
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func sign(payload: String) -> String {
        guard let data = payload.data(using: .utf8) else { return "" }
        guard let signature = try? privateKey.signature(for: data) else { return "" }
        return Data(signature)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - GatewayConnection

class GatewayConnection: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published private(set) var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pendingRequests: [String: (Result<ResponseFrame, Error>) -> Void] = [:]
    private var reconnectAttempts = 0
    private var shouldReconnect = true
    private let gatewayURL: URL
    private let gatewayConfig: MoltNotchConfig.GatewayConfig
    private var healthCheckTimer: Timer?
    private let deviceIdentity = DeviceIdentity()
    private var storedDeviceToken: String?
    private var connectNonce: String?
    private var connectSent = false
    private var connectTimer: Timer?
    private var isReconnecting = false

    var onChatEvent: ((ChatEvent) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    init(url: URL, config: MoltNotchConfig.GatewayConfig) {
        self.gatewayURL = url
        self.gatewayConfig = config
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Connection

    func connect() {
        guard !isConnected else { return }
        isReconnecting = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        connectNonce = nil
        connectSent = false
        connectTimer?.invalidate()
        connectTimer = nil
        webSocketTask = urlSession.webSocketTask(with: gatewayURL)
        webSocketTask?.resume()
        receiveMessage()
    }

    func disconnect() {
        shouldReconnect = false
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        connectTimer?.invalidate()
        connectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        updateConnected(false)
    }

    func send<P: Encodable>(method: String, params: P, completion: @escaping (Result<ResponseFrame, Error>) -> Void) {
        let requestId = UUID().uuidString
        let request = GatewayRequest(id: requestId, method: method, params: params)
        pendingRequests[requestId] = completion

        do {
            let data = try JSONEncoder().encode(request)
            guard let string = String(data: data, encoding: .utf8) else {
                pendingRequests.removeValue(forKey: requestId)
                completion(.failure(NSError(domain: "GatewayConnection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request"])))
                return
            }
            webSocketTask?.send(.string(string)) { [weak self] error in
                if let error = error {
                    self?.pendingRequests.removeValue(forKey: requestId)
                    completion(.failure(error))
                }
            }
        } catch {
            pendingRequests.removeValue(forKey: requestId)
            completion(.failure(error))
        }
    }

    // MARK: - Connect Handshake

    private func queueConnect() {
        connectNonce = nil
        connectSent = false
        DispatchQueue.main.async { [weak self] in
            self?.connectTimer?.invalidate()
            self?.connectTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
                self?.sendConnectFrame(nonce: nil)
            }
        }
    }

    private func sendConnectFrame(nonce: String?) {
        guard !connectSent else { return }
        connectSent = true
        connectTimer?.invalidate()
        connectTimer = nil

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let role = "operator"
        let scopes = ["operator.admin"]
        let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let authToken = storedDeviceToken ?? gatewayConfig.token

        // Build device signature payload (v2 format)
        let payloadParts = [
            "v2",
            deviceIdentity.deviceId,
            GatewayClientId.macosApp,
            "webchat",
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            authToken ?? "",
            nonce ?? ""
        ]
        let payloadString = payloadParts.joined(separator: "|")
        let signature = deviceIdentity.sign(payload: payloadString)

        let deviceInfo = ConnectParams.DeviceInfo(
            id: deviceIdentity.deviceId,
            publicKey: deviceIdentity.publicKeyRawBase64Url,
            signature: signature,
            signedAt: signedAtMs,
            nonce: nonce
        )

        var authInfo: ConnectParams.AuthInfo? = nil
        if let token = gatewayConfig.token {
            authInfo = ConnectParams.AuthInfo(password: token, token: authToken)
        } else if let token = authToken {
            authInfo = ConnectParams.AuthInfo(token: token)
        }

        let params = ConnectParams(
            client: ConnectParams.ClientInfo(
                id: GatewayClientId.macosApp,
                displayName: "MoltNotch",
                version: appVersion
            ),
            caps: [],
            role: role,
            scopes: scopes,
            auth: authInfo,
            device: deviceInfo
        )

        let healthInterval = TimeInterval(gatewayConfig.healthCheckInterval ?? 15)

        send(method: "connect", params: params) { [weak self] result in
            switch result {
            case .success(let response):
                if response.ok {
                    // Extract device token from hello-ok payload
                    if let payload = response.payload?.value as? [String: Any],
                       let auth = payload["auth"] as? [String: Any],
                       let deviceToken = auth["deviceToken"] as? String {
                         self?.storedDeviceToken = deviceToken
                    }
                    self?.reconnectAttempts = 0
                    self?.updateConnected(true)
                    self?.onConnectionChanged?(true)
                    self?.startHealthCheck(interval: healthInterval)
                } else {
                    let errorMsg = response.error?.message ?? "Connect failed"
                    self?.handleDisconnect(NSError(domain: "GatewayConnection", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                }
            case .failure(let error):
                self?.handleDisconnect(error)
            }
        }
    }

    // MARK: - Receive Loop

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                self?.handleDisconnect(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else {
            return
        }

        guard let frame = try? JSONDecoder().decode(GatewayFrame.self, from: data) else {
            return
        }

        switch frame.type {
        case "res":
            if let response = try? JSONDecoder().decode(ResponseFrame.self, from: data) {
                if let callback = pendingRequests.removeValue(forKey: response.id) {
                    callback(.success(response))
                }
            }
        case "event":
            if let eventFrame = try? JSONDecoder().decode(EventFrame.self, from: data) {
                if eventFrame.event == "connect.challenge", let nonce = eventFrame.challengeNonce {
                    connectNonce = nonce
                    sendConnectFrame(nonce: nonce)
                } else if eventFrame.event == "chat", let chatEvent = eventFrame.chatEvent {
                    DispatchQueue.main.async { [weak self] in
                        self?.onChatEvent?(chatEvent)
                    }
                }
            }
        default:
            break
        }
    }

    private func handleDisconnect(_ error: Error) {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        connectTimer?.invalidate()
        connectTimer = nil
        updateConnected(false)
        onConnectionChanged?(false)
        if !isReconnecting {
            scheduleReconnect()
        }
    }

    private func updateConnected(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = connected
        }
    }

    private func scheduleReconnect() {
        let maxAttempts = gatewayConfig.reconnectMaxAttempts ?? 10
        let baseDelay = gatewayConfig.reconnectBaseDelay ?? 1.0
        let maxDelay = gatewayConfig.reconnectMaxDelay ?? 30.0

        guard shouldReconnect, !isReconnecting, reconnectAttempts < maxAttempts else { return }
        isReconnecting = true
        reconnectAttempts += 1
        let delay = min(
            baseDelay * pow(2.0, Double(reconnectAttempts - 1)),
            maxDelay
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queueConnect()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnect(NSError(domain: "GatewayConnection", code: Int(closeCode.rawValue), userInfo: nil))
    }

    // MARK: - Health Check

    func startHealthCheck(interval: TimeInterval) {
        healthCheckTimer?.invalidate()
        DispatchQueue.main.async { [weak self] in
            self?.healthCheckTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: true
            ) { [weak self] _ in
                self?.performHealthCheck()
            }
        }
    }

    private func performHealthCheck() {
        guard !isReconnecting else { return }
        sendPing { [weak self] success in
            if !success {
                DispatchQueue.main.async { [weak self] in
                    self?.updateConnected(false)
                    self?.onConnectionChanged?(false)
                    self?.scheduleReconnect()
                }
            }
        }
    }

    // MARK: - Ping

    func sendPing(completion: @escaping (Bool) -> Void) {
        webSocketTask?.sendPing { [weak self] error in
            _ = self
            completion(error == nil)
        }
    }
}
