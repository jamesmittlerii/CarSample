import SwiftUI
import SwiftOBD2

struct RingGaugeView: View {
    let pid: OBDPID
    let measurement: MeasurementResult?

    // Visual constants to match GaugeDrawing.swift
    private let startAngle: Angle = .radians((5.0 / 6.0) * .pi)          // ~8 o’clock
    private let sweepAngle: Angle = .radians((4.0 / 3.0) * .pi)           // ~240°
    private var endAngle: Angle { Angle(radians: startAngle.radians + sweepAngle.radians) }

    private let lineWidthRatio: CGFloat = 0.25 // relative to min dimension
    private let tickCount: Int = 21            // every 5% across the span
    private let tickLengthRatio: CGFloat = 0.10
    private let tickThickness: CGFloat = 2

    // Derived unit system to color/convert ranges (mirrors GaugeDrawing.swift)
    private var colorUnitSystem: MeasurementUnit {
        if let m = measurement {
            return measurementUnit(from: m.unit)
        }
        return ConfigData.shared.units
    }

    // Combined range in the chosen unit system
    private var combinedRange: ValueRange {
        // Start with metric canonical
        let metricRanges: [ValueRange] = [pid.typicalRange, pid.warningRange, pid.dangerRange].compactMap { $0 }
        let fallbackTypical = pid.typicalRange ?? ValueRange(min: 0, max: 1)
        let metricMin = metricRanges.map(\.min).min() ?? fallbackTypical.min
        let metricMax = metricRanges.map(\.max).max() ?? fallbackTypical.max
        var combined = ValueRange(min: metricMin, max: metricMax)

        // If measurement exists, align to its unit system using PID.units label conversion
        if let baseUnits = pid.units, let _ = measurement {
            combined = combined.converted(from: baseUnits, to: colorUnitSystem)
        }
        return combined
    }

    // Background bands converted to chosen unit system
    private var typicalBand: ValueRange? { pid.typicalRange(for: colorUnitSystem) }
    private var warnBand: ValueRange? { pid.warningRange(for: colorUnitSystem) }
    private var dangerBand: ValueRange? { pid.dangerRange(for: colorUnitSystem) }

    // Current value and display
    private var value: Double? { measurement?.value }
    private var displayText: String {
        if let m = measurement {
            return pid.formatted(measurement: m, includeUnits: true)
        } else {
            return "— \(pid.displayUnits(for: colorUnitSystem))"
        }
    }

    // Unified splitter
    private enum SplitPart { case first, second }

