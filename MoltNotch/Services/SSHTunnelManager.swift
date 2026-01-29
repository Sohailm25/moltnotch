// ABOUTME: SSH tunnel process manager that launches and monitors `ssh -N -L` child processes.
// ABOUTME: Provides automatic reconnection with exponential backoff and TCP health checks.

import Foundation
import Combine

class SSHTunnelManager: ObservableObject {
    @Published private(set) var tunnelState: TunnelState = .disconnected

    enum TunnelState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private var process: Process?
    private var healthCheckTimer: Timer?
    private var reconnectAttempts = 0
    private let tunnelConfig: MoltNotchConfig.TunnelConfig
    private let healthCheckInterval: TimeInterval
    private let reconnectMaxAttempts: Int
    private let reconnectBaseDelay: TimeInterval
    private let reconnectMaxDelay: TimeInterval
    private var shouldReconnect = true

    init(config: MoltNotchConfig.TunnelConfig, gatewayConfig: MoltNotchConfig.GatewayConfig) {
        self.tunnelConfig = config
        self.healthCheckInterval = TimeInterval(gatewayConfig.healthCheckInterval ?? 15)
        self.reconnectMaxAttempts = gatewayConfig.reconnectMaxAttempts ?? 10
        self.reconnectBaseDelay = gatewayConfig.reconnectBaseDelay ?? 1.0
        self.reconnectMaxDelay = gatewayConfig.reconnectMaxDelay ?? 30.0
    }

    var localPort: Int {
        tunnelConfig.localPort ?? 18789
    }

    func startTunnel() {
        DispatchQueue.main.async { [weak self] in
            self?.tunnelState = .connecting
        }

        checkTCPConnection(host: "127.0.0.1", port: localPort) { [weak self] reachable in
            guard let self = self else { return }
            if reachable {
                DispatchQueue.main.async { [weak self] in
                    self?.reconnectAttempts = 0
                    self?.tunnelState = .connected
                }
                self.startHealthCheck()
                return
            }
            self.launchSSHProcess()
        }
    }

    private func launchSSHProcess() {
        let sshProcess = Process()
        sshProcess.launchPath = "/usr/bin/ssh"
        sshProcess.arguments = [
            "-N",
            "-L", "\(localPort):127.0.0.1:\(tunnelConfig.remotePort ?? 18789)",
            "\(tunnelConfig.user)@\(tunnelConfig.host)",
            "-p", "\(tunnelConfig.port ?? 22)",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes"
        ]

        sshProcess.standardOutput = FileHandle.nullDevice
        sshProcess.standardError = FileHandle.nullDevice

        sshProcess.terminationHandler = { [weak self] terminatedProcess in
            guard let self = self else { return }
            let exitCode = terminatedProcess.terminationStatus
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.shouldReconnect {
                    self.tunnelState = .disconnected
                    self.scheduleReconnect()
                } else {
                    self.tunnelState = exitCode == 0 ? .disconnected : .failed("SSH exited with code \(exitCode)")
                }
            }
        }

        do {
            try sshProcess.run()
            process = sshProcess
            startHealthCheck()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.tunnelState = .failed("Failed to launch SSH: \(error.localizedDescription)")
            }
        }
    }

    func stopTunnel() {
        shouldReconnect = false
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        process?.terminate()
        process = nil
        DispatchQueue.main.async { [weak self] in
            self?.tunnelState = .disconnected
        }
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.healthCheckTimer = Timer.scheduledTimer(
                withTimeInterval: self.healthCheckInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performHealthCheck()
            }
        }
    }

    private func performHealthCheck() {
        checkTCPConnection(host: "127.0.0.1", port: localPort) { [weak self] reachable in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if reachable {
                    if self.tunnelState == .connecting {
                        self.reconnectAttempts = 0
                        self.tunnelState = .connected
                    }
                } else {
                    if self.tunnelState == .connected {
                        self.tunnelState = .disconnected
                        self.healthCheckTimer?.invalidate()
                        self.healthCheckTimer = nil
                        self.process?.terminate()
                        self.process = nil
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        guard reconnectAttempts < reconnectMaxAttempts else {
            DispatchQueue.main.async { [weak self] in
                self?.tunnelState = .failed("Max reconnect attempts reached")
            }
            return
        }
        reconnectAttempts += 1
        let delay = min(
            reconnectBaseDelay * pow(2.0, Double(reconnectAttempts - 1)),
            reconnectMaxDelay
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startTunnel()
        }
    }

    // MARK: - TCP Check

    private func checkTCPConnection(host: String, port: Int, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://\(host):\(port)")!
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            _ = self
            let portOpen = error == nil || (response as? HTTPURLResponse) != nil
            completion(portOpen)
        }.resume()
    }

    deinit {
        stopTunnel()
    }
}
