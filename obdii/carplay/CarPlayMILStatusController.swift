/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
CarPlay template for MIL status (CEL)
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */


import CarPlay
import UIKit
import SwiftOBD2
import Combine

@MainActor
class CarPlayMILStatusController: CarPlayBaseTemplateController {
    private let viewModel: MILStatusViewModel
    private var cancellables = Set<AnyCancellable>()
    
    init(connectionManager: OBDConnectionManager) {
        // Use the shared ViewModel logic for MIL status
        self.viewModel = MILStatusViewModel(connectionManager: connectionManager)
    }

    override func setInterfaceController(_ interfaceController: CPInterfaceController) {
        super.setInterfaceController(interfaceController)
        
        // Observe ViewModel changes to keep the UI in sync
        // only refresh if visible
        
        subscribeAndRefresh(viewModel.$status)
       
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
        guard let template = currentTemplate as? CPListTemplate else { return }
        let sections = buildSections()
        template.updateSections(sections)
    }
    
    // Ensure demand-driven streaming includes fuel status while this tab is visible
    override func registerVisiblePIDs() {
        PIDInterestRegistry.shared.replace(pids: [.mode1(.status)], for: controllerToken)
    }

    /// Creates the root template for the MIL tab.
    override func makeRootTemplate() -> CPListTemplate {
        let sections = buildSections()
        let template = CPListTemplate(title: "MILStatus", sections: sections)
        template.tabTitle = "MIL"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        self.currentTemplate = template
        return template
    }
    
    // Hook for base class visibility refresh
    override func performRefresh() {
        refreshSection()
    }

    //  Helpers
}

