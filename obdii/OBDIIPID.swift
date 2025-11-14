import Foundation
import SwiftOBD2
import SwiftUI

// MARK: - ValueRange

/// Represents a numeric range for a PID value (for scaling, warnings, etc.)
struct ValueRange: Hashable, Codable {
    let min: Double
    let max: Double

    // MARK: - Initializer
    init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    // MARK: - Helpers

    /// Checks if a value is within the range (inclusive)
    func contains(_ value: Double) -> Bool {
        value >= min && value <= max
    }

    /// Returns a clamped value between min and max
    func clampedValue(for value: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    /// Checks if this range overlaps another
    func overlaps(_ other: ValueRange) -> Bool {
        return !(other.max < min || other.min > max)
    }

    /// Returns a normalized 0–1 position within the range
    func normalizedPosition(for value: Double) -> Double {
        guard max != min else { return 0.0 }
        return (value - min) / (max - min)
    }

    /// Convert a metric range to the requested MeasurementUnit for a given unit label.
    /// Only the following conversions are applied:
    /// - Temperature: "°C" <-> "°F"
    /// - Speed: "km/h" <-> "mph"
    /// - Pressure: "kPa" <-> "psi"
    /// - Length: "km" <-> "mi"
    /// All others are returned unchanged.
    func converted(from unitLabel: String, to measurementUnit: MeasurementUnit) -> ValueRange {
        guard let conversion = UnitConversion.fromMetricUnitLabel(unitLabel, to: measurementUnit) else {
            return self
        }
        let newMin = conversion.convert(self.min)
        let newMax = conversion.convert(self.max)
        return ValueRange(min: newMin, max: newMax)
    }
}

// MARK: - UnitConversion helper

/// Encapsulates a label mapping and a numeric conversion closure for supported units.
/// We treat stored OBDPID units/ranges as METRIC canonical and convert for presentation.
private struct UnitConversion {
    let displayLabel: String
    let convert: (Double) -> Double

    /// Produce a conversion based on a stored metric label and the requested MeasurementUnit.
    /// Returns nil if no conversion is needed/supported.
    static func fromMetricUnitLabel(_ label: String, to unit: MeasurementUnit) -> UnitConversion? {
        switch label {
        case "°C":
            if unit == .imperial {
                return UnitConversion(displayLabel: "°F") { c in (c * 9.0 / 5.0) + 32.0 }
            } else {
                return UnitConversion(displayLabel: "°C") { $0 }
            }
        case "km/h":
            if unit == .imperial {
                return UnitConversion(displayLabel: "mph") { kmh in kmh * 0.621371 }
            } else {
                return UnitConversion(displayLabel: "km/h") { $0 }
            }
        case "kPa":
            if unit == .imperial {
                return UnitConversion(displayLabel: "psi") { kpa in kpa * 0.145038 }
            } else {
                return UnitConversion(displayLabel: "kPa") { $0 }
            }
        case "km":
            if unit == .imperial {
                return UnitConversion(displayLabel: "mi") { km in km * 0.621371 }
            } else {
                return UnitConversion(displayLabel: "km") { $0 }
            }
        case "g/s":
            if unit == .imperial {
                return UnitConversion(displayLabel: "lb/min") { gs in gs * 0.132277}
            } else {
                return UnitConversion(displayLabel: "g/s") { $0 }
            }
        case "L/h":
            if unit == .imperial {
                return UnitConversion(displayLabel: "gal/h") { l in l * 0.264172}
            } else {
                return UnitConversion(displayLabel: "L/h") { $0 }
            }

        // Units we do not convert here (leave as-is)
        case "RPM", "%", "V", "λ", "NA", "Pa", "mA", "° BTDC", "s", "count":
            return UnitConversion(displayLabel: label) { $0 }

        default:
            // Unknown label → no conversion
            return nil
        }
    }
}

// MARK: - OBDPID

/// Represents a single OBD-II Parameter ID (PID) definition.
struct OBDPID: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, Hashable {
        case gauge
        case status
    }

    let id: UUID
    var enabled: Bool
    let label: String          // Short name for compact UI
    let name: String      // Full/original descriptive name
    let pid: OBDCommand
    let formula: String?
    let units: String?
    let typicalRange: ValueRange?
    let warningRange: ValueRange?
    let dangerRange: ValueRange?
    let notes: String?
    let kind: Kind

    init(
        id: UUID = UUID(),
        enabled: Bool = false,
        label: String,
        name: String? = nil,
        pid: OBDCommand,
        formula: String? = nil,
        units: String,
        typicalRange: ValueRange,
        warningRange: ValueRange? = nil,
        dangerRange: ValueRange? = nil,
        notes: String? = nil,
        kind: Kind = .gauge
    ) {
        self.id = id
        self.label = label
        self.name = name ?? label
        self.pid = pid
        self.formula = formula
        self.units = units
        self.typicalRange = typicalRange
        self.warningRange = warningRange
        self.dangerRange = dangerRange
        self.notes = notes
        self.enabled = enabled
        self.kind = kind
    }

