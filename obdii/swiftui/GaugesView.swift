import SwiftUI
import Combine
import SwiftOBD2
import UIKit

struct GaugesView: View {
    @StateObject private var connectionManager = OBDConnectionManager.shared
    @StateObject private var pidStore = PIDStore.shared

    // Adaptive grid: 2–4 columns depending on width
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(pidStore.enabledGauges, id: \.id) { pid in
                        NavigationLink {
                            GaugeDetailView(pid: pid, connectionManager: connectionManager)
                        } label: {
                            GaugeTile(pid: pid, manager: connectionManager)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("GaugeTile_\(pid.id.uuidString)")
                    }
                }
                .padding()
            }
            .navigationTitle("Gauges")
        }
    }
}

private struct GaugeTile: View {
    let pid: OBDPID
    @ObservedObject var manager: OBDConnectionManager

    private var measurement: MeasurementResult? {
        manager.stats(for: pid.pid)?.latest
    }

    var body: some View {
        VStack(spacing: 2) {
            // SwiftUI gauge view replacing the UIImage-based drawing for app UI
            RingGaugeView(pid: pid, measurement: measurement)
                .frame(width: 120, height: 120)

            // Title
            Text(pid.label)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func subtitleText() -> String {
        if let m = measurement {
            return pid.formatted(measurement: m, includeUnits: true)
        } else {
            return "— \(pid.displayUnits)"
        }
    }
}

#Preview {
    GaugesView()
}
