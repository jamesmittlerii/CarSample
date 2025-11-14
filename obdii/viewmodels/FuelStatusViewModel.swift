//
//  FuelStatusViewModel.swift
//  obdii
//
//  Created by cisstudent on 11/14/25.
//

import Combine
import SwiftOBD2
import Foundation


@MainActor
final class FuelStatusViewModel: ObservableObject {
    @Published private(set) var status: [StatusCodeMetadata?] = []

    private var cancellable: AnyCancellable?

    init(connectionManager: OBDConnectionManager? = nil) {
        let manager = connectionManager ?? OBDConnectionManager.shared
        cancellable = manager.$fuelStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.status = newValue
            }
    }

    var bank1: StatusCodeMetadata? { status.indices.contains(0) ? status[0] : nil }
    var bank2: StatusCodeMetadata? { status.indices.contains(1) ? status[1] : nil }
    var hasAnyStatus: Bool { bank1 != nil || bank2 != nil }
}