    // MARK: - Unit-aware presentation helpers (based on MeasurementUnit)

    /// Unit label adjusted for the requested measurement system.
    func unitLabel(for measurementUnit: MeasurementUnit) -> String {
        let base = units ?? ""
        guard let conversion = UnitConversion.fromMetricUnitLabel(base, to: measurementUnit) else {
            return base
        }
        return conversion.displayLabel
    }

    /// Convert any stored range (metric canonical) to the requested system using the PID's units label.
    private func converted(range: ValueRange?, for measurementUnit: MeasurementUnit) -> ValueRange? {
        guard let range, let base = units else { return range }
        return range.converted(from: base, to: measurementUnit)
    }

    /// Typical range converted to the requested measurement system.
    func typicalRange(for measurementUnit: MeasurementUnit) -> ValueRange? {
        converted(range: typicalRange, for: measurementUnit)
    }

    /// Warning range converted to the requested measurement system.
    func warningRange(for measurementUnit: MeasurementUnit) -> ValueRange? {
        converted(range: warningRange, for: measurementUnit)
    }

    /// Danger range converted to the requested measurement system.
    func dangerRange(for measurementUnit: MeasurementUnit) -> ValueRange? {
        converted(range: dangerRange, for: measurementUnit)
    }
    
    func displayUnits(for measurementUnit: MeasurementUnit) -> String {
        unitLabel(for: measurementUnit)
    }
    
    func combinedRange() -> ValueRange {
        let metricRanges: [ValueRange] = [typicalRange, warningRange, dangerRange].compactMap { $0 }
        let fallbackTypical = typicalRange ?? ValueRange(min: 0, max: 1)
        let metricMin = metricRanges.map(\.min).min() ?? fallbackTypical.min
        let metricMax = metricRanges.map(\.max).max() ?? fallbackTypical.max
        return ValueRange(min: metricMin, max: metricMax)
    }

    /// Returns a display string for UI, e.g. "600 – 7000 RPM", converted for the requested unit.
    func displayRange(for measurementUnit: MeasurementUnit) -> String {
        guard let baseUnits = units
              //    let metricTypical = combinedRange() //typicalRange
        else { return "" }

        let metricTypical = combinedRange()
        // Convert the typical range and label
        let convertedTypical = metricTypical.converted(from: baseUnits, to: measurementUnit)
        let unitLabel = unitLabel(for: measurementUnit)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let digits = preferredFractionDigits(forUnits: unitLabel)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits

        let minStr = formatter.string(from: NSNumber(value: convertedTypical.min)) ?? String(format: "%.\(digits)f", convertedTypical.min)
        let maxStr = formatter.string(from: NSNumber(value: convertedTypical.max)) ?? String(format: "%.\(digits)f", convertedTypical.max)

        return "\(minStr) – \(maxStr) \(unitLabel)"
    }

    /// Formats a single value using the same units-aware fraction digit policy as displayRange,
    /// honoring the requested measurement system's unit label.
    func formattedValue(_ value: Double, unit measurementUnit: MeasurementUnit, includeUnits: Bool = true) -> String {
        let unitLabel = unitLabel(for: measurementUnit)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let digits = preferredFractionDigits(forUnits: unitLabel)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits

        let numberString = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
        if includeUnits, !unitLabel.isEmpty {
            return "\(numberString) \(unitLabel)"
        } else {
            return numberString
        }
    }

    // MARK: - MeasurementResult-aware presentation helpers (use actual Unit)

    /// Map Foundation.Unit to a concise display label.
    func unitLabel(for foundationUnit: Unit) -> String {
        switch foundationUnit {
        case is UnitDuration:
            return ""
        case is UnitTemperature:
            if foundationUnit == UnitTemperature.celsius { return "°C" }
            if foundationUnit == UnitTemperature.fahrenheit { return "°F" }
            return "°"
        case is UnitSpeed:
            if foundationUnit == UnitSpeed.kilometersPerHour { return "km/h" }
            if foundationUnit == UnitSpeed.milesPerHour { return "mph" }
            return ""
        case is UnitPressure:
            if foundationUnit == UnitPressure.kilopascals { return "kPa" }
            if foundationUnit == UnitPressure.poundsForcePerSquareInch { return "psi" }
            if foundationUnit == UnitPressure.hectopascals { return "hPa" }
            if foundationUnit == UnitPressure.bars { return "bar" }
            return ""
        case is UnitLength:
            if foundationUnit == UnitLength.kilometers { return "km" }
            if foundationUnit == UnitLength.miles { return "mi" }
            return ""
        case is UnitElectricPotentialDifference:
            return "V"
        case is UnitElectricCurrent:
            if foundationUnit == UnitElectricCurrent.milliamperes { return "mA" }
            if foundationUnit == UnitElectricCurrent.amperes { return "A" }
            return "A"
        case is UnitAngle:
            return "° BTDC"
        case is UnitDuration:
            // Not typically used for gauge values; leave blank
            return ""
        case is UnitFrequency:
            return "Hz"
        default:
            // Handle custom Units you defined in decoders.swift
            let symbol = foundationUnit.symbol
            switch symbol {
            case "%": return "%"
            case "g/s": return "g/s"
            case "rpm", "RPM": return "RPM"
            case "Pa": return "Pa"
            case "L/h": return "L/h"
            case "λ": return "λ"
            case "count": return "count"
            case "s": return "s"
            default: return symbol // fallback to whatever Unit.symbol was provided
            }
        }
    }

