import SwiftUI
import Combine
import SwiftOBD2



struct MILStatusView: View {
    @StateObject private var viewModel = MILStatusViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Malfunction Indicator Lamp")) {
                    if viewModel.hasStatus {
                        HStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(.orange)
                                .imageScale(.large)
                            Text(viewModel.headerText)
                                .font(.headline)
                        }
                        .accessibilityLabel(viewModel.headerText)
                    } else {
                        Label("No MIL Status", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.hasStatus {
                    Section(header: Text("Readiness Monitors")) {
                        ForEach(viewModel.sortedSupportedMonitors, id: \.name) { monitor in
                            HStack(spacing: 12) {
                                Image(systemName: "gauge")
                                    .foregroundStyle(.blue)
                                    .imageScale(.medium)
                                Text(monitor.name)
                                Spacer()
                                Text(monitor.readyText)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("\(monitor.name), \(monitor.readyText)")
                        }
                    }
                }
            }
            .navigationTitle("MIL Status")
        }
    }
}

private extension ReadinessMonitor {
    var readyText: String {
        if let ready {
            return ready ? "Ready" : "Not Ready"
        }
        return "—"
    }
}

#Preview {
    MILStatusView()
}
