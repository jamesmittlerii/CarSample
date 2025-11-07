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
}
