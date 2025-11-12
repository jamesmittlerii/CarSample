import CarPlay
import Combine
import SwiftOBD2
import SwiftUI // For Color
import UIKit   // For UIImage

/// Draws a gauge-style ring image for a given PID value.
/// This function is scoped to this file as it's only used for the gauges UI.
fileprivate func drawGaugeImage(for pid: OBDPID, measurement: MeasurementResult?, size: CGSize = CPListImageRowItemElement.maximumImageSize) -> UIImage {
    // Helper: map Foundation.Unit to our MeasurementUnit for range conversion/color thresholds
    func measurementUnit(from unit: Unit) -> MeasurementUnit {
        switch unit {
        case is UnitTemperature:
            return unit == UnitTemperature.fahrenheit ? .imperial : .metric
        case is UnitSpeed:
            return unit == UnitSpeed.milesPerHour ? .imperial : .metric
        case is UnitPressure:
            if unit == UnitPressure.poundsForcePerSquareInch { return .imperial }
            return .metric
        case is UnitLength:
            return unit == UnitLength.miles ? .imperial : .metric
        default:
            // For units without a metric/imperial distinction, assume metric canonical
            return .metric
        }
    }

    // Build a combined range in the PID's canonical (metric) units first
    let metricRanges: [ValueRange] = [pid.typicalRange, pid.warningRange, pid.dangerRange].compactMap { $0 }
    // Fallback typical (should exist for gauges, but guard anyway)
    let fallbackTypical = pid.typicalRange ?? ValueRange(min: 0, max: 1)
    let metricMin = metricRanges.map(\.min).min() ?? fallbackTypical.min
    let metricMax = metricRanges.map(\.max).max() ?? fallbackTypical.max
    var combinedRange = ValueRange(min: metricMin, max: metricMax)

    // If we have a measurement, convert the combined range to the measurement’s unit system when appropriate
    var colorUnitSystem: MeasurementUnit = ConfigData.shared.units
    if let m = measurement {
        let sys = measurementUnit(from: m.unit)
        colorUnitSystem = sys
        if let baseUnits = pid.units {
            combinedRange = combinedRange.converted(from: baseUnits, to: sys)
        }
    }

    let value = measurement?.value

    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    return renderer.image { ctx in
        let rect = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Make it a ring that fits within the smallest dimension
        let lineWidth: CGFloat = max(4, min(size.width, size.height) * 0.25)
        let radius = (min(size.width, size.height) - lineWidth) / 2.0

        // Angles for a speedometer-style gauge (from 8 o'clock to 4 o'clock)
        let startAngle: CGFloat = (5.0 / 6.0) * .pi
        let sweepAngle: CGFloat = (4.0 / 3.0) * .pi
        let endAngle: CGFloat = startAngle + sweepAngle

        // Background track (always drawn)
        let trackPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        trackPath.lineWidth = lineWidth
        trackPath.lineCapStyle = .round
        UIColor.systemGray3.setStroke()
        trackPath.stroke()

        // If we don't have a value yet, stop here (draw only background track)
        guard let actualValue = value else {
            return
        }

        // Normalize/clamp the progress against the combined range (now aligned with the measurement’s unit system if present)
        let clampedNormalized = max(0.0, min(1.0, combinedRange.normalizedPosition(for: actualValue)))

        // Determine color for the current value using the same unit system as the measurement (or app default)
        let uiColor = UIColor(pid.color(for: actualValue, unit: colorUnitSystem))

        // Progress arc
        let progressEndAngle = startAngle + (sweepAngle * CGFloat(clampedNormalized))
        let progressPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: progressEndAngle, clockwise: true)
        progressPath.lineCapStyle = .round
        progressPath.lineWidth = lineWidth
        uiColor.setStroke()
        progressPath.stroke()
    }
}

