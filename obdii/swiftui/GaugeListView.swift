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
    // Track visible IDs
    @State private var visibleIDs: Set<UUID> = []
    // Remember last set we registered to avoid transient drops
    @State private var lastRegistered: Set<OBDCommand> = []

    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
        _viewModel = StateObject(wrappedValue: GaugesViewModel(connectionManager: connectionManager, pidStore: .shared))
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
                    .visibilityTrack(id: tile.id)
                }
            }
        }
        .navigationTitle("Live Gauges")
        .onVisibleIDsChange { ids in
            visibleIDs = ids
            updateInterest()
        }
        .onChange(of: viewModel.tiles) {
            updateInterest()
        }
        .onAppear {
            updateInterest()
        }
        .onDisappear {
            PIDInterestRegistry.shared.clear(token: interestToken)
            visibleIDs.removeAll()
            lastRegistered.removeAll()
        }
    }

    private func updateInterest() {
        let newVisible: [GaugesViewModel.Tile] = viewModel.tiles.filter { visibleIDs.contains($0.id) }
        let visibleCommands: Set<OBDCommand> = Set(newVisible.map { $0.pid.pid })

        if visibleCommands.isEmpty {
            // Avoid replacing with empty to prevent transient drops when visibility is momentarily unknown.
            // Do nothing; keep lastRegistered alive until we truly disappear.
            return
        }

        lastRegistered = visibleCommands
        PIDInterestRegistry.shared.replace(pids: visibleCommands, for: interestToken)
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

// Reuse the same visibility helpers from GaugesView

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

#Preview {
    NavigationView {
        GaugeListView(connectionManager: .shared)
    }
}
