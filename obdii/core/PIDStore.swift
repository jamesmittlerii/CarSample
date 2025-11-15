/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
These are the pids we are publishing
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import Foundation
import Combine

@MainActor
final class PIDStore: ObservableObject {
    static let shared = PIDStore()

    @Published var pids: [OBDPID]

    // Persist enabled flags keyed by the Mode1 command string (CommandProperties.command)
    private let enabledKey = "PIDStore.enabledByCommand"
    // Persist the order of enabled PIDs by their Mode1 command string
    private let enabledOrderKey = "PIDStore.enabledOrderByCommand"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Start from the library defaults
        var initial = OBDPIDLibrary.standard

        // Restore saved enabled flags keyed by command string
        if let data = UserDefaults.standard.data(forKey: enabledKey),
           let saved = try? JSONDecoder().decode([String: Bool].self, from: data) {
            for i in initial.indices {
                let commandKey = initial[i].pid.properties.command
                if let savedEnabled = saved[commandKey] {
                    initial[i].enabled = savedEnabled
                }
            }
        }

        // Restore enabled order and apply it to the enabled subset
        if let orderData = UserDefaults.standard.data(forKey: enabledOrderKey),
           let savedOrder = try? JSONDecoder().decode([String].self, from: orderData) {
            // Partition into enabled and disabled preserving current relative order
            var enabled = initial.filter { $0.enabled }
            let disabled = initial.filter { !$0.enabled }

            // Sort enabled by saved order; items not in saved order go to the end preserving their relative order
            let indexByCommand = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
            enabled.sort { lhs, rhs in
                let l = indexByCommand[lhs.pid.properties.command]
                let r = indexByCommand[rhs.pid.properties.command]
                switch (l, r) {
                case let (li?, ri?): return li < ri
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return false
                }
            }

            initial = enabled + disabled
        }

        self.pids = initial

        // Observe changes and persist enabled flags and order
        $pids
            .sink { [weak self] (pids: [OBDPID]) in
                guard let self else { return }
                self.persistEnabledFlags(pids)
                self.persistEnabledOrder(pids)
            }
            .store(in: &cancellables)
    }

    //  Public API

    func toggle(_ pid: OBDPID) {
        guard let idx = pids.firstIndex(where: { $0.id == pid.id }) else { return }
        pids[idx].enabled.toggle()
    }

    func setEnabled(_ enabled: Bool, for pid: OBDPID) {
        guard let idx = pids.firstIndex(where: { $0.id == pid.id }) else { return }
        pids[idx].enabled = enabled
    }

    var enabledGauges: [OBDPID] {
        // Enabled items are the prefix (by construction after applying saved order)
        pids.filter { $0.enabled && $0.kind == OBDPID.Kind.gauge }
    }

   
    // reorder the enabled gauges
    func moveEnabled(fromOffsets source: IndexSet, toOffset destination: Int) {
        
        var enabledGauges: [OBDPID] = pids.filter { $0.enabled && $0.kind == .gauge }
        let disabledGauges: [OBDPID] = pids.filter { !$0.enabled && $0.kind == .gauge }
        let nonGauges: [OBDPID] = pids.filter { $0.enabled && $0.kind != .gauge }
        
        // If there are no enabled gauges, there's nothing to move.
        guard !enabledGauges.isEmpty else { return }

        // Apply the move within the enabledGauges subset
        enabledGauges.move(fromOffsets: source, toOffset: destination)

        // reassemble the whole array of pids
        pids = enabledGauges + disabledGauges + nonGauges
  
    }

    //  Persistence

    private func persistEnabledFlags(_ pids: [OBDPID]) {
        // Key by the stable Mode1 command string
        let map: [String: Bool] = Dictionary(
            uniqueKeysWithValues: pids.map { ($0.pid.properties.command, $0.enabled) }
        )
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: enabledKey)
        }
    }

    private func persistEnabledOrder(_ pids: [OBDPID]) {
        // Persist only the enabled order by command string in their current on-screen order
        let enabledCommands = pids.filter { $0.enabled }.map { $0.pid.properties.command }
        if let data = try? JSONEncoder().encode(enabledCommands) {
            UserDefaults.standard.set(data, forKey: enabledOrderKey)
        }
    }
}