    /// Formats a MeasurementResult using its own Unit, not the app's MeasurementUnit.
    func formatted(measurement: MeasurementResult, includeUnits: Bool = true) -> String {
        let label = unitLabel(for: measurement.unit)
        
        // do a special case for time based values
        if measurement.unit is UnitDuration {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .positional
            formatter.zeroFormattingBehavior = [.pad]
            return formatter.string(from: measurement.value) ?? "--:--:--"
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let digits = preferredFractionDigits(forUnits: label)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits

        let numberString = formatter.string(from: NSNumber(value: measurement.value)) ?? String(format: "%.\(digits)f", measurement.value)
        if includeUnits, !label.isEmpty {
            return "\(numberString) \(label)"
        } else {
            return numberString
        }
    }

    // Backward-compatible versions that default to the app's configured units

    var displayUnits: String {
        displayUnits(for: ConfigData.shared.units)
    }
    /// Returns a display string for UI, e.g. "600 – 7000 RPM"
    var displayRange: String {
        displayRange(for: ConfigData.shared.units)
    }

    /// Formats a single value using the app's configured units.
    func formattedValue(_ value: Double, includeUnits: Bool = true) -> String {
        formattedValue(value, unit: ConfigData.shared.units, includeUnits: includeUnits)
    }

    /// Unit-aware color evaluation: uses converted ranges for the provided measurement system.
    func color(for value: Double, unit measurementUnit: MeasurementUnit) -> Color {
        if let danger = dangerRange(for: measurementUnit), danger.contains(value) {
            return .red
        }
        if let warn = warningRange(for: measurementUnit), warn.contains(value) {
            return .yellow
        }
        if let typical = typicalRange(for: measurementUnit), typical.contains(value) {
            return .green
        }
        return .gray
    }

    /// Backward-compatible color evaluation using the app's configured units.
    func color(for value: Double) -> Color {
        color(for: value, unit: ConfigData.shared.units)
    }

    /// Pick conventional fraction digits for the given units.
    /// Adjust this mapping as needed for your domain.
    private func preferredFractionDigits(forUnits units: String) -> Int {
        switch units {
        case "RPM":
            return 0
        case "°C", "°F":
            return 0
        case "%":
            return 0
        case "kPa", "psi":
            return 0
        case "V":
            return 2
        case "g/s":
            return 2
        case "λ":
            return 2
        case "km/h", "mph":
            return 0
        case "km", "mi":
            return 0
        case "L/h":
            return 1
        case "s", "count":
            return 0
        default:
            return 0
        }
    }
}

// MARK: - Library

/// Groups a set of standard OBD-II PIDs.
struct OBDPIDLibrary {
    static let standard: [OBDPID] = [
        OBDPID(
            enabled: true,
            label: "FuelStat",
            name: "Fuel Control Status",
            pid: .mode1(.fuelStatus),
            //formula: "A – 40",
            units: "NA",
            typicalRange: .init(min: 0, max: 100),
            //warningRange: .init(min: 80, max: 100),
            //dangerRange: .init(min: 100, max: 150),
            notes: "Returns open/closed loop data.",
            kind: .status
        ),
        OBDPID(
            enabled: true,
            label: "MIL Stat",
            name: "MIL Status",
            pid: .mode1(.status),
            //formula: "A – 40",
            units: "NA",
            typicalRange: .init(min: 0, max: 100),
            //warningRange: .init(min: 80, max: 100),
            //dangerRange: .init(min: 100, max: 150),
            notes: "Returns MIL status",
            kind: .status
        ),
        OBDPID(
            enabled: true,
            label: "IAT",
            name: "Intake Air Temperature",
            pid: .mode1(.intakeTemp),
            formula: "A – 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 80),
            warningRange: .init(min: 80, max: 100),
            dangerRange: .init(min: 100, max: 150),
            notes: "Correlates with ambient and heat-soak."
        ),
        OBDPID(
            enabled: true,
            label: "Voltage",
            name: "Control Module Voltage",
            pid: .mode1(.controlModuleVoltage),
            formula: "((A*256)+B)/1000",
            units: "V",
            typicalRange: .init(min: 8, max: 16),
            warningRange: .init(min: 0, max: 12),
            dangerRange: .init(min: 15, max: 18),
            notes: "Battery/alternator voltage"
        ),
        OBDPID(
            enabled: true,
            label: "Coolant",
            name: "Engine Coolant Temperature",
            pid: .mode1(.coolantTemp),
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 98),
            warningRange: .init(min: 98, max: 108),
            dangerRange: .init(min: 108, max: 150),
            notes: "Subtract 40 offset"
        ),
        OBDPID(
            enabled: true,
            label: "RPM",
            name: "Engine RPM",
            pid: .mode1(.rpm),
            formula: "((A*256)+B)/4",
            units: "RPM",
            typicalRange: .init(min: 0, max: 8000),
            warningRange: .init(min: 6000, max: 7500),
            dangerRange: .init(min: 7500, max: 8500),
            notes: "Main tachometer source"
        ),
        OBDPID(
            enabled: false,
            label: "AFR λ",
            name: "Commanded Equivalence Ratio (Lambda)",
            pid: .mode1(.commandedEquivRatio),
            formula: "((A*256)+B)/32768",
            units: "λ",
            typicalRange: .init(min: 0.7, max: 1.3),
            warningRange: nil,
            dangerRange: nil,
            notes: "1.00 = stoich tick; AFR secondary scale handled elsewhere"
        ),
        OBDPID(
            enabled: false,
            label: "Speed",
            name: "Vehicle Speed",
            pid: .mode1(.speed),
            formula: "A",
            units: "km/h",
            typicalRange: .init(min: 0, max: 240),
            warningRange: nil,
            dangerRange: nil,
            notes: "Conversion to mph handled elsewhere"
        ),
        OBDPID(
            enabled: false,
            label: "Oil Temp",
            name: "Engine Oil Temperature",
            pid: .mode1(.engineOilTemp),
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 98),
            warningRange: .init(min: 98, max: 108),
            dangerRange: .init(min: 108, max: 150),
            notes: "Optional PID"
        ),
        OBDPID(
            enabled: false,
            label: "Fuel Pres",
            name: "Fuel Pressure",
            pid: .mode1(.fuelPressure),
            formula: "A*3",
            units: "kPa",
            typicalRange: .init(min: 0, max: 765),
            warningRange: nil,
            dangerRange: nil,
            notes: "Legacy/gauge fuel pressure"
        ),
        OBDPID(
            enabled: false,
            label: "CatT B1S1",
            name: "Catalyst Temperature Bank 1 Sensor 1",
            pid: .mode1(.catalystTempB1S1),
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Pre-cat temp; linear thermometer"
        ),
        OBDPID(
            enabled: false,
            label: "Throttle",
            name: "Throttle Position",
            pid: .mode1(.throttlePos),
            formula: "((A*256)+B)/10",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Accelerator plate position"
        ),
        // Newly added: Throttle Actuator Command
        OBDPID(
            enabled: false,
            label: "Thr Act",
            name: "Throttle Actuator Command",
            pid: .mode1(.throttleActuator),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "ECU-commanded DBW throttle; compare vs TPS for tracking"
        ),
        // Newly added: Alternate Throttle Position Sensors (disabled gauges)
        OBDPID(
            enabled: false,
            label: "TPS B",
            name: "Throttle Position Sensor B",
            pid: .mode1(.throttlePosB),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Alternate TPS track B"
        ),
        OBDPID(
            enabled: false,
            label: "TPS C",
            name: "Throttle Position Sensor C",
            pid: .mode1(.throttlePosC),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Alternate TPS track C"
        ),
        OBDPID(
            enabled: false,
            label: "TPS D",
            name: "Throttle Position Sensor D",
            pid: .mode1(.throttlePosD),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Alternate TPS track D"
        ),
        OBDPID(
            enabled: false,
            label: "TPS E",
            name: "Throttle Position Sensor E",
            pid: .mode1(.throttlePosE),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Alternate TPS track E"
        ),
        OBDPID(
            enabled: false,
            label: "TPS F",
            name: "Throttle Position Sensor F",
            pid: .mode1(.throttlePosF),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Alternate TPS track F"
        ),
        OBDPID(
            enabled: false,
            label: "Ign Time",
            name: "Timing Advance",
            pid: .mode1(.timingAdvance),
            formula: "(A/2) – 64",
            units: "° BTDC",
            typicalRange: .init(min: -10, max: 60),
            warningRange: nil,
            dangerRange: nil,
            notes: "Center gauge at 0°, bipolar −10° to +60°"
        ),