@MainActor
class CarPlayGaugesController {
    private weak var interfaceController: CPInterfaceController?
    private let connectionManager: OBDConnectionManager
    private var currentTemplate: CPListTemplate?
    private var sensorItems: [CPInformationItem] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Detail screen live update state
    private var currentDetailPID: OBDPID?
    private var currentInfoTemplate: CPInformationTemplate?
    private var currentDetailCancellable: AnyCancellable?
    
    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        // Subscribe to PID stats updates and notify the gauges controller to refresh
        connectionManager.$pidStats
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)
        
        // NEW: Refresh gauges when the enabled PID set changes (e.g., toggled in Settings)
        PIDStore.shared.$pids
            .map { pids in pids.filter { $0.enabled }.map { $0.id } }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)
    }

    /// Creates the root template for the Gauges tab.
    func makeRootTemplate() -> CPListTemplate {
        let section = buildSections()
        let template = CPListTemplate(title: "Gauges", sections: section)
        template.tabTitle = "Gauges"
        template.tabImage = symbolImage(named: "gauge")

        self.currentTemplate = template
        return template
    }

    private func refreshSection() {
        guard let template = currentTemplate else { return }
        let sections = buildSections()
        template.updateSections(sections)
    }

    // MARK: - Private Template Creation & Navigation

    private func makeItem(_ text: String, detailText: String?) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }
    
    private func buildSections() -> [CPListSection]  {
        // Use the live enabled PID list from the store so toggles reflect here
        let sensors = PIDStore.shared.enabledGauges
        
        // No gauges → single info row
        if sensors.isEmpty {
            let item = makeItem("No Enabled Gauges", detailText: nil)
            let section = CPListSection(items: [item])
            return [section]
        }

        func currentMeasurement(for pid: OBDPID) -> MeasurementResult? {
            return connectionManager.stats(for: pid.pid)?.latest
        }

        let rowElements: [CPListImageRowItemRowElement] = sensors.map { pid in
            let measurement = currentMeasurement(for: pid)
            let image = drawGaugeImage(for: pid, measurement: measurement)
            let subtitle = measurement.map { pid.formatted(measurement: $0, includeUnits: true) } ?? "— \(pid.units!)"
            return CPListImageRowItemRowElement(image: image, title: pid.label, subtitle: subtitle)
        }

        let item = CPListImageRowItem(text: "", elements: rowElements, allowsMultipleLines: true)
        item.handler = { _, completion in completion() }

        item.listImageRowHandler = { [weak self] _, index, completion in
            guard let self = self, index >= 0 && index < sensors.count else {
                completion()
                return
            }
            let tappedPID = sensors[index]
            self.presentSensorTemplate(for: tappedPID)
            completion()
        }

        return [CPListSection(items: [item])]
    }

    private func updateSensorItems(for pid: OBDPID)  {
        var items: [CPInformationItem] = []
        let stats = connectionManager.stats(for: pid.pid)

        // Current
        if let s = stats {
            let currentStr = pid.formatted(measurement: s.latest, includeUnits: true)
            items.append(CPInformationItem(title: "Current", detail: currentStr))
        } else {
            items.append(CPInformationItem(title: "Current", detail: "— \(pid.units!)"))
        }

        // Min/Max/Samples when stats are available
        if let s = stats {
            let minStr = pid.formatted(measurement: MeasurementResult(value: s.min, unit: s.latest.unit), includeUnits: true)
            let maxStr = pid.formatted(measurement: MeasurementResult(value: s.max, unit: s.latest.unit), includeUnits: true)
            items.append(CPInformationItem(title: "Min", detail: minStr))
            items.append(CPInformationItem(title: "Max", detail: maxStr))
            items.append(CPInformationItem(title: "Samples", detail: "\(s.sampleCount)"))
        }

       // Typical Range using the new displayRange helper
        items.append(CPInformationItem(title: "Typical Range", detail: pid.displayRange))

        sensorItems = items
    }
    
    private func presentSensorTemplate(for pid: OBDPID) {
        // Cancel any previous detail subscription
        currentDetailCancellable?.cancel()
        currentDetailCancellable = nil
        currentDetailPID = pid
        currentInfoTemplate = nil
        
        updateSensorItems(for: pid)
        let template = CPInformationTemplate(title: pid.name  , layout: .twoColumn, items: sensorItems, actions: [])
        currentInfoTemplate = template

        interfaceController?.pushTemplate(template, animated: false, completion: nil)
        
        // Live updates for this PID: update items in place
        currentDetailCancellable = connectionManager.$pidStats
            .compactMap { statsDict -> OBDConnectionManager.PIDStats? in
                statsDict[pid.pid]
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self,
                      let infoTemplate = self.currentInfoTemplate,
                      let currentPID = self.currentDetailPID
                else { return }
                
                // Rebuild items and assign to the template
                self.updateSensorItems(for: currentPID)
                infoTemplate.items = self.sensorItems
            }
    }

    // MARK: - Helpers

    private func symbolImage(named name: String) -> UIImage? {
        return UIImage(systemName: name)
    }
}
