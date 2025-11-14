import SwiftUI
import SwiftOBD2

enum GaugesDisplayMode: String, CaseIterable, Identifiable {
    case gauges
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gauges: return "Gauges"
        case .list: return "List"
        }
    }
}

struct GaugesContainerView: View {
    // Persist the selected mode across runs
    @AppStorage("gaugesDisplayMode") private var storedMode: String = GaugesDisplayMode.gauges.rawValue

    // Bridge stored string <-> enum for Picker
    private var modeBinding: Binding<GaugesDisplayMode> {
        Binding<GaugesDisplayMode>(
            get: { GaugesDisplayMode(rawValue: storedMode) ?? .gauges },
            set: { storedMode = $0.rawValue }
        )
    }

    @ObservedObject var connectionManager: OBDConnectionManager

    var body: some View {
        VStack {
            Picker("Display Mode", selection: modeBinding) {
                ForEach(GaugesDisplayMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            Group {
                switch GaugesDisplayMode(rawValue: storedMode) ?? .gauges {
                case .gauges:
                    GaugesView(connectionManager: connectionManager, pidStore: .shared)
                case .list:
                    GaugeListView(connectionManager: connectionManager)
                 }
            }
        }
        .navigationTitle(titleForMode(GaugesDisplayMode(rawValue: storedMode) ?? .gauges))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func titleForMode(_ mode: GaugesDisplayMode) -> String {
        switch mode {
        case .gauges: return "Gauges"
        case .list: return "List"
        }
    }
}

#Preview {
    NavigationView {
        GaugesContainerView(connectionManager: .shared)
    }
}
