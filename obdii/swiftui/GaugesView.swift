import SwiftUI
import Combine
import SwiftOBD2
import UIKit

// Copy of the ring renderer so we can use it in SwiftUI without changing access in CarPlay file.
fileprivate func drawGaugeImage(for pid: OBDPID, measurement: MeasurementResult?, size: CGSize = CGSize(width: 120, height: 120)) -> UIImage {
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

    let metricRanges: [ValueRange] = [pid.typicalRange, pid.warningRange, pid.dangerRange].compactMap { $0 }
    let fallbackTypical = pid.typicalRange ?? ValueRange(min: 0, max: 1)
    let metricMin = metricRanges.map(\.min).min() ?? fallbackTypical.min
    let metricMax = metricRanges.map(\.max).max() ?? fallbackTypical.max
    var combinedRange = ValueRange(min: metricMin, max: metricMax)

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

        let lineWidth: CGFloat = max(4, min(size.width, size.height) * 0.25)
        let radius = (min(size.width, size.height) - lineWidth) / 2.0

        let startAngle: CGFloat = (5.0 / 6.0) * .pi
        let sweepAngle: CGFloat = (4.0 / 3.0) * .pi
        let endAngle: CGFloat = startAngle + sweepAngle

        let trackPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        trackPath.lineWidth = lineWidth
        trackPath.lineCapStyle = .round
        UIColor.systemGray3.setStroke()
        trackPath.stroke()

        guard let actualValue = value else {
            return
        }

        let clampedNormalized = max(0.0, min(1.0, combinedRange.normalizedPosition(for: actualValue)))
        let uiColor = UIColor(pid.color(for: actualValue, unit: colorUnitSystem))

        let progressEndAngle = startAngle + (sweepAngle * CGFloat(clampedNormalized))
        let progressPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: progressEndAngle, clockwise: true)
        progressPath.lineCapStyle = .round
        progressPath.lineWidth = lineWidth
        uiColor.setStroke()
        progressPath.stroke()
    }
}

struct GaugesView: View {
    @StateObject private var connectionManager = OBDConnectionManager.shared
    @StateObject private var pidStore = PIDStore.shared

    // Adaptive grid: 2–4 columns depending on width
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(pidStore.enabledGauges, id: \.id) { pid in
                        NavigationLink {
                            GaugeDetailView(pid: pid, connectionManager: connectionManager)
                        } label: {
                            GaugeTile(pid: pid, manager: connectionManager)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("GaugeTile_\(pid.id.uuidString)")
                    }
                }
                .padding()
            }
            .navigationTitle("Gauges")
        }
    }
}

private struct GaugeTile: View {
    let pid: OBDPID
    @ObservedObject var manager: OBDConnectionManager

    private var measurement: MeasurementResult? {
        manager.stats(for: pid.pid)?.latest
    }

    var body: some View {
        VStack(spacing: 8) {
            // Gauge image
            let img = drawGaugeImage(for: pid, measurement: measurement, size: CGSize(width: 120, height: 120))
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)

            // Title
            Text(pid.label)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Subtitle: current formatted or placeholder with units
            Text(subtitleText())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func subtitleText() -> String {
        if let m = measurement {
            return pid.formatted(measurement: m, includeUnits: true)
        } else {
            return "— \(pid.displayUnits)"
        }
    }
}

#Preview {
    GaugesView()
}
