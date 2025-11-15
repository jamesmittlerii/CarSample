/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
CarPlay template for Fuel/O2 sensor data
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import CarPlay
import UIKit
import SwiftOBD2
import Combine

@MainActor
class CarPlayFuelStatusController: CarPlayBaseTemplateController {
    private let viewModel: FuelStatusViewModel
    private var cancellables = Set<AnyCancellable>()
    private var previousFuelStatus: [StatusCodeMetadata?]?
    
    init(connectionManager: OBDConnectionManager) {
        // Use the shared FuelStatusViewModel logic
        self.viewModel = FuelStatusViewModel(connectionManager: connectionManager)
    }

    override func setInterfaceController(_ interfaceController: CPInterfaceController) {
        super.setInterfaceController(interfaceController)
        
        // Observe ViewModel changes to keep the UI in sync (only refresh if visible)
        subscribeAndRefresh(viewModel.$status)
    }
    
    // Ensure demand-driven streaming includes fuel status while this tab is visible
    override func registerVisiblePIDs() {
        PIDInterestRegistry.shared.replace(pids: [.mode1(.fuelStatus)], for: controllerToken)
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

    override func makeRootTemplate() -> CPInformationTemplate {
        let items = buildInformationItems()
        let template = CPInformationTemplate(title: "Fuel Control Status", layout: .leading, items: items, actions: [])
        template.tabTitle = "FC"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        currentTemplate = template
        // Initialize previous snapshot to match what we just rendered
        previousFuelStatus = viewModel.status
        return template
    }
    
    // Unified refresh method name
    private func refreshSection() {
        guard let template = currentTemplate as? CPInformationTemplate else { return }
        
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

    // Hook for base class visibility refresh
    override func performRefresh() {
        refreshSection()
    }

    //  Helpers
}
