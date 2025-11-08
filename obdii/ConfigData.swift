import SwiftUI
import SwiftOBD2
import Combine

class ConfigData: ObservableObject {
    static let shared = ConfigData()

    @AppStorage("units") var units: MeasurementUnit = .metric
    @AppStorage("wifiHost") var wifiHost: String = "192.168.0.10"
    @AppStorage("wifiPort") var wifiPort: Int = 35000
    @AppStorage("autoConnectToOBD") var autoConnectToOBD: Bool = true

    @AppStorage("connectionType") private var storedConnectionType: String = ConnectionType.bluetooth.rawValue

    @Published var publishedConnectionType: String

    private var cancellables = Set<AnyCancellable>()

    private init() {
        //
        // ✅ DO NOT ACCESS @AppStorage here.
        // Instead read directly from UserDefaults.
        //
        let raw = UserDefaults.standard.string(forKey: "connectionType")
            ?? ConnectionType.bluetooth.rawValue

        // ✅ Initialize the published value first
        self.publishedConnectionType = raw

        //super.init() // (not required but conceptually here)

        // ✅ Now we can safely sync the initial value outward
        ConfigurationService.shared.connectionType =
            ConnectionType(rawValue: raw) ?? .bluetooth

        //
        // ✅ When the *published* value changes, write to @AppStorage
        // (safe because all stored properties now exist)
        //
        $publishedConnectionType
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                self.storedConnectionType = newValue
                ConfigurationService.shared.connectionType =
                    ConnectionType(rawValue: newValue) ?? .bluetooth
            }
            .store(in: &cancellables)
    }

    // Convenience enum accessor
    var connectionType: ConnectionType {
        get { ConnectionType(rawValue: publishedConnectionType) ?? .bluetooth }
        set { publishedConnectionType = newValue.rawValue }
    }
}
