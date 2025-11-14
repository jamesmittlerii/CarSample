// GaugesViewModel.swift
import Foundation
import Combine
import SwiftOBD2

@MainActor
final class GaugesViewModel: ObservableObject {
    struct Tile: Identifiable {
        let id: UUID
        let pid: OBDPID
        let measurement: MeasurementResult?
    }

    @Published private(set) var tiles: [Tile] = []

    private let connectionManager: OBDConnectionManager
    private let pidStore: PIDStore
    private var cancellables = Set<AnyCancellable>()

    // Designated initializer without default arguments (avoids nonisolated default evaluation)
    init(connectionManager: OBDConnectionManager, pidStore: PIDStore) {
        self.connectionManager = connectionManager
        self.pidStore = pidStore

        // Rebuild tiles whenever enabled PIDs or live stats change
        Publishers.CombineLatest(pidStore.$pids, connectionManager.$pidStats)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pids, stats in
                self?.rebuildTiles(pids: pids, stats: stats)
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
