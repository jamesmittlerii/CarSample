import SwiftUI

struct PIDToggleListView: View {
    @StateObject private var viewModel = PIDToggleListViewModel()

    var body: some View {
        List {
            // Enabled section
            let enabled = viewModel.enabledIndices
            if !enabled.isEmpty {
                Section(header: Text("Enabled")) {
                    ForEach(enabled, id: \.self) { index in
                        let pid = viewModel.pids[index]
                        PIDToggleRow(
                            pid: pid,
                            isOn: Binding(
                                get: { viewModel.pids[index].enabled },
                                set: { newValue in viewModel.toggle(at: index, to: newValue) }
                            )
                        )
                    }
                    .onMove { indices, newOffset in
                        viewModel.moveEnabled(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }

            // Disabled section
            let disabled = viewModel.disabledIndices
            if !disabled.isEmpty {
                Section(header: Text("Disabled")) {
                    ForEach(disabled, id: \.self) { index in
                        let pid = viewModel.pids[index]
                        PIDToggleRow(
                            pid: pid,
                            isOn: Binding(
                                get: { viewModel.pids[index].enabled },
                                set: { newValue in viewModel.toggle(at: index, to: newValue) }
                            )
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
