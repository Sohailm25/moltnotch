// ABOUTME: Orchestrates gateway connection with optional SSH tunnel based on config.
// ABOUTME: Decides direct WebSocket vs tunnel+WebSocket and tracks composite connection state.

import Foundation
import Combine

class ConnectionManager: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var reconnectAttempt: Int = 0

    private var tunnelManager: SSHTunnelManager?
    private(set) var gateway: GatewayConnection?
    private let config: MoltNotchConfig
    private var cancellables = Set<AnyCancellable>()

    var onChatEvent: ((ChatEvent) -> Void)?

    init(config: MoltNotchConfig) {
        self.config = config
    }

    func connect() {
        if let tunnelConfig = config.tunnel {
            startWithTunnel(tunnelConfig)
        } else {
            connectGatewayDirect()
        }
    }

    func disconnect() {
        tunnelManager?.stopTunnel()
        tunnelManager = nil
        gateway?.disconnect()
        gateway = nil
        cancellables.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .disconnected
        }
    }

    // MARK: - Tunnel Mode

    private func startWithTunnel(_ tunnelConfig: MoltNotchConfig.TunnelConfig) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .tunnelConnecting
        }

        let tunnel = SSHTunnelManager(config: tunnelConfig, gatewayConfig: config.gateway)
        self.tunnelManager = tunnel

        tunnel.$tunnelState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleTunnelStateChange(state)
            }
            .store(in: &cancellables)

        tunnel.startTunnel()
    }

    private func handleTunnelStateChange(_ state: SSHTunnelManager.TunnelState) {
        switch state {
        case .disconnected:
            break
        case .connecting:
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .tunnelConnecting
            }
        case .connected:
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .tunnelConnected
            }
            if gateway == nil || !gateway!.isConnected {
                let localPort = tunnelManager?.localPort ?? 18789
                let url = URL(string: "ws://127.0.0.1:\(localPort)")!
                connectGateway(url: url)
            }
        case .failed(let message):
            DispatchQueue.main.async { [weak self] in
                self?.reconnectAttempt += 1
                self?.connectionState = .error(message)
            }
        }
    }

    // MARK: - Direct Mode

    private func connectGatewayDirect() {
        guard let url = URL(string: config.gateway.url) else {
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .error("Invalid gateway URL")
            }
            return
        }
        connectGateway(url: url)
    }

    // MARK: - Gateway

    private func connectGateway(url: URL) {
        gateway?.disconnect()

        let gw = GatewayConnection(url: url, config: config.gateway)
        self.gateway = gw

        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .connecting
        }

        gw.onChatEvent = { [weak self] event in
            self?.onChatEvent?(event)
        }

        gw.onConnectionChanged = { [weak self] connected in
            DispatchQueue.main.async { [weak self] in
                if connected {
                    self?.connectionState = .connected
                    self?.reconnectAttempt = 0
                } else {
                    self?.connectionState = .error("Gateway disconnected")
                }
            }
        }

        gw.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                if connected {
                    self?.connectionState = .connected
                }
            }
            .store(in: &cancellables)

        gw.connect()
    }
}
