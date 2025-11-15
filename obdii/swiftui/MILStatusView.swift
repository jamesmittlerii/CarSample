/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
Swift UI view for the MIL status
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */
import SwiftUI
import Combine
import SwiftOBD2



struct MILStatusView: View {
    @StateObject private var viewModel = MILStatusViewModel()
    // Demand-driven interest token for this view
    @State private var interestToken: UUID = PIDInterestRegistry.shared.makeToken()

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
        .onAppear {
            // Request streaming for MIL/status while this view is visible
            PIDInterestRegistry.shared.replace(pids: [.mode1(.status)], for: interestToken)
        }
        .onDisappear {
            // Clear our interest when leaving
            PIDInterestRegistry.shared.clear(token: interestToken)
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
