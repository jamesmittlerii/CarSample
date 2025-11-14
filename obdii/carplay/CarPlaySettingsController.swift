import CarPlay
import UIKit
import SwiftOBD2
import Combine
import Network

@MainActor
class CarPlaySettingsController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPListTemplate?
    private let viewModel = SettingsViewModel()
    private var cancellables = Set<AnyCancellable>()

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        // Observe SettingsViewModel state so the UI stays in sync
        viewModel.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)

        viewModel.$connectionType
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)

        // Observe units via the ViewModel instead of ConfigData directly
        viewModel.$units
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
        let item = CPListItem(text: "Units", detailText: viewModel.units.rawValue)
        item.handler = { [weak self] _, completion in
            // Toggle units via the ViewModel (which persists to ConfigData)
            guard let self else {
                completion()
                return
            }
            let next = self.viewModel.units.next
            self.viewModel.units = next

            // Update the UI
            //self.refreshSection()
            completion()
        }
        return item
    }

    // Connection details item built from SettingsViewModel + manager for BT name
    private func makeConnectionDetailsItem() -> CPListItem {
        let type = viewModel.connectionType
        let typeText = type.rawValue

        // Build a concise detail string depending on connection type
        let detail: String
        switch type {
        case .demo:
            detail = "\(typeText) • no actual connection"
        case .wifi:
            let host = viewModel.wifiHost
            let port = viewModel.wifiPort
            detail = "\(typeText) • \(host):\(port)"
        case .bluetooth:
            let name = OBDConnectionManager.shared.connectedPeripheralName ?? "unknown"
            detail = "\(typeText) • \(name)"
        }
        
        return makeItem("Connection", detailText: detail)
    }

    // Connection status item from SettingsViewModel
    private func makeConnectionStatusItem() -> CPListItem {
        let state = viewModel.connectionState
        let detail: String
        switch state {
        case .disconnected:
            detail = "Disconnected"
        case .connecting:
            detail = "Connecting..."
        case .connected:
            detail = "Connected"
        case .failed(let error):
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
