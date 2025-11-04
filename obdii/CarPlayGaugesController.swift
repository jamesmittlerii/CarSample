import CarPlay
import Combine
import SwiftOBD2
import SwiftUI // For Color
import UIKit   // For UIImage

/// Draws a gauge-style ring image for a given PID value.
/// This function is scoped to this file as it's only used for the gauges UI.
fileprivate func drawGaugeImage(for pid: OBDPID, value: Double?, size: CGSize = CPListImageRowItemElement.maximumImageSize) -> UIImage {
    // Use provided value or fall back to the minimum of the typical range
    let actualValue = value ?? pid.typicalRange.min

    // Normalize value to 0...1 within the typical range
    let clampedNormalized = max(0.0, min(1.0, pid.typicalRange.normalizedPosition(for: actualValue)))

    // Determine color for the current value and convert to UIColor
    let uiColor = UIColor(pid.color(for: actualValue))

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

        // Background track
        let trackPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        trackPath.lineWidth = lineWidth
        trackPath.lineCapStyle = .round
        UIColor.systemGray3.setStroke()
        trackPath.stroke()

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
    private var sensorsListTemplate: CPListTemplate?

    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    /// Creates the root template for the Gauges tab.
    func makeRootTemplate() -> CPListTemplate {
        let section = makeGaugesSection()
        let template = CPListTemplate(title: "Gauges", sections: [section])
        template.tabTitle = "Gauges"
        template.tabImage = symbolImage(named: "gauge")

        self.sensorsListTemplate = template
        return template
    }

    /// Refreshes the gauges template with the latest data.
    func refresh() {
        guard let currentTemplate = sensorsListTemplate else { return }
        let updatedSection = makeGaugesSection()
        currentTemplate.updateSections([updatedSection])
    }
    
    // MARK: - Private Template Creation & Navigation

    private func makeGaugesSection() -> CPListSection {
        let sensors = OBDPIDLibrary.standard

        func currentValue(for pid: OBDPID) -> Double? {
            return connectionManager.stats(for: pid.pid)?.latest.value
        }

        let rowElements: [CPListImageRowItemRowElement] = sensors.map { pid in
            let image = drawGaugeImage(for: pid, value: currentValue(for: pid))
            let subtitle = (currentValue(for: pid).map { String(format: "%.1f %@", $0, pid.units) }) ?? "— \(pid.units)"
            return CPListImageRowItemRowElement(image: image, title: pid.name, subtitle: subtitle)
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

        return CPListSection(items: [item])
    }

    private func presentSensorTemplate(for pid: OBDPID) {
        let stats = connectionManager.stats(for: pid.pid)
        var items: [CPInformationItem] = []

        items.append(CPInformationItem(title: "Current", detail: (stats.map { String(format: "%.2f %@", $0.latest.value, pid.units) }) ?? "— \(pid.units)"))
        if let stats = stats {
            items.append(CPInformationItem(title: "Min", detail: String(format: "%.2f %@", stats.min, pid.units)))
            items.append(CPInformationItem(title: "Max", detail: String(format: "%.2f %@", stats.max, pid.units)))
            items.append(CPInformationItem(title: "Samples", detail: "\(stats.sampleCount)"))
        }

        items.append(CPInformationItem(title: "Units", detail: pid.units))
        items.append(CPInformationItem(title: "Typical Range", detail: String(format: "%.1f – %.1f %@", pid.typicalRange.min, pid.typicalRange.max, pid.units)))

        let template = CPInformationTemplate(title: pid.name, layout: .twoColumn, items: items, actions: [])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
}
