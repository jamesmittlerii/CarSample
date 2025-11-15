/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
CarPlay template for PID details
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import Foundation
import CarPlay
import Combine
import SwiftOBD2

@MainActor
final class CarPlayGaugeDetailController {
    private let viewModel: GaugeDetailViewModel

    private(set) var template: CPInformationTemplate
    private var cancellables = Set<AnyCancellable>()

    init(pid: OBDPID, connectionManager: OBDConnectionManager) {
        // Reuse the existing GaugeDetailViewModel for data and formatting
        self.viewModel = GaugeDetailViewModel(pid: pid, connectionManager: connectionManager)

        // Build initial items and template
        let items = CarPlayGaugeDetailController.buildItems(for: viewModel.pid, stats: viewModel.stats)
        self.template = CPInformationTemplate(title: viewModel.pid.name, layout: .twoColumn, items: items, actions: [])

        // Subscribe to live updates from the view model
        
        viewModel.$stats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let items = CarPlayGaugeDetailController.buildItems(for: self.viewModel.pid, stats: self.viewModel.stats)
                self.template.items = items
            }
            .store(in: &cancellables)
    }

    private static func buildItems(for pid: OBDPID, stats: OBDConnectionManager.PIDStats?) -> [CPInformationItem] {
        var items: [CPInformationItem] = []

        if let s = stats {
            let currentStr = pid.formatted(measurement: s.latest, includeUnits: true)
            items.append(CPInformationItem(title: "Current", detail: currentStr))
        } else {
            items.append(CPInformationItem(title: "Current", detail: "— \(pid.displayUnits)"))
        }

        if let s = stats {
            let minStr = pid.formatted(measurement: MeasurementResult(value: s.min, unit: s.latest.unit), includeUnits: true)
            let maxStr = pid.formatted(measurement: MeasurementResult(value: s.max, unit: s.latest.unit), includeUnits: true)
            items.append(CPInformationItem(title: "Min", detail: minStr))
            items.append(CPInformationItem(title: "Max", detail: maxStr))
            items.append(CPInformationItem(title: "Samples", detail: "\(s.sampleCount)"))
        }

        items.append(CPInformationItem(title: "Typical Range", detail: pid.displayRange))

        return items
    }
}
