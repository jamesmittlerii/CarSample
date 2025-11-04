import Foundation
import Combine
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties for the View
    
    @Published var wifiHost: String
    @Published var wifiPort: Int
    @Published var autoConnectToOBD: Bool
    @Published private(set) var connectionState: OBDConnectionManager.ConnectionState

    // MARK: - Private Model References
    
    private let configData: ConfigData
    private let connectionManager: OBDConnectionManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Helpers
    
    /// Formatter to ensure the port is entered as a number
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        return formatter
    }()
    
    var isConnectButtonDisabled: Bool {
        connectionState == .connecting
    }

    // MARK: - Initializer
    
    init(configData: ConfigData = .shared, connectionManager: OBDConnectionManager = .shared) {
        self.configData = configData
        self.connectionManager = connectionManager

        // Initialize published properties from the models
        self.wifiHost = configData.wifiHost
        self.wifiPort = configData.wifiPort
        self.autoConnectToOBD = configData.autoConnectToOBD
        self.connectionState = connectionManager.connectionState

        // Set up subscriptions to propagate changes from models to ViewModel
        // and from ViewModel back to models.
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        // 1. Listen for connection state changes from the manager
        connectionManager.$connectionState
            .receive(on: RunLoop.main)
            .assign(to: &$connectionState)

        // 2. When ViewModel properties change, update the underlying models.
        // This creates a two-way flow: View -> ViewModel -> Model.
        $wifiHost
            .dropFirst() // Ignore the initial value
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main) // Avoid rapid updates
            .sink { [weak self] newHost in
                self?.configData.wifiHost = newHost
                self?.connectionManager.updateConnectionDetails()
            }
            .store(in: &cancellables)

        $wifiPort
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newPort in
                self?.configData.wifiPort = newPort
                self?.connectionManager.updateConnectionDetails()
            }
            .store(in: &cancellables)

        $autoConnectToOBD
            .dropFirst()
            .sink { [weak self] newSetting in
                self?.configData.autoConnectToOBD = newSetting
            }
            .store(in: &cancellables)
    }
    
    // MARK: - User Actions
    
    /// Handles the primary connect/disconnect button tap.
    func handleConnectionButtonTap() {
        switch connectionManager.connectionState {
        case .connected:
            connectionManager.disconnect()
        case .disconnected, .failed:
            // Connection details are already up-to-date via subscriptions
            Task {
                await connectionManager.connect()
            }
        case .connecting:
            // Button is disabled, so this case shouldn't be reached
            break
        }
    }
}
