/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
View Model for showing the a collection of enabled/selected Gauges. Used by CarPlay and SwiftUI
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import Foundation
import Combine
import SwiftOBD2

@MainActor
final class GaugesViewModel: ObservableObject {
    struct Tile: Identifiable, Equatable {
        let id: UUID
        let pid: OBDPID
        let measurement: MeasurementResult?
    }

    @Published private(set) var tiles: [Tile] = []

    private let connectionManager: OBDConnectionManager
    private let pidStore: PIDStore
    private var cancellables = Set<AnyCancellable>()

    // Cache the latest inputs so we can rebuild on units changes
    private var lastPids: [OBDPID] = []
    private var lastStats: [OBDCommand: OBDConnectionManager.PIDStats] = [:]

    // Designated initializer without default arguments (avoids nonisolated default evaluation)
    init(connectionManager: OBDConnectionManager, pidStore: PIDStore) {
        self.connectionManager = connectionManager
        self.pidStore = pidStore

        // Rebuild tiles whenever enabled PIDs or live stats change
        Publishers.CombineLatest(pidStore.$pids, connectionManager.$pidStats)
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pids, stats in
                guard let self else { return }
                self.lastPids = pids
                self.lastStats = stats
                self.rebuildTiles(pids: pids, stats: stats)
            }
            .store(in: &cancellables)

        // Also rebuild when units change so display strings update
        ConfigData.shared.$unitsPublished
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.rebuildTiles(pids: self.lastPids, stats: self.lastStats)
            }
            .store(in: &cancellables)
    }

    // Convenience initializers that safely access MainActor singletons
    convenience init(connectionManager: OBDConnectionManager) {
        self.init(connectionManager: connectionManager, pidStore: .shared)
    }

    convenience init() {
        self.init(connectionManager: .shared, pidStore: .shared)
    }

    private func rebuildTiles(pids: [OBDPID], stats: [OBDCommand: OBDConnectionManager.PIDStats]) {
        let enabled = pids.filter { $0.enabled && $0.kind == .gauge }
        tiles = enabled.map { pid in
            let measurement = stats[pid.pid]?.latest
            return Tile(id: pid.id, pid: pid, measurement: measurement)
        }
    }
}
