import CarPlay
import UIKit
import SwiftOBD2

@MainActor
class CarPlayDiagnosticsController {
    private weak var interfaceController: CPInterfaceController?
    private let connectionManager: OBDConnectionManager
    
    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    // MARK: - Root Template

    func makeRootTemplate() -> CPListTemplate {
        let codes = connectionManager.troubleCodes

        // No DTCs → single info row
        if codes.isEmpty {
            let item = CPListItem(text: "No Diagnostic Trouble Codes", detailText: nil)
            let section = CPListSection(items: [item])
            let template = CPListTemplate(title: "Diagnostics", sections: [section])
            template.tabTitle = "Diagnostics"
            template.tabImage = symbolImage(named: "wrench.and.screwdriver")
            return template
        }

        // Group codes by severity
        let grouped = Dictionary(grouping: codes, by: { $0.severity })

        // Ordered severity buckets (Critical → Low)
        let order: [CodeSeverity] = [.critical, .high, .moderate, .low]

        let sections: [CPListSection] = order.compactMap { severity -> CPListSection? in
            guard let list = grouped[severity] else { return nil }

            let items: [CPListItem] = list.map { code in
                let item = CPListItem(
                    text: "\(code.code) • \(code.title)",
                    detailText: code.severity.rawValue
                )
                item.setImage(
                    tintedSymbol(
                        named: imageName(for: code.severity),
                        severity: code.severity
                    )
                )
                item.handler = { [weak self] _, completion in
                    self?.presentOBDDetail(for: code)
                    completion()
                }
                return item
            }

            return CPListSection(items: items,
                                 header: severitySectionTitle(severity),
                                 sectionIndexTitle: nil)
        }

        let template = CPListTemplate(title: "Diagnostics", sections: sections)
        template.tabTitle = "Diagnostics"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        return template
    }

    // MARK: - Detail Template

    private func presentOBDDetail(for code: TroubleCodeMetadata) {
        var items: [CPInformationItem] = [
            CPInformationItem(title: "Code", detail: code.code),
            CPInformationItem(title: "Title", detail: code.title),
            CPInformationItem(title: "Severity", detail: code.severity.rawValue),
            CPInformationItem(title: "Description", detail: code.description)
        ]

        if !code.causes.isEmpty {
            let causesText = code.causes.map { "• \($0)" }.joined(separator: "\n")
            items.append(CPInformationItem(title: "Potential Causes", detail: causesText))
        }

        if !code.remedies.isEmpty {
            let remediesText = code.remedies.map { "• \($0)" }.joined(separator: "\n")
            items.append(CPInformationItem(title: "Possible Remedies", detail: remediesText))
        }

        let template = CPInformationTemplate(
            title: "DTC \(code.code)",
            layout: .twoColumn,
            items: items,
            actions: []
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Helpers

    private func symbolImage(named name: String) -> UIImage? {
        return UIImage(systemName: name)
    }

    private func imageName(for severity: CodeSeverity) -> String {
        switch severity {
        case .low:       return "exclamationmark.circle"
        case .moderate:  return "exclamationmark.triangle"
        case .high:      return "bolt.trianglebadge.exclamationmark"
        case .critical:  return "xmark.octagon"
        }
    }

    private func severityColor(_ severity: CodeSeverity) -> UIColor {
        switch severity {
        case .low:
            return .systemYellow
        case .moderate:
            return .systemOrange
        case .high:
            return .systemRed
        case .critical:
            return UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    // A brighter red for dark mode for better visibility
                    return UIColor(red: 1.0, green: 0.3, blue: 0.25, alpha: 1.0)
                } else {
                    // The original dark red for light mode
                    return UIColor(red: 0.85, green: 0.0, blue: 0.0, alpha: 1.0)
                }
            }
        }
    }

    private func tintedSymbol(named name: String, severity: CodeSeverity) -> UIImage? {
        guard let img = symbolImage(named: name) else { return nil }
        return img.withTintColor(severityColor(severity), renderingMode: .alwaysOriginal)
    }

    private func severitySectionTitle(_ severity: CodeSeverity) -> String {
        switch severity {
        case .critical: return "Critical"
        case .high:     return "High Severity"
        case .moderate: return "Moderate"
        case .low:      return "Low"
        }
    }
}