        // MARK: - Added per earlier request

        OBDPID(
            enabled: false,
            label: "Amb Temp",
            name: "Ambient Air Temperature",
            pid: .mode1(.ambientAirTemp),
            formula: "A – 40",
            units: "°C",
            typicalRange: .init(min: -40, max: 50),
            warningRange: nil,
            dangerRange: nil,
            notes: "Outside/ambient temperature"
        ),
        OBDPID(
            enabled: false,
            label: "Rel TPS",
            name: "Relative Throttle Position",
            pid: .mode1(.relativeThrottlePos),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Relative to learned min/max"
        ),
        OBDPID(
            enabled: false,
            label: "Eng Load",
            name: "Calculated Engine Load",
            pid: .mode1(.engineLoad),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Calculated load"
        ),
        OBDPID(
            enabled: false,
            label: "Abs Load",
            name: "Absolute Load Value",
            pid: .mode1(.absoluteLoad),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Absolute load value"
        ),
        OBDPID(
            enabled: false,
            label: "Fuel Lvl",
            name: "Fuel Level Input",
            pid: .mode1(.fuelLevel),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: .init(min: 0, max: 10),
            dangerRange: .init(min: 0, max: 5),
            notes: "Tank level"
        ),
        OBDPID(
            enabled: false,
            label: "Baro",
            name: "Barometric Pressure",
            pid: .mode1(.barometricPressure),
            formula: "A",
            units: "kPa",
            typicalRange: .init(min: 80, max: 105),
            warningRange: nil,
            dangerRange: nil,
            notes: "Convert to inHg elsewhere if needed"
        ),
        OBDPID(
            enabled: false,
            label: "MAP",
            name: "Intake Manifold Absolute Pressure",
            pid: .mode1(.intakePressure),
            formula: "A",
            units: "kPa",
            typicalRange: .init(min: 20, max: 250),
            warningRange: nil,
            dangerRange: nil,
            notes: "Boost can be derived vs baro"
        ),
        OBDPID(
            enabled: false,
            label: "Rail P",
            name: "Fuel Rail Pressure (Absolute)",
            pid: .mode1(.fuelRailPressureAbs),
            formula: "((A*256)+B) * 10",
            units: "kPa",
            typicalRange: .init(min: 0, max: 20000), // 0–20 MPa
            warningRange: nil,
            dangerRange: nil,
            notes: "Display as MPa/PSI elsewhere if preferred"
        ),
        OBDPID(
            enabled: false,
            label: "Rail P DI",
            name: "Fuel Rail Pressure (Direct Injection)",
            pid: .mode1(.fuelRailPressureDirect),
            formula: "((A*256)+B) * 10",
            units: "kPa",
            typicalRange: .init(min: 0, max: 20000), // 0–20 MPa
            warningRange: nil,
            dangerRange: nil,
            notes: "DI rail; convert to MPa/PSI elsewhere"
        ),
        OBDPID(
            enabled: false,
            label: "Rail P Vac",
            name: "Fuel Rail Pressure (Relative to Manifold Vacuum)",
            pid: .mode1(.fuelRailPressureVac),
            formula: "((A*256)+B) * 0.079",
            units: "kPa",
            typicalRange: .init(min: 0, max: 700),
            warningRange: nil,
            dangerRange: nil,
            notes: "Relative to manifold vacuum"
        ),