    private func splitDisplayText(_ part: SplitPart) -> String {
        let s = displayText
        guard let idx = s.firstIndex(of: " ") else {
            // No space: treat whole string as first part
            if part == .first {
                // Try to strip grouping if it's a number
                let nf = NumberFormatter()
                nf.numberStyle = .decimal
                if let number = nf.number(from: s) {
                    let out = NumberFormatter()
                    out.numberStyle = .decimal
                    out.usesGroupingSeparator = false
                    // Preserve any decimals present by inferring fraction digits from input formatter
                    out.minimumFractionDigits = nf.minimumFractionDigits
                    out.maximumFractionDigits = nf.maximumFractionDigits
                    return out.string(from: number) ?? s
                }
                return s
            } else {
                return ""
            }
        }

        switch part {
        case .first:
            let firstPart = String(s[..<idx])

            // If firstPart is a number, remove grouping separators
            let nf = NumberFormatter()
            nf.numberStyle = .decimal
            if let number = nf.number(from: firstPart) {
                let out = NumberFormatter()
                out.numberStyle = .decimal
                out.usesGroupingSeparator = false
                // Keep a reasonable fraction digit policy: infer from input token
                out.minimumFractionDigits = nf.minimumFractionDigits
                out.maximumFractionDigits = nf.maximumFractionDigits
                return out.string(from: number) ?? firstPart
            }
            return firstPart

        case .second:
            return String(s[s.index(after: idx)...])
        }
    }
    private var displayFirstLine: String { splitDisplayText(.first) }
    private var displaySecondLine: String { splitDisplayText(.second) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dim = min(size.width, size.height)
            let lineWidth = max(4, dim * lineWidthRatio)
            //let radius = (dim - lineWidth) / 2.0

            ZStack {
                // Base track
                ArcShape(start: startAngle, end: endAngle)
                    .inset(by: lineWidth / 2)
                    .stroke(Color(UIColor.systemGray3), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Background bands (typical/warn/danger)
                //band(typicalBand, color: .green, lineWidth: lineWidth)
                //band(warnBand, color: .yellow, lineWidth: lineWidth)
                //band(dangerBand, color: .red, lineWidth: lineWidth)

                // Ticks
                //ticks(count: tickCount, radius: radius, lineWidth: lineWidth, color: Color(UIColor.systemGray))

                // Progress arc
                if let v = value {
                    let normalized = combinedRange.normalizedPosition(for: v).clamped01
                    let progressEnd = Angle(radians: startAngle.radians + sweepAngle.radians * normalized)
                    ArcShape(start: startAngle, end: progressEnd)
                        .inset(by: lineWidth / 2)
                        .stroke(progressColor(for: v), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .animation(.easeInOut(duration: 0.35), value: v)
                }

                // Center readout
                VStack(spacing: 4) {
                    Text(displayFirstLine)
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(displaySecondLine)
                        .font(.subheadline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    
                }
                .padding(0)
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityLabel(pid.name)
        .accessibilityValue(displayText)
    }

    // MARK: - Helpers

    private func measurementUnit(from unit: Unit) -> MeasurementUnit {
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

    private func angle(for value: Double, in range: ValueRange) -> Angle {
        let n = range.normalizedPosition(for: value).clamped01
        return Angle(radians: startAngle.radians + sweepAngle.radians * n)
    }

    private func band(_ range: ValueRange?, color: Color, lineWidth: CGFloat) -> some View {
        guard let r = range else { return AnyView(EmptyView()) }
        let start = angle(for: r.min, in: combinedRange)
        let end = angle(for: r.max, in: combinedRange)
        return AnyView(
            ArcShape(start: start, end: end)
                .inset(by: lineWidth / 2)
                .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        )
    }

    private func ticks(count: Int, radius: CGFloat, lineWidth: CGFloat, color: Color) -> some View {
        let inner = radius
        let outer = radius - radius * tickLengthRatio
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let t = Double(i) / Double(max(1, count - 1))
                let angle = Angle(radians: startAngle.radians + sweepAngle.radians * t)
                TickShape(angle: angle, innerRadius: inner, outerRadius: outer)
                    .stroke(color.opacity(i % 5 == 0 ? 0.8 : 0.5), lineWidth: tickThickness)
            }
        }
    }

    private func progressColor(for value: Double) -> Color {
        pid.color(for: value, unit: colorUnitSystem)
    }
}

// MARK: - Shapes

private struct ArcShape: InsettableShape {
    var start: Angle
    var end: Angle
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.width, rect.height) / 2.0 - insetAmount)

        var p = Path()
        p.addArc(center: center,
                 radius: radius,
                 startAngle: start,
                 endAngle: end,
                 clockwise: false)
        return p
    }

    func inset(by amount: CGFloat) -> ArcShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct TickShape: Shape {
    let angle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let a = CGFloat(angle.radians)
        let sinA = sin(a)
        let cosA = cos(a)

        let p1 = CGPoint(x: center.x + innerRadius * cosA, y: center.y + innerRadius * sinA)
        let p2 = CGPoint(x: center.x + outerRadius * cosA, y: center.y + outerRadius * sinA)

        var p = Path()
        p.move(to: p1)
        p.addLine(to: p2)
        return p
    }
}

// MARK: - Utilities

private extension Double {
    var clamped01: Double { max(0.0, min(1.0, self)) }
}

#Preview("With Value") {
    let pid = OBDPIDLibrary.standard.first { $0.label == "RPM" }!
    // Example RPM value using your custom Unit.rpm
    let measurement = MeasurementResult(value: 2500, unit: Unit(symbol: "rpm"))
    RingGaugeView(pid: pid, measurement: measurement)
        .frame(width: 200, height: 200)
        .padding()
}

#Preview("No Value") {
    let pid = OBDPIDLibrary.standard.first { $0.label == "Coolant" }!
     RingGaugeView(pid: pid, measurement: nil)
        .frame(width: 200, height: 200)
        .padding()
}
