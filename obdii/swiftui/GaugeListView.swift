import SwiftUI
import SwiftOBD2

struct GaugeListView: View {
    @ObservedObject var connectionManager: OBDConnectionManager
    @ObservedObject private var pidStore = PIDStore.shared

    var body: some View {
        List {
            Section(header: Text("Gauges")) {
                ForEach(pidStore.enabledGauges) { pid in
                    NavigationLink(destination: GaugeDetailView(pid: pid, connectionManager: connectionManager)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pid.name)
                                    .font(.headline)
                                Text(pid.displayRange)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(currentValueText(for: pid))
                                .font(.title3.monospacedDigit())
                                .foregroundColor(currentValueColor(for: pid))
                                .accessibilityLabel("\(pid.name) value")
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle("Live Gauges")
    }

    private func currentValueText(for pid: OBDPID) -> String {
        if let stats = connectionManager.stats(for: pid.pid) {
            return pid.formatted(measurement: stats.latest, includeUnits: true)
        } else {
            return "— \(pid.displayUnits)"
        }
    }

    private func currentValueColor(for pid: OBDPID) -> Color {
        if let stats = connectionManager.stats(for: pid.pid) {
            return pid.color(for: stats.latest.value)
        } else {
            return .secondary
        }
    }
}

#Preview {
    NavigationView {
        GaugeListView(connectionManager: .shared)
    }
}
