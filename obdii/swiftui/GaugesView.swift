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
    // Track visible tile IDs
    @State private var visibleTileIDs: Set<UUID> = []

    init(connectionManager: OBDConnectionManager, pidStore: PIDStore? = nil) {
        let resolvedStore = pidStore ?? PIDStore.shared
        _viewModel = StateObject(wrappedValue: GaugesViewModel(connectionManager: connectionManager, pidStore: resolvedStore))
    }

    // Adaptive grid: 2–4 columns depending on width
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16, alignment: .top)
    ]

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
                    .visibilityTrack(id: tile.id)
                }
            }
            .padding()
        }
        .onVisibleIDsChange { ids in
            visibleTileIDs = ids
            updateInterest()
        }
        // Updated to iOS 17+ zero-parameter overload
        .onChange(of: viewModel.tiles) {
            updateInterest()
        }
        .onAppear {
            updateInterest()
        }
        .onDisappear {
            PIDInterestRegistry.shared.clear(token: interestToken)
            visibleTileIDs.removeAll()
        }
    }

    private func updateInterest() {
        // Map visible tiles to their commands
        let visibleCommands: Set<OBDCommand> = Set(
            viewModel.tiles
                .filter { visibleTileIDs.contains($0.id) }
                .map { $0.pid.pid }
        )
        PIDInterestRegistry.shared.replace(pids: visibleCommands, for: interestToken)
    }
}

// MARK: - Visibility tracking modifier

private struct VisibleIDPreferenceKey: PreferenceKey {
    static var defaultValue: Set<UUID> = []
    static func reduce(value: inout Set<UUID>, nextValue: () -> Set<UUID>) {
        value.formUnion(nextValue())
    }
}

private struct VisibilityTrackModifier: ViewModifier {
    let id: UUID
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .preference(key: VisibleIDPreferenceKey.self, value: frame.isOnScreen ? [id] : [])
                }
            )
    }
}

private extension View {
    func visibilityTrack(id: UUID) -> some View {
        modifier(VisibilityTrackModifier(id: id))
    }

    func onVisibleIDsChange(_ action: @escaping (Set<UUID>) -> Void) -> some View {
        onPreferenceChange(VisibleIDPreferenceKey.self, perform: action)
    }
}

private extension CGRect {
    var isOnScreen: Bool {
        guard let screen = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.bounds else { return false }
        return self.intersects(screen)
    }
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
