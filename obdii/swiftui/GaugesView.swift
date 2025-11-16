/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
Swift UI view for a grid of gauges
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import SwiftUI
import Combine
import SwiftOBD2
import UIKit

@MainActor
struct GaugesView: View {
    @StateObject private var viewModel: GaugesViewModel

    // Demand-driven polling token
    @State private var interestToken: UUID = PIDInterestRegistry.shared.makeToken()

    init(connectionManager: OBDConnectionManager, pidStore: PIDStore? = nil) {
        let resolvedStore = pidStore ?? PIDStore.shared
        _viewModel = StateObject(wrappedValue: GaugesViewModel(connectionManager: connectionManager, pidStore: resolvedStore))
    }

    // Adaptive grid: 2–4 columns depending on width
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16, alignment: .top)
    ]

    // Identity of tiles that should trigger interest updates (ignores live measurements)
    private var tileIdentities: [TileIdentity] {
        viewModel.tiles.map { TileIdentity(id: $0.id, name: $0.pid.name) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.tiles) { tile in
                    NavigationLink {
                        GaugeDetailView(pid: tile.pid, connectionManager: .shared)
                    } label: {
                        GaugeTile(pid: tile.pid, measurement: tile.measurement)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("GaugeTile_\(tile.pid.id.uuidString)")
                }
            }
            .padding()
        }
        // Only react when the tile identities (names/count/order) change, not measurements
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
        // Register interest for all gauge tiles currently in the grid
        let commands: Set<OBDCommand> = Set(viewModel.tiles.map { $0.pid.pid })
        PIDInterestRegistry.shared.replace(pids: commands, for: interestToken)
    }
}

// Minimal equatable identity for tiles (ignores measurements)
struct TileIdentity: Equatable {
    let id: UUID
    let name: String
}

private struct GaugeTile: View {
    let pid: OBDPID
    let measurement: MeasurementResult?

    var body: some View {
        VStack(spacing: 0) {
            RingGaugeView(pid: pid, measurement: measurement)
                .frame(width: 120, height: 120)
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
}

#Preview {
    NavigationStack {
        GaugesView(connectionManager: .shared, pidStore: .shared)
    }
}