        // MARK: - Newly added per latest request

        OBDPID(
            enabled: false,
            label: "MAF",
            name: "Mass Air Flow",
            pid: .mode1(.maf),
            formula: "((A*256)+B)/100",
            units: "g/s",
            typicalRange: .init(min: 0, max: 300),
            warningRange: nil,
            dangerRange: nil,
            notes: "Wide range; linear bar reads well; scale by engine size"
        ),
        OBDPID(
            enabled: false,
            label: "FuelRate",
            name: "Fuel Rate",
            pid: .mode1(.fuelRate),
            formula: "((A*256)+B)/20",
            units: "L/h",
            typicalRange: .init(min: 0, max: 50),
            warningRange: nil,
            dangerRange: nil,
            notes: "Typical 0–50 L/h; tank/diesel may go higher"
        ),
        OBDPID(
            enabled: false,
            label: "Rel Accel",
            name: "Relative Accelerator Pedal Position",
            pid: .mode1(.relativeAccelPos),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Pedal position relative to calibrated range"
        ),
        OBDPID(
            enabled: false,
            label: "CatT B2S1",
            name: "Catalyst Temperature Bank 2 Sensor 1",
            pid: .mode1(.catalystTempB2S1),
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Pre-cat temp; linear thermometer"
        ),
        OBDPID(
            enabled: false,
            label: "CatT B1S2",
            name: "Catalyst Temperature Bank 1 Sensor 2",
            pid: .mode1(.catalystTempB1S2),
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Post-cat temp; linear thermometer"
        ),
        OBDPID(
            enabled: false,
            label: "CatT B2S2",
            name: "Catalyst Temperature Bank 2 Sensor 2",
            pid: .mode1(.catalystTempB2S2),
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Post-cat temp; linear thermometer"
        ),

        // MARK: - Bank 2 additions (gauges)

