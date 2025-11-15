/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
CarPlay template for Gauges
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import CarPlay
import Combine
import SwiftOBD2
import SwiftUI // For Color
import UIKit   // For UIImage

@MainActor
class CarPlayGaugesController: CarPlayBaseTemplateController {
    private let connectionManager: OBDConnectionManager
    private let viewModel: GaugesViewModel
    private var sensorItems: [CPInformationItem] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Detail screen controller (manages template and live updates)
    private var detailController: CarPlayGaugeDetailController?
    
    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
        // Construct the gauges view model on the MainActor
        self.viewModel = GaugesViewModel(connectionManager: connectionManager, pidStore: PIDStore.shared)
    }

    override func setInterfaceController(_ interfaceController: CPInterfaceController) {
        super.setInterfaceController(interfaceController)
        
        // Subscribe with throttling, and let the base class gate refreshes by tab visibility
        subscribeAndRefresh(viewModel.$tiles, throttleSeconds: 1.0)
    }

    /// Creates the root template for the Gauges tab.
    override func makeRootTemplate() -> CPListTemplate {
        let section = buildSections()
        let template = CPListTemplate(title: "Gauges", sections: section)
        template.tabTitle = "Gauges"
        template.tabImage = symbolImage(named: "gauge")

        self.currentTemplate = template
        return template
    }

    private func refreshSection() {
        guard let template = currentTemplate as? CPListTemplate else { return }
        let sections = buildSections()
        template.updateSections(sections)
    }

    //  Private Template Creation & Navigation

    private func makeItem(_ text: String, detailText: String?) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }
    
    private func buildSections() -> [CPListSection]  {
        let tiles = viewModel.tiles
        
        // No gauges → single info row
        if tiles.isEmpty {
            let item = makeItem("No Enabled Gauges", detailText: nil)
            let section = CPListSection(items: [item])
            return [section]
        }

        let rowElements: [CPListImageRowItemRowElement] = tiles.map { tile in
            let pid = tile.pid
            let measurement = tile.measurement
            let image = drawGaugeImage(for: pid, measurement: measurement, size: CPListImageRowItemElement.maximumImageSize)
            let subtitle = measurement.map { pid.formatted(measurement: $0, includeUnits: true) } ??  "— \(pid.displayUnits)"
            return CPListImageRowItemRowElement(image: image, title: pid.label, subtitle: subtitle)
        }

        let item = CPListImageRowItem(text: "", elements: rowElements, allowsMultipleLines: true)
        item.handler = { _, completion in completion() }

        item.listImageRowHandler = { [weak self] _, index, completion in
            guard let self = self else {
                completion()
                return
            }
            let tiles = self.viewModel.tiles
            guard index >= 0 && index < tiles.count else {
                completion()
                return
            }
            let tappedPID = tiles[index].pid
            self.presentSensorTemplate(for: tappedPID)
            completion()
        }

        return [CPListSection(items: [item])]
    }

    private func presentSensorTemplate(for pid: OBDPID) {
        // Releasing the old controller cancels its subscriptions automatically
        detailController = nil

        // Create a new self-contained detail controller (auto-subscribes in init)
        let controller = CarPlayGaugeDetailController(pid: pid, connectionManager: connectionManager)
        detailController = controller

        // Push its template
        interfaceController?.pushTemplate(controller.template, animated: false, completion: nil)
    }

    // Hook for base class visibility refresh
    override func performRefresh() {
        refreshSection()
    }

    //  Helpers
}
