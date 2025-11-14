//
//  MILStatusViewModel.swift
//  obdii
//
//  Created by cisstudent on 11/14/25.
//

import Foundation
import SwiftOBD2
import Combine


@MainActor
final class MILStatusViewModel: ObservableObject {
    @Published private(set) var status: Status?
    private var cancellable: AnyCancellable?
    private var lastEmitted: Status?

    init(connectionManager: OBDConnectionManager? = nil) {
        let manager = connectionManager ?? OBDConnectionManager.shared
        cancellable = manager.$MILStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                // Deduplicate identical snapshots
                if self.lastEmitted != newValue {
                    self.lastEmitted = newValue
                    self.status = newValue
                }
            }
    }

    var headerText: String {
        guard let status else { return "No MIL Status" }
        let dtcLabel = "\(status.dtcCount) DTC" + (status.dtcCount == 1 ? "" : "s")
        let milLabel = status.milOn ? "On" : "Off"
        return "MIL: \(milLabel) (\(dtcLabel))"
    }

    var hasStatus: Bool { status != nil }

    var sortedSupportedMonitors: [ReadinessMonitor] {
        guard let status else { return [] }
        let supported = status.monitors.filter { $0.supported }
        return supported.sorted { lhs, rhs in
            func priority(for ready: Bool?) -> Int {
                switch ready {
                case .some(false): return 0   // Not Ready first
                case .some(true):  return 1   // Ready next
                case .none:        return 2   // Unknown last
                }
            }
            let lp = priority(for: lhs.ready)
            let rp = priority(for: rhs.ready)
            if lp != rp { return lp < rp }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