        OBDPID(
            enabled: false,
            label: "STFT B2",
            name: "Short Term Fuel Trim Bank 2",
            pid: .mode1(.shortFuelTrim2),
            formula: "(A - 128) * 100 / 128",
            units: "%",
            typicalRange: .init(min: -25, max: 25),
            warningRange: nil,
            dangerRange: nil,
            notes: "Real-time fuel correction; V engines use Bank 2"
        ),
        OBDPID(
            enabled: false,
            label: "LTFT B2",
            name: "Long Term Fuel Trim Bank 2",
            pid: .mode1(.longFuelTrim2),
            formula: "(A - 128) * 100 / 128",
            units: "%",
            typicalRange: .init(min: -25, max: 25),
            warningRange: nil,
            dangerRange: nil,
            notes: "Learned fuel correction; V engines use Bank 2"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B2S1",
            name: "O2 Sensor Voltage Bank 2 Sensor 1",
            pid: .mode1(.O2Bank2Sensor1),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Upstream O₂ sensor; narrowband typical 0–1 V"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B2S2",
            name: "O2 Sensor Voltage Bank 2 Sensor 2",
            pid: .mode1(.O2Bank2Sensor2),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Downstream O₂ sensor; narrowband typical 0–1 V"
        ),

        // MARK: - Newly added per user request (Bank 1 trims, O2, EVAP purge, WR currents, EVAP vapor pressure, O2 bitmap)

