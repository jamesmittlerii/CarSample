import SwiftUI

struct PIDToggleListView: View {
    @StateObject private var store = PIDStore.shared

    var body: some View {
        List {
            if store.pids.contains(where: { $0.enabled }) {
                Section(header: Text("Enabled")) {
                    ForEach(store.enabledPIDs) { pid in
                        PIDToggleRow(
                            pid: pid,
                            isOn: Binding(
                                get: { pid.enabled },
                                set: { store.setEnabled($0, for: pid) }
                            )
                        )
                    }
                    .onMove { indices, newOffset in
                        store.moveEnabled(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }

            if store.pids.contains(where: { !$0.enabled }) {
                Section(header: Text("Disabled")) {
                    ForEach(store.pids.filter { !$0.enabled }) { pid in
                        PIDToggleRow(
                            pid: pid,
                            isOn: Binding(
                                get: { pid.enabled },
                                set: { store.setEnabled($0, for: pid) }
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
