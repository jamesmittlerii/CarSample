/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
Swift UI view for showing a textual list of gauges
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import SwiftUI
import SwiftOBD2

struct GaugeListView: View {
    @ObservedObject var connectionManager: OBDConnectionManager
    @StateObject private var viewModel: GaugesViewModel

    // Demand-driven polling token
    @State private var interestToken: UUID = PIDInterestRegistry.shared.makeToken()

    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
        _viewModel = StateObject(wrappedValue: GaugesViewModel(connectionManager: connectionManager, pidStore: .shared))
    }
    
    private var tileIdentities: [TileIdentity] {
        viewModel.tiles.map { TileIdentity(id: $0.id, name: $0.pid.name) }
    }

    var body: some View {
        List {
            Section(header: Text("Gauges")) {
                ForEach(viewModel.tiles) { tile in
                    NavigationLink(destination: GaugeDetailView(pid: tile.pid, connectionManager: connectionManager)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tile.pid.name)
                                    .font(.headline)
                                Text(tile.pid.displayRange)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(currentValueText(for: tile))
                                .font(.title3.monospacedDigit())
                                .foregroundColor(currentValueColor(for: tile))
                                .accessibilityLabel("\(tile.pid.name) value")
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle("Live Gauges")
        .onChange(of: tileIdentities) {
            updateInterest()
        }
        .onAppear {
            updateInterest()
        }
        .onDisappear {
            PIDInterestRegistry.shared.clear(token: interestToken)
        }
    }

    private func updateInterest() {
        // Register interest for all gauge tiles currently in the list
        let commands: Set<OBDCommand> = Set(viewModel.tiles.map { $0.pid.pid })
        PIDInterestRegistry.shared.replace(pids: commands, for: interestToken)
    }

    private func currentValueText(for: GaugesViewModel.Tile) -> String {
        if let m = `for`.measurement {
            return `for`.pid.formatted(measurement: m, includeUnits: true)
        } else {
            return "— \(`for`.pid.displayUnits)"
        }
    }

    private func currentValueColor(for: GaugesViewModel.Tile) -> Color {
        if let m = `for`.measurement {
            return `for`.pid.color(for: m.value)
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
