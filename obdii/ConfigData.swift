import SwiftUI
import SwiftOBD2
import Combine

class ConfigData: ObservableObject {
    static let shared = ConfigData()

    @AppStorage("units") var units: MeasurementUnit =  (Locale.current.measurementSystem == .metric) ? .metric : .imperial
    @AppStorage("wifiHost") var wifiHost: String = "192.168.0.10"
    @AppStorage("wifiPort") var wifiPort: Int = 35000
    @AppStorage("autoConnectToOBD") var autoConnectToOBD: Bool = true

    @AppStorage("connectionType") private var storedConnectionType: String = ConnectionType.bluetooth.rawValue

    @Published var publishedConnectionType: String

    // Mirror publisher for units so other components can subscribe cleanly
    @Published var unitsPublished: MeasurementUnit

    private var cancellables = Set<AnyCancellable>()

    private init() {
        //
        // ✅ DO NOT ACCESS @AppStorage here for connection type beyond reading its raw value.
        //
        let raw = UserDefaults.standard.string(forKey: "connectionType")
            ?? ConnectionType.bluetooth.rawValue

        // Initialize published properties
        self.publishedConnectionType = raw
        self.unitsPublished = UserDefaults.standard.string(forKey: "units")
            .flatMap { MeasurementUnit(rawValue: $0) } ?? .metric

        // Sync initial values outward
        ConfigurationService.shared.connectionType =
            ConnectionType(rawValue: raw) ?? .bluetooth

        // Keep publishedConnectionType -> @AppStorage and service in sync
        $publishedConnectionType
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                self.storedConnectionType = newValue
                ConfigurationService.shared.connectionType =
                    ConnectionType(rawValue: newValue) ?? .bluetooth
            }
            .store(in: &cancellables)

        // Keep unitsPublished <-> @AppStorage("units") in sync both ways

        // When unitsPublished changes, write to @AppStorage
        $unitsPublished
            .dropFirst()
            .sink { [weak self] newUnits in
                self?.units = newUnits
            }
            .store(in: &cancellables)

        // When @AppStorage units changes externally, mirror to unitsPublished
        // Note: @AppStorage is not a publisher; observe via objectWillChange from this object
        // or add a small timer/notification. Simpler: mirror on accessors:
        // Provide a setter to update unitsPublished when units is set externally.
        // Since other code writes ConfigData.shared.units directly, add a didSet-like bridge below.
    }

    // Convenience enum accessor
    var connectionType: ConnectionType {
        get { ConnectionType(rawValue: publishedConnectionType) ?? .bluetooth }
        set { publishedConnectionType = newValue.rawValue }
    }
}

extension ConfigData {
    // Bridge units property so external writes update unitsPublished too
    // Wrap with computed property for external access if needed elsewhere.
    // Existing code accesses ConfigData.shared.units directly; to keep that working,
    // you can add these helpers or ensure all writes also update unitsPublished.
    // For minimal change, provide explicit setters:

    func setUnits(_ newUnits: MeasurementUnit) {
        // Update both storage and published mirror
        self.units = newUnits
        self.unitsPublished = newUnits
    }
}
