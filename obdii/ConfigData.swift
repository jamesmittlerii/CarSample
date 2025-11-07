//
//  ConfigData.swift
//  CarSample
//
//  Created by cisstudent on 11/3/25.
//

import SwiftUI
import SwiftOBD2

class ConfigData: ObservableObject {
    static let shared = ConfigData()
    
    @AppStorage("units") var units: MeasurementUnit = MeasurementUnit.metric
    
    @AppStorage("wifiHost") var wifiHost: String = "192.168.0.10"
    @AppStorage("wifiPort") var wifiPort: Int = 35000
    @AppStorage("autoConnectToOBD") var autoConnectToOBD: Bool = true

    // Persist the connection type selection; keep it aligned with ConfigurationService
    @AppStorage("connectionType") private var storedConnectionType: String = ConfigurationService.shared.connectionType.rawValue

    var connectionType: ConnectionType {
        get { ConnectionType(rawValue: storedConnectionType) ?? .bluetooth }
        set {
            storedConnectionType = newValue.rawValue
            // Also update the library-side configuration for consistency
            ConfigurationService.shared.connectionType = newValue
        }
    }
}

