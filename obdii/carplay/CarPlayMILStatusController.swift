import CarPlay
import UIKit
import SwiftOBD2
import Combine


@MainActor
class CarPlayMILStatusController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPListTemplate?
    private let connectionManager: OBDConnectionManager
    private var cancellables = Set<AnyCancellable>()
    private var previousMILStatus: Status?
    
    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
        
       
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        // Observe connection state changes to keep the UI in sync
        OBDConnectionManager.shared.$MILStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)
    }
    
    private func makeItem(_ text: String, detailText: String) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }
    
    private func buildSections() -> [CPListSection] {
        let current = OBDConnectionManager.shared.MILStatus
        var items: [CPListItem] = []

        guard let status = current else {
            items.append(makeItem("No MIL Status", detailText: ""))
            let section = CPListSection(items: items)
            return [section]
        }

        // Top-level flags/values
        let dtcLabel = "\(status.dtcCount) DTC" + (status.dtcCount == 1 ? "" : "s")
        let milLabel = status.milOn ? "On" : "Off"
        items.append(makeItem("MIL", detailText: "\(milLabel) (\(dtcLabel))"))
        
        // Readiness monitors: filter to supported, then sort so Not Ready first, Ready next, unknown last
        let supported = status.monitors.filter { $0.supported }
        let sorted = supported.sorted { lhs, rhs in
            // Map ready state to priority: Not Ready (false) = 0, Ready (true) = 1, Unknown (nil) = 2
            func priority(for ready: Bool?) -> Int {
                switch ready {
                case .some(false): return 0
                case .some(true):  return 1
                case .none:        return 2
                }
            }
            let lp = priority(for: lhs.ready)
            let rp = priority(for: rhs.ready)
            if lp != rp { return lp < rp }
            // Stable fallback by name to keep order deterministic
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        for monitor in sorted {
            let detail: String
            if let ready = monitor.ready {
                detail = ready ? "Ready" : "Not Ready"
            } else {
                detail = "—"
            }
            items.append(makeItem(monitor.name, detailText: detail))
        }

        let section = CPListSection(items: items)
        return [section]
    }

    private func refreshSection() {
        guard let template = currentTemplate else { return }
        
        let current = OBDConnectionManager.shared.MILStatus
        
        // Early exit if nothing changed
        if let previous = previousMILStatus, previous == current {
            return
        }
        
        // Update UI and remember last shown state
        let sections = buildSections()
        previousMILStatus = current
        template.updateSections(sections)
    }

    /// Creates the root template for the Settings tab.
    func makeRootTemplate() -> CPListTemplate {
        let sections = buildSections()
        let template = CPListTemplate(title: "MILStatus", sections: sections)
        template.tabTitle = "MIL"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        self.currentTemplate = template
        
        // Initialize previous snapshot to match what we just rendered
        previousMILStatus = OBDConnectionManager.shared.MILStatus
        
        return template
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

