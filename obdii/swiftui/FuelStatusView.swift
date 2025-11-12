import SwiftUI
import Combine
import SwiftOBD2

@MainActor
final class FuelStatusViewModel: ObservableObject {
    @Published private(set) var status: [StatusCodeMetadata?] = []
    private var cancellable: AnyCancellable?
    private var lastEmitted: [StatusCodeMetadata?] = []

    init(connectionManager: OBDConnectionManager? = nil) {
        let manager = connectionManager ?? OBDConnectionManager.shared
        cancellable = manager.$fuelStatus
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

    var bank1: StatusCodeMetadata? { status.indices.contains(0) ? status[0] : nil }
    var bank2: StatusCodeMetadata? { status.indices.contains(1) ? status[1] : nil }
    var hasAnyStatus: Bool { bank1 != nil || bank2 != nil }
}

struct FuelStatusView: View {
    @StateObject private var viewModel = FuelStatusViewModel()

    var body: some View {
        List {
            Section(header: Text("Fuel Control Status")) {
                if let b1 = viewModel.bank1 {
                    HStack(spacing: 12) {
                        Image(systemName: "fuelpump.fill")
                            .foregroundStyle(.blue)
                            .imageScale(.large)
                        Text("Bank 1")
                        Spacer()
                        Text(b1.description)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityLabel("Bank 1, \(b1.description)")
                }

                if let b2 = viewModel.bank2 {
                    HStack(spacing: 12) {
                        Image(systemName: "fuelpump.fill")
                            .foregroundStyle(.blue)
                            .imageScale(.large)
                        Text("Bank 2")
                        Spacer()
                        Text(b2.description)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityLabel("Bank 2, \(b2.description)")
                }

                if !viewModel.hasAnyStatus {
                    Label("No Fuel System Status Codes", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Fuel Status")
    }
}

#Preview {
    NavigationView { FuelStatusView() }
}
