import SwiftUI

struct PIDToggleListView: View {
    @StateObject private var store = PIDStore.shared

    var body: some View {
        List {
            // Enabled section
            let enabledIndices = store.pids.indices.filter { store.pids[$0].enabled && store.pids[$0].kind == .gauge}
            if !enabledIndices.isEmpty {
                Section(header: Text("Enabled")) {
                    ForEach(enabledIndices, id: \.self) { index in
                        let pid = store.pids[index]
                        PIDToggleRow(
                            pid: pid,
                            isOn: Binding(
                                get: { store.pids[index].enabled },
                                set: { newValue in store.pids[index].enabled = newValue }
                            )
                        )
                    }
                    .onMove { indices, newOffset in
                        store.moveEnabled(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }

            // Disabled section
            let disabledIndices = store.pids.indices.filter { !store.pids[$0].enabled && store.pids[$0].kind == .gauge}
            if !disabledIndices.isEmpty {
                Section(header: Text("Disabled")) {
                    ForEach(disabledIndices, id: \.self) { index in
                        let pid = store.pids[index]
                        PIDToggleRow(
                            pid: pid,
                            isOn: Binding(
                                get: { store.pids[index].enabled },
                                set: { newValue in store.pids[index].enabled = newValue }
                            )
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gauges")
    }
}

private struct PIDToggleRow: View {
    let pid: OBDPID
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pid.name)
                Text(pid.displayRange)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("PIDToggle_\(pid.id.uuidString)")
    }
}

#Preview {
    NavigationView { PIDToggleListView() }
}
