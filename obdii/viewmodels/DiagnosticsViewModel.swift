// DiagnosticsViewModel.swift
import Foundation
import Combine
import SwiftOBD2

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    struct Section: Equatable {
        let title: String
        let severity: CodeSeverity
        let items: [TroubleCodeMetadata]
    }

    @Published private(set) var sections: [Section] = []
    @Published private(set) var isEmpty: Bool = true

    private var cancellable: AnyCancellable?

    init(connectionManager: OBDConnectionManager? = nil) {
        let manager = connectionManager ?? OBDConnectionManager.shared
        cancellable = manager.$troubleCodes
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] codes in
                self?.rebuildSections(from: codes)
            }
    }

    private func rebuildSections(from codes: [TroubleCodeMetadata]) {
        guard !codes.isEmpty else {
            sections = []
            isEmpty = true
            return
        }

        let grouped = Dictionary(grouping: codes, by: { $0.severity })
        let order: [CodeSeverity] = [.critical, .high, .moderate, .low]

        sections = order.compactMap { severity in
            guard let list = grouped[severity], !list.isEmpty else { return nil }
            return Section(
                title: title(for: severity),
                severity: severity,
                items: list
            )
        }
        isEmpty = sections.isEmpty
    }

    private func title(for severity: CodeSeverity) -> String {
        switch severity {
        case .critical: return "Critical"
        case .high:     return "High"
        case .moderate: return "Moderate"
        case .low:      return "Low"
        }
    }
}
