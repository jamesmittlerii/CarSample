import CarPlay
import UIKit
import SwiftOBD2
import Combine

@MainActor
class CarPlayMILStatusController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPListTemplate?
    private let viewModel: MILStatusViewModel
    private var cancellables = Set<AnyCancellable>()
    private var previousMILStatus: Status?
    
    init(connectionManager: OBDConnectionManager) {
        // Use the shared ViewModel logic for MIL status
        self.viewModel = MILStatusViewModel(connectionManager: connectionManager)
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        // Observe ViewModel changes to keep the UI in sync
        viewModel.$status
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
        guard let status = viewModel.status else {
            let item = makeItem("No MIL Status", detailText: "")
            let section = CPListSection(items: [item])
            return [section]
        }

        var items: [CPListItem] = []

        // Top-level flags/values
        let dtcLabel = "\(status.dtcCount) DTC" + (status.dtcCount == 1 ? "" : "s")
        let milLabel = status.milOn ? "On" : "Off"
        items.append(makeItem("MIL", detailText: "\(milLabel) (\(dtcLabel))"))
        
        // Readiness monitors: use the same sorting/grouping logic as the SwiftUI ViewModel
        for monitor in viewModel.sortedSupportedMonitors {
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
        
        let current = viewModel.status
        
        // Early exit if nothing changed
        if let previous = previousMILStatus, previous == current {
            return
        }
        
        // Update UI and remember last shown state
        let sections = buildSections()
        previousMILStatus = current
        template.updateSections(sections)
    }

    /// Creates the root template for the MIL tab.
    func makeRootTemplate() -> CPListTemplate {
        let sections = buildSections()
        let template = CPListTemplate(title: "MILStatus", sections: sections)
        template.tabTitle = "MIL"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        self.currentTemplate = template
        
        // Initialize previous snapshot to match what we just rendered
        previousMILStatus = viewModel.status
        
        return template
    }
    
    // MARK: - Helpers
}
