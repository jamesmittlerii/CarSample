import Foundation
import Combine

@MainActor
final class PIDStore: ObservableObject {
    static let shared = PIDStore()

    @Published var pids: [OBDPID]

    // Persist only the enabled flags keyed by PID UUID
    private let enabledKey = "PIDStore.enabledByID"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Start from the library defaults
        var initial = OBDPIDLibrary.standard

        // Restore saved enabled flags
        if let data = UserDefaults.standard.data(forKey: enabledKey),
           let saved = try? JSONDecoder().decode([UUID: Bool].self, from: data) {
            for i in initial.indices {
                if let savedEnabled = saved[initial[i].id] {
                    initial[i].enabled = savedEnabled
                }
            }
        }
        self.pids = initial

        // Observe changes and persist enabled flags
        $pids
            .sink { [weak self] (pids: [OBDPID]) in
                self?.persistEnabledFlags(pids)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func toggle(_ pid: OBDPID) {
        guard let idx = pids.firstIndex(where: { $0.id == pid.id }) else { return }
        pids[idx].enabled.toggle()
    }

    func setEnabled(_ enabled: Bool, for pid: OBDPID) {
        guard let idx = pids.firstIndex(where: { $0.id == pid.id }) else { return }
        pids[idx].enabled = enabled
    }

    var enabledPIDs: [OBDPID] {
        pids.filter { $0.enabled }
    }

    // MARK: - Persistence

    private func persistEnabledFlags(_ pids: [OBDPID]) {
        let map = Dictionary(uniqueKeysWithValues: pids.map { ($0.id, $0.enabled) })
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: enabledKey)
        }
    }
}
