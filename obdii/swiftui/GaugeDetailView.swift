import SwiftUI
import SwiftOBD2
import Combine


struct GaugeDetailView: View {
    @StateObject private var viewModel: GaugeDetailViewModel

    init(pid: OBDPID, connectionManager: OBDConnectionManager) {
        _viewModel = StateObject(wrappedValue: GaugeDetailViewModel(pid: pid, connectionManager: connectionManager))
    }

    var body: some View {
        List {
            Section(header: Text("Current")) {
                if let s = viewModel.stats {
                    Text(viewModel.pid.formatted(measurement: s.latest, includeUnits: true))
                } else {
                    Text("— \(viewModel.pid.displayUnits)")
                        .foregroundColor(.secondary)
                }
            }

            if let s = viewModel.stats {
                Section(header: Text("Statistics")) {
                    Text("Min: \(viewModel.pid.formatted(measurement: MeasurementResult(value: s.min, unit: s.latest.unit), includeUnits: true))")
                    Text("Max: \(viewModel.pid.formatted(measurement: MeasurementResult(value: s.max, unit: s.latest.unit), includeUnits: true))")
                    Text("Samples: \(s.sampleCount)")
                }
            }

            Section(header: Text("Maximum Range")) {
                Text(viewModel.pid.displayRange)
            }
        }
        .navigationTitle(viewModel.pid.name)
    }
}

#Preview {
    NavigationView {
        GaugeDetailView(
            pid: PIDStore.shared.enabledGauges.first ?? PIDStore.shared.pids.first!,
            connectionManager: OBDConnectionManager.shared
        )
    }
}
