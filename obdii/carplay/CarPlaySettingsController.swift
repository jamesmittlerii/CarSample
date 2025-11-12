import CarPlay
import UIKit
import SwiftOBD2
import Combine
import Network

@MainActor
class CarPlaySettingsController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPListTemplate?
    //private var cancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        // Observe connection state changes to keep the UI in sync
        OBDConnectionManager.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)

        // Observe connection type changes to keep the UI in sync
        ConfigData.shared.$publishedConnectionType
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)

        // Also observe units changes so the list reflects the new value immediately
        ConfigData.shared.$unitsPublished
            .removeDuplicates()
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

    private func makeUnitsItem() -> CPListItem {
        let item = CPListItem(text: "Units", detailText: ConfigData.shared.units.rawValue)
        item.handler = { [weak self] _, completion in
            // Toggle units using the setter so unitsPublished emits
            let next = ConfigData.shared.units.next
            ConfigData.shared.setUnits(next)

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
            detail = "\(typeText) • no actual connection"
        case .wifi:
            let host = ConfigData.shared.wifiHost
            let port = ConfigData.shared.wifiPort
            detail = "\(typeText) • \(host):\(port)"
        case .bluetooth:
            let name = OBDConnectionManager.shared.connectedPeripheralName ?? "unknown"
            detail = "\(typeText) • \(name)"
            // If you have a selected peripheral name/identifier, append it here
           
        }
        
        return makeItem("Connection", detailText: detail)

        
    }
    func errorName(_ error: Error) -> String {
        return String(describing: type(of: error))
    }

    // New: Connection status item
    private func makeConnectionStatusItem() -> CPListItem {
        let state = OBDConnectionManager.shared.connectionState
        let detail: String
        switch state {
        case .disconnected:
            detail = "Disconnected"
        case .connecting:
            detail = "Connecting..."
        case .connected:
            detail = "Connected"
        case .failed(let error):
            // Keep it concise for CarPlay
            
            detail = "Failed: \(error.localizedDescription)"
            
        }
        return makeItem("Connection Status", detailText: detail)
    }
    
    private func makeAboutItem() -> CPListItem {
        let aboutTitle = "About"
        let aboutDetail = aboutDetailString()
        return makeItem(aboutTitle, detailText: aboutDetail)
    }

    private func buildSection() -> CPListSection {
        let items: [CPListItem] = [
            makeConnectionDetailsItem(),
            makeConnectionStatusItem(),
            makeUnitsItem(),
            makeAboutItem()
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
