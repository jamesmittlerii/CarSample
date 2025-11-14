import SwiftUI
import SwiftOBD2
import Combine

@MainActor
final class GaugeDetailViewModel: ObservableObject {
    let pid: OBDPID
    private let connectionManager: OBDConnectionManager

    // Expose the live stats for this PID
    @Published private(set) var stats: OBDConnectionManager.PIDStats?

    private var cancellables = Set<AnyCancellable>()

    init(pid: OBDPID, connectionManager: OBDConnectionManager) {
        self.pid = pid
        self.connectionManager = connectionManager

        // Seed with current value if available
        self.stats = connectionManager.stats(for: pid.pid)

        // Subscribe to pidStats and extract the one for our pid
        connectionManager.$pidStats
            .map { dict in
                dict[pid.pid]
            }
            .removeDuplicates(by: { lhs, rhs in
                // Shallow equality: compare latest value and sampleCount to reduce UI updates
                switch (lhs, rhs) {
                case (nil, nil):
                    return true
                case let (l?, r?):
                    return l.sampleCount == r.sampleCount && l.latest.value == r.latest.value && l.min == r.min && l.max == r.max
                default:
                    return false
                }
            })
            .receive(on: DispatchQueue.main)
            .assign(to: &$stats)

        // Also listen to units changes so the view can re-render formatting even if stats didn’t change
        ConfigData.shared.$unitsPublished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Trigger a change by reassigning the current stats
                guard let self else { return }
                self.stats = self.connectionManager.stats(for: self.pid.pid)
            }
            .store(in: &cancellables)
    }
}