        OBDPID(
            enabled: false,
            label: "LTFT B1",
            name: "Long Term Fuel Trim Bank 1",
            pid: .mode1(.longFuelTrim1),
            formula: "(A - 128) * 100 / 128",
            units: "%",
            typicalRange: .init(min: -25, max: 25),
            warningRange: nil,
            dangerRange: nil,
            notes: "Learned fuel correction; Bank 1"
        ),
        OBDPID(
            enabled: false,
            label: "STFT B1",
            name: "Short Term Fuel Trim Bank 1",
            pid: .mode1(.shortFuelTrim1),
            formula: "(A - 128) * 100 / 128",
            units: "%",
            typicalRange: .init(min: -25, max: 25),
            warningRange: nil,
            dangerRange: nil,
            notes: "Real-time fuel correction; Bank 1"
        ),
        OBDPID(
            enabled: false,
            label: "WR I S7",
            name: "Wideband O2 Sensor Current Sensor 7",
            pid: .mode1(.O2Sensor7WRCurrent),
            formula: "((A*256)+B - 32768) / 256",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil,
            notes: "Wideband current; verify scaling for your ECU"
        ),
        OBDPID(
            enabled: false,
            label: "WR I S1",
            name: "Wideband O2 Sensor Current Sensor 1",
            pid: .mode1(.O2Sensor1WRCurrent),
            formula: "((A*256)+B - 32768) / 256",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil,
            notes: "Wideband current; verify scaling for your ECU"
        ),
        OBDPID(
            enabled: false,
            label: "WR I S2",
            name: "Wideband O2 Sensor Current Sensor 2",
            pid: .mode1(.O2Sensor2WRCurrent),
            formula: "((A*256)+B - 32768) / 256",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil,
            notes: "Wideband current; verify scaling for your ECU"
        ),
        OBDPID(
            enabled: false,
            label: "EVAP Cmd",
            name: "Commanded EVAP Purge",
            pid: .mode1(.evaporativePurge),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Purge valve duty cycle"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B1S1",
            name: "O2 Sensor Voltage Bank 1 Sensor 1",
            pid: .mode1(.O2Bank1Sensor1),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Upstream O₂ sensor; narrowband typical 0–1 V"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B1S2",
            name: "O2 Sensor Voltage Bank 1 Sensor 2",
            pid: .mode1(.O2Bank1Sensor2),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Downstream O₂ sensor; narrowband typical 0–1 V"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B1S3",
            name: "O2 Sensor Voltage Bank 1 Sensor 3",
            pid: .mode1(.O2Bank1Sensor3),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Downstream O₂ sensor; narrowband typical 0–1 V"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B1S4",
            name: "O2 Sensor Voltage Bank 1 Sensor 4",
            pid: .mode1(.O2Bank1Sensor4),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Downstream O₂ sensor; narrowband typical 0–1 V"
        ),
        OBDPID(
            enabled: false,
            label: "O2V B2S3",
            name: "O2 Sensor Voltage Bank 2 Sensor 3",
            pid: .mode1(.O2Bank2Sensor3),
            formula: "A / 200",
            units: "V",
            typicalRange: .init(min: 0.0, max: 1.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "Downstream O₂ sensor; narrowband typical 0–1 V"
        ),
        OBDPID(
            enabled: false,
            label: "O2 Map",
            name: "O2 Sensors Present (Bitfield)",
            pid: .mode1(.O2Sensor),
            formula: "bitfield",
            units: "NA",
            typicalRange: .init(min: 0, max: 255),
            warningRange: nil,
            dangerRange: nil,
            notes: "Bitmask of O₂ sensors present; not a gauge",
            kind: .status
        ),

        // MARK: - Newly added status entries

        OBDPID(
            enabled: false,
            label: "FuelType",
            name: "Fuel Type",
            pid: .mode1(.fuelType),
            formula: "categorical",
            units: "NA",
            typicalRange: .init(min: 0, max: 255),
            warningRange: nil,
            dangerRange: nil,
            notes: "Categorical: gasoline, diesel, etc.",
            kind: .status
        ),
        OBDPID(
            enabled: false,
            label: "OBD Comp",
            name: "OBD Compliance",
            pid: .mode1(.obdcompliance),
            formula: "categorical",
            units: "NA",
            typicalRange: .init(min: 0, max: 255),
            warningRange: nil,
            dangerRange: nil,
            notes: "OBD standard/version compliance",
            kind: .status
        ),
        OBDPID(
            enabled: false,
            label: "DrvCycle",
            name: "Monitor Status This Drive Cycle",
            pid: .mode1(.statusDriveCycle),
            formula: "bitfield",
            units: "NA",
            typicalRange: .init(min: 0, max: 0xFFFFFFFF),
            warningRange: nil,
            dangerRange: nil,
            notes: "Monitors readiness for current drive cycle",
            kind: .status
        ),
        OBDPID(
            enabled: false,
            label: "FreezeDTC",
            name: "Freeze DTC",
            pid: .mode1(.freezeDTC),
            formula: "DTC",
            units: "NA",
            typicalRange: .init(min: 0, max: 0xFFFF),
            warningRange: nil,
            dangerRange: nil,
            notes: "Stored DTC at time of freeze-frame capture",
            kind: .status
        ),
        OBDPID(
            enabled: false,
            label: "Sec Air",
            name: "Secondary Air Status",
            pid: .mode1(.airStatus),
            formula: "categorical",
            units: "NA",
            typicalRange: .init(min: 0, max: 255),
            warningRange: nil,
            dangerRange: nil,
            notes: "Secondary air system status",
            kind: .status
        ),

        OBDPID(
            enabled: false,
            label: "EVAP VP",
            name: "EVAP Vapor Pressure",
            pid: .mode1(.evapVaporPressure),
            formula: "((A*256)+B)/4 (kPa)",
            units: "kPa",
            typicalRange: .init(min: -20, max: 20),
            warningRange: nil,
            dangerRange: nil,
            notes: "Reported in kPa via PID 0132"
        ),
        OBDPID(
            enabled: false,
            label: "EVAP VP Alt",
            name: "EVAP Vapor Pressure (Alt/Pa)",
            pid: .mode1(.evapVaporPressureAlt),
            formula: "((A*256)+B) - 32767",
            units: "Pa",
            typicalRange: .init(min: -2000, max: 2000),
            warningRange: nil,
            dangerRange: nil,
            notes: "Alternate scaling (Pa) via PID 0154"
        ),
        OBDPID(
            enabled: false,
            label: "EVAP VP Abs",
            name: "EVAP Vapor Pressure (Absolute)",
            pid: .mode1(.evapVaporPressureAbs),
            formula: "((A*256)+B)/200",
            units: "kPa",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Absolute EVAP pressure via PID 0153"
        ),

        // GM extended commands
        

        OBDPID(
            enabled: false,
            label: "GM Oil P",
            name: "GM Engine Oil Pressure",
            pid: .GMmode22(.engineOilPressure),
            formula: "[psi]=A×0.578",
            units: "kPa",
            typicalRange: .init(min: 0, max: 800),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "GM Oil T",
            name: "GM Engine Oil Temperature",
            pid: .GMmode22(.engineOilTemp),
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 98),
            warningRange: .init(min: 98, max: 108),
            dangerRange: .init(min: 108, max: 150),
        ),
        OBDPID(
            enabled: false,
            label: "GM AC HiP",
            name: "GM A/C High Side Pressure",
            pid: .GMmode22(.ACHighPressure),
            formula: "PAC​[psig]=(A×1.83)−14.7",
            units: "kPa",
            typicalRange: .init(min: 0, max: 800),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "GM TransT",
            name: "GM Transmission Fluid Temperature",
            pid: .GMmode22(.transFluidTemp),
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 98),
            warningRange: .init(min: 98, max: 108),
            dangerRange: .init(min: 108, max: 150),
        ),

        // MARK: - Newly added numeric Mode 1 PIDs (previously missing)

        OBDPID(
            enabled: false,
            label: "Run Time",
            name: "Engine Run Time",
            pid: .mode1(.runTime),
            formula: "((A*256)+B) s",
            units: "s",
            typicalRange: .init(min: 0, max: 65535),
            warningRange: nil,
            dangerRange: nil,
            notes: "Seconds since engine start"
        ),
        OBDPID(
            enabled: false,
            label: "Dist MIL",
            name: "Distance with MIL On",
            pid: .mode1(.distanceWMIL),
            formula: "((A*256)+B) km",
            units: "km",
            typicalRange: .init(min: 0, max: 65535),
            warningRange: nil,
            dangerRange: nil,
            notes: "Distance travelled while MIL was on"
        ),
        OBDPID(
            enabled: false,
            label: "WR V S1",
            name: "Wideband O2 Lambda Voltage Sensor 1",
            pid: .mode1(.O2Sensor1WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil,
            notes: "Wideband controller voltage"
        ),
        OBDPID(
            enabled: false,
            label: "WR V S2",
            name: "Wideband O2 Lambda Voltage Sensor 2",
            pid: .mode1(.O2Sensor2WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR V S3",
            name: "Wideband O2 Lambda Voltage Sensor 3",
            pid: .mode1(.O2Sensor3WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR V S4",
            name: "Wideband O2 Lambda Voltage Sensor 4",
            pid: .mode1(.O2Sensor4WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR V S5",
            name: "Wideband O2 Lambda Voltage Sensor 5",
            pid: .mode1(.O2Sensor5WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR V S6",
            name: "Wideband O2 Lambda Voltage Sensor 6",
            pid: .mode1(.O2Sensor6WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR V S7",
            name: "Wideband O2 Lambda Voltage Sensor 7",
            pid: .mode1(.O2Sensor7WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR V S8",
            name: "Wideband O2 Lambda Voltage Sensor 8",
            pid: .mode1(.O2Sensor8WRVolatage),
            formula: "((A*256)+B) * 8 / 65535",
            units: "V",
            typicalRange: .init(min: 0, max: 5),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "Cmd EGR",
            name: "Commanded EGR",
            pid: .mode1(.commandedEGR),
            formula: "A * 100 / 255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "EGR duty command"
        ),
        OBDPID(
            enabled: false,
            label: "EGR Err",
            name: "EGR Error",
            pid: .mode1(.EGRError),
            formula: "(A - 128) * 100 / 128",
            units: "%",
            typicalRange: .init(min: -100, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Centered percent error"
        ),
        OBDPID(
            enabled: false,
            label: "Warm-ups",
            name: "Warm-ups Since DTC Cleared",
            pid: .mode1(.warmUpsSinceDTCCleared),
            formula: "A",
            units: "count",
            typicalRange: .init(min: 0, max: 255),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "Dist DTC Clr",
            name: "Distance Since DTC Cleared",
            pid: .mode1(.distanceSinceDTCCleared),
            formula: "((A*256)+B) km",
            units: "km",
            typicalRange: .init(min: 0, max: 65535),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR I S3",
            name: "Wideband O2 Sensor Current Sensor 3",
            pid: .mode1(.O2Sensor3WRCurrent),
            formula: "(A-128)*(2/128)",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR I S4",
            name: "Wideband O2 Sensor Current Sensor 4",
            pid: .mode1(.O2Sensor4WRCurrent),
            formula: "(A-128)*(2/128)",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR I S5",
            name: "Wideband O2 Sensor Current Sensor 5",
            pid: .mode1(.O2Sensor5WRCurrent),
            formula: "(A-128)*(2/128)",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR I S6",
            name: "Wideband O2 Sensor Current Sensor 6",
            pid: .mode1(.O2Sensor6WRCurrent),
            formula: "(A-128)*(2/128)",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "WR I S8",
            name: "Wideband O2 Sensor Current Sensor 8",
            pid: .mode1(.O2Sensor8WRCurrent),
            formula: "(A-128)*(2/128)",
            units: "mA",
            typicalRange: .init(min: -10, max: 10),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "MIL Time",
            name: "Run Time with MIL On",
            pid: .mode1(.runTimeMIL),
            formula: "((A*256)+B) s",
            units: "s",
            typicalRange: .init(min: 0, max: 65535),
            warningRange: nil,
            dangerRange: nil,
            notes: "Seconds with MIL illuminated"
        ),
        OBDPID(
            enabled: false,
            label: "DTC Clear",
            name: "Time Since DTC Cleared",
            pid: .mode1(.timeSinceDTCCleared),
            formula: "((A*256)+B) s",
            units: "s",
            typicalRange: .init(min: 0, max: 65535),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "Max MAF",
            name: "Maximum MAF Since Clear",
            pid: .mode1(.maxMAF),
            formula: "A * 10",
            units: "g/s",
            typicalRange: .init(min: 0, max: 655),
            warningRange: nil,
            dangerRange: nil,
            notes: "Max airflow since DTC clear"
        ),
        OBDPID(
            enabled: false,
            label: "Ethanol %",
            name: "Ethanol Fuel Percentage",
            pid: .mode1(.ethanoPercent),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil
        ),
        OBDPID(
            enabled: false,
            label: "Hybrid SOC",
            name: "Hybrid Battery Remaining Life",
            pid: .mode1(.hybridBatteryLife),
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: .init(min: 0, max: 10),
            dangerRange: .init(min: 0, max: 5),
            notes: "State of charge estimate"
        ),
        OBDPID(
            enabled: false,
            label: "Inj Time",
            name: "Fuel Injection Timing",
            pid: .mode1(.fuelInjectionTiming),
            formula: "((A*256)+B - 26880)/128",
            units: "° BTDC",
            typicalRange: .init(min: -50, max: 50),
            warningRange: nil,
            dangerRange: nil,
            notes: "Degrees BTDC/ATDC"
        )
        
    ]
}
