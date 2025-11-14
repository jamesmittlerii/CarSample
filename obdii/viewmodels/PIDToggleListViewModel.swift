import Foundation
import Combine
import SwiftOBD2

@MainActor
final class PIDToggleListViewModel: ObservableObject {
    // Mirror of the store PIDs for simple view binding
    @Published private(set) var pids: [OBDPID] = []

    private let store: PIDStore
    private var cancellables = Set<AnyCancellable>()

    // Designated initializer without default argument to avoid nonisolated default evaluation
    init(store: PIDStore) {
        self.store = store

        // Keep local pids in sync with the store
        store.$pids
            .receive(on: RunLoop.main)
            .assign(to: &$pids)
    }

    // Convenience initializer accessing MainActor-isolated singleton safely
    convenience init() {
        self.init(store: .shared)
    }

    // Computed helpers for sections
    var enabledIndices: [Int] {
        pids.indices.filter { pids[$0].enabled && pids[$0].kind == .gauge }
    }

    var disabledIndices: [Int] {
        pids.indices.filter { !pids[$0].enabled && pids[$0].kind == .gauge }
    }

    // Intents
    func toggle(at index: Int, to isOn: Bool) {
        guard pids.indices.contains(index) else { return }
        store.pids[index].enabled = isOn
    }

    func moveEnabled(fromOffsets indices: IndexSet, toOffset newOffset: Int) {
        store.moveEnabled(fromOffsets: indices, toOffset: newOffset)
    }
}
