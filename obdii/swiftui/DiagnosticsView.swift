import SwiftUI
import SwiftOBD2
import Combine

private func severitySymbolName(for severity: CodeSeverity) -> String {
    switch severity {
    case .low:       return "exclamationmark.circle"
    case .moderate:  return "exclamationmark.triangle"
    case .high:      return "bolt.trianglebadge.exclamationmark"
    case .critical:  return "xmark.octagon"
    }
}

private func severityColor(_ severity: CodeSeverity) -> Color {
    switch severity {
    case .low:
        return .yellow
    case .moderate:
        return .orange
    case .high:
        return .red
    case .critical:
        // Slightly different red for emphasis
        return Color(red: 0.85, green: 0.0, blue: 0.0)
    }
}

private func severitySectionTitle(_ severity: CodeSeverity) -> String {
    switch severity {
    case .critical: return "Critical"
    case .high:     return "High Severity"
    case .moderate: return "Moderate"
    case .low:      return "Low"
    }
}

struct DiagnosticsView: View {
    @StateObject private var connectionManager = OBDConnectionManager.shared

    // Ordered severity buckets (Critical → Low)
    private let order: [CodeSeverity] = [.critical, .high, .moderate, .low]

    var body: some View {
        NavigationView {
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
                                                Image(systemName: severitySymbolName(for: code.severity))
                                                    .foregroundStyle(severityColor(code.severity))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(code.code) • \(code.title)")
                                                        .lineLimit(1)
                                                    Text(code.severity.rawValue)
                                                        .font(.footnote)
                                                        .foregroundStyle(.secondary)
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
            .navigationTitle("DTCs")
        }
    }
}

#Preview {
    DiagnosticsView()
}
