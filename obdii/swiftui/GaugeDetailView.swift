import SwiftUI
import SwiftOBD2

struct GaugeDetailView: View {
    let pid: OBDPID
    @ObservedObject var connectionManager: OBDConnectionManager

    private var stats: OBDConnectionManager.PIDStats? {
        connectionManager.stats(for: pid.pid)
    }

    var body: some View {
        List {
            Section(header: Text("Current")) {
                if let s = stats {
                    Text(pid.formatted(measurement: s.latest, includeUnits: true))
                } else {
                    Text("— \(pid.displayUnits)")
                        .foregroundColor(.secondary)
                }
            }

            if let s = stats {
                Section(header: Text("Statistics")) {
                    Text("Min: \(pid.formatted(measurement: MeasurementResult(value: s.min, unit: s.latest.unit), includeUnits: true))")
                    Text("Max: \(pid.formatted(measurement: MeasurementResult(value: s.max, unit: s.latest.unit), includeUnits: true))")
                    Text("Samples: \(s.sampleCount)")
                }
            }

            Section(header: Text("Typical Range")) {
                Text(pid.displayRange)
            }
        }
        .navigationTitle(pid.name)
    }
}

#Preview {
    NavigationView {
        GaugeDetailView(pid: PIDStore.shared.enabledGauges.first ?? PIDStore.shared.pids.first!, connectionManager: OBDConnectionManager.shared)
    }
}
