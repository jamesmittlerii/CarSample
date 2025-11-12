import UIKit
import SwiftUI
import SwiftOBD2

// Shared gauge ring renderer usable from SwiftUI (Image(uiImage:)) and CarPlay (UIImage)
func drawGaugeImage(for pid: OBDPID, measurement: MeasurementResult?, size: CGSize) -> UIImage {
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
            return .metric
        }
    }

    // Build a combined range in the PID's canonical (metric) units first
    let metricRanges: [ValueRange] = [pid.typicalRange, pid.warningRange, pid.dangerRange].compactMap { $0 }
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

    return renderer.image { _ in
        let rect = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Ring sizing
        let lineWidth: CGFloat = max(4, min(size.width, size.height) * 0.25)
        let radius = (min(size.width, size.height) - lineWidth) / 2.0

        // Angles for a speedometer-style gauge (from ~8 o'clock to ~4 o'clock)
        let startAngle: CGFloat = (5.0 / 6.0) * .pi
        let sweepAngle: CGFloat = (4.0 / 3.0) * .pi
        let endAngle: CGFloat = startAngle + sweepAngle

        // Background track
        let trackPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        trackPath.lineWidth = lineWidth
        trackPath.lineCapStyle = .round
        UIColor.systemGray3.setStroke()
        trackPath.stroke()

        // If no value yet, stop here
        guard let actualValue = value else { return }

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
