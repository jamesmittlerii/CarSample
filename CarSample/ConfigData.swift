//
//  ConfigData.swift
//  CarSample
//
//  Created by cisstudent on 11/3/25.
//

import Foundation
import Combine

class ConfigData: ObservableObject {
    static let shared = ConfigData()
    @Published var wifiHost: String = "192.168.0.10"
    @Published var wifiPort: UInt16 = 35000
    
}
