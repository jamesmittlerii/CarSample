import SwiftUI
import Combine
import SwiftOBD2

@MainActor
final class MILStatusViewModel: ObservableObject {
    @Published private(set) var status: Status?
    private var cancellable: AnyCancellable?
    private var lastEmitted: Status?

    init(connectionManager: OBDConnectionManager? = nil) {
        let manager = connectionManager ?? OBDConnectionManager.shared
        cancellable = manager.$MILStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                // Deduplicate identical snapshots
                if self.lastEmitted != newValue {
                    self.lastEmitted = newValue
                    self.status = newValue
                }
            }
    }

    var headerText: String {
        guard let status else { return "No MIL Status" }
        let dtcLabel = "\(status.dtcCount) DTC" + (status.dtcCount == 1 ? "" : "s")
        let milLabel = status.milOn ? "On" : "Off"
        return "MIL: \(milLabel) (\(dtcLabel))"
    }

    var hasStatus: Bool { status != nil }

    var sortedSupportedMonitors: [ReadinessMonitor] {
        guard let status else { return [] }
        let supported = status.monitors.filter { $0.supported }
        return supported.sorted { lhs, rhs in
            func priority(for ready: Bool?) -> Int {
                switch ready {
                case .some(false): return 0   // Not Ready first
                case .some(true):  return 1   // Ready next
                case .none:        return 2   // Unknown last
                }
            }
            let lp = priority(for: lhs.ready)
            let rp = priority(for: rhs.ready)
            if lp != rp { return lp < rp }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

struct MILStatusView: View {
    @StateObject private var viewModel = MILStatusViewModel()

    var body: some View {
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

private extension ReadinessMonitor {
    var readyText: String {
        if let ready {
            return ready ? "Ready" : "Not Ready"
        }
        return "—"
    }
}

#Preview {
    NavigationView { MILStatusView() }
}
