import SwiftUI
import SwiftOBD2
import Combine

struct DiagnosticsView: View {
    @StateObject private var connectionManager = OBDConnectionManager.shared

    // Ordered severity buckets (Critical → Low)
    private let order: [CodeSeverity] = [.critical, .high, .moderate, .low]

    var body: some View {
        NavigationStack {
            Group {
                if connectionManager.troubleCodes.isEmpty {
                    List {
                        Text("No Diagnostic Trouble Codes")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        let grouped = Dictionary(grouping: connectionManager.troubleCodes, by: { $0.severity })
                        ForEach(order, id: \.self) { severity in
                            if let list = grouped[severity], !list.isEmpty {
                                Section(header: Text(severitySectionTitle(severity))) {
                                    ForEach(list, id: \.code) { code in
                                        NavigationLink {
                                            DTCDetailView(code: code)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: imageName(for: code.severity))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(code.code) • \(code.title)")
                                                        .lineLimit(1)
                                                    Text(code.severity.rawValue)
                                                        .font(.footnote)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Diagnostic Codes")
        }
    }
}

#Preview {
    DiagnosticsView()
}
