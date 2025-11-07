import CarPlay
import UIKit
import SwiftOBD2

@MainActor
class CarPlaySettingsController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPListTemplate?

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }
    
    private func makeItem(_ text: String, detailText: String) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }

    private func makeUnitsItem() -> CPListItem {
        let item = CPListItem(text: "Units", detailText: ConfigData.shared.units.rawValue)
        item.handler = { [weak self] _, completion in
            // Toggle units
            ConfigData.shared.units = ConfigData.shared.units.next

            // Update the UI: rebuild the section and update the template
            self?.refreshSection()
            completion()
        }
        return item
    }

    // New: Connection details item
    private func makeConnectionDetailsItem() -> CPListItem {
        let type = ConfigData.shared.connectionType
        let typeText = type.rawValue

        // Build a concise detail string depending on connection type
        let detail: String
        switch type {
        case .demo:
            detail = "Demo (no actual connection)"
        case .wifi:
            let host = ConfigData.shared.wifiHost
            let port = ConfigData.shared.wifiPort
            detail = "\(typeText) • \(host):\(port)"
        case .bluetooth:
            // If you have a selected peripheral name/identifier, append it here
            detail = typeText
        }

        let item = CPListItem(text: "Connection", detailText: detail)
        item.handler = { [weak self] _, completion in
            // Nothing to push for now; simply complete.
            // If desired, you could present a detail template here.
            self?.refreshSection()
            completion()
        }
        return item
    }

    private func buildSection() -> CPListSection {
        // Fetch app metadata
        let bundle = Bundle.main
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let aboutTitle = "About"
        let aboutDetail = "\(displayName) v\(version) build:\(build)"

        // Items (Units has a custom handler; others are inert for now)
        let items: [CPListItem] = [
            makeUnitsItem(),
            makeConnectionDetailsItem(),
            makeItem(aboutTitle, detailText: aboutDetail)
        ]
        return CPListSection(items: items)
    }

    private func refreshSection() {
        guard let template = currentTemplate else { return }
        let section = buildSection()
        template.updateSections([section])
    }

    /// Creates the root template for the Settings tab.
    func makeRootTemplate() -> CPListTemplate {
        let section = buildSection()
        let template = CPListTemplate(title: "Settings", sections: [section])
        template.tabTitle = "Settings"
        template.tabImage = UIImage(systemName: "gear")
        self.currentTemplate = template
        return template
    }
}
