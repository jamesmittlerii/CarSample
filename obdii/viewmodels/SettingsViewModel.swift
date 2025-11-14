import Foundation
import Combine
import SwiftUI
import SwiftOBD2

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties for the View
    
    @Published var wifiHost: String
    @Published var wifiPort: Int
    @Published var autoConnectToOBD: Bool
    @Published var connectionType: ConnectionType
    @Published private(set) var connectionState: OBDConnectionManager.ConnectionState
    @Published var units: MeasurementUnit   // NEW: expose units to the View

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

    // MARK: - Initializers
    
    // Designated initializer without default arguments (avoids nonisolated default evaluation)
    init(configData: ConfigData, connectionManager: OBDConnectionManager) {
        self.configData = configData
        self.connectionManager = connectionManager

        // Initialize published properties from the models
        self.wifiHost = configData.wifiHost
        self.wifiPort = configData.wifiPort
        self.autoConnectToOBD = configData.autoConnectToOBD
        self.connectionType = configData.connectionType
        self.connectionState = connectionManager.connectionState
        self.units = configData.unitsPublished   // NEW

        // Set up subscriptions to propagate changes from models to ViewModel
        // and from ViewModel back to models.
        setupSubscriptions()
    }

    // Convenience initializer that safely accesses main-actor isolated singletons
    convenience init() {
        self.init(configData: .shared, connectionManager: .shared)
    }

    private func setupSubscriptions() {
        // 1. Listen for connection state changes from the manager
        connectionManager.$connectionState
            .receive(on: RunLoop.main)
            .assign(to: &$connectionState)

        // 2. When ViewModel properties change, update the underlying models.
        // This creates a two-way flow: View -> ViewModel -> Model.

        // Wi‑Fi host updates only matter when connection type is .wifi
        $wifiHost
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newHost in
                guard let self else { return }
                self.configData.wifiHost = newHost
                if self.connectionType == .wifi {
                    self.connectionManager.updateConnectionDetails()
                }
            }
            .store(in: &cancellables)

        // Wi‑Fi port updates only matter when connection type is .wifi
        $wifiPort
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newPort in
                guard let self else { return }
                self.configData.wifiPort = newPort
                if self.connectionType == .wifi {
                    self.connectionManager.updateConnectionDetails()
                }
            }
            .store(in: &cancellables)

        $autoConnectToOBD
            .dropFirst()
            .sink { [weak self] newSetting in
                self?.configData.autoConnectToOBD = newSetting
            }
            .store(in: &cancellables)

        // When connection type changes, persist and rebuild the OBDService
        $connectionType
            .dropFirst()
            .sink { [weak self] newType in
                guard let self else { return }
                self.configData.connectionType = newType
                self.connectionManager.updateConnectionDetails()
            }
            .store(in: &cancellables)

        // NEW: Units two-way binding between ConfigData and ViewModel
        configData.$unitsPublished
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$units)

        $units
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newUnits in
                self?.configData.setUnits(newUnits)
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
