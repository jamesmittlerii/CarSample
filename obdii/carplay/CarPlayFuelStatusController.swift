import CarPlay
import UIKit
import SwiftOBD2
import Combine

@MainActor
class CarPlayFuelStatusController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPInformationTemplate?
    private let viewModel: FuelStatusViewModel
    private var cancellables = Set<AnyCancellable>()
    private var previousFuelStatus: [StatusCodeMetadata?]?
    
    init(connectionManager: OBDConnectionManager) {
        // Use the shared FuelStatusViewModel logic
        self.viewModel = FuelStatusViewModel(connectionManager: connectionManager)
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        // Observe ViewModel changes to keep the UI in sync
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshTemplate()
            }
            .store(in: &cancellables)
    }
    
    private func makeItem(_ text: String, detailText: String) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }
    
    private func buildInformationItems() -> [CPInformationItem] {
        var items: [CPInformationItem] = []
        
        if let b1 = viewModel.bank1 {
            let item = CPInformationItem(
                title: "Bank 1",
                detail: b1.description
            )
            items.append(item)
        }
        if let b2 = viewModel.bank2 {
            let item = CPInformationItem(
                title: "Bank 2",
                detail: b2.description
            )
            items.append(item)
        }
        if items.isEmpty {
            items.append(CPInformationItem(title: "No Fuel System Status Codes", detail: ""))
        }
        return items
    }

    func makeRootTemplate() -> CPInformationTemplate {
        let items = buildInformationItems()
        let template = CPInformationTemplate(title: "Fuel Control Status", layout: .leading, items: items, actions: [])
        template.tabTitle = "FC"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        currentTemplate = template
        // Initialize previous snapshot to match what we just rendered
        previousFuelStatus = viewModel.status
        return template
    }
    
    private func refreshTemplate() {
        guard let template = currentTemplate else { return }
        
        let current = viewModel.status
        
        // Early exit if nothing changed
        if let previous = previousFuelStatus, previous == current {
            return
        }
        
        // Update UI and remember last shown state
        let items = buildInformationItems()
        previousFuelStatus = current
        template.items = items
    }

    // MARK: - Helpers
}
