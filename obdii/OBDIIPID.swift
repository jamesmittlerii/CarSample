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
    let name: String
    let pid: OBDCommand.Mode1
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
        name: String,
        pid: OBDCommand.Mode1,
        formula: String? = nil,
        units: String,
        typicalRange: ValueRange,
        warningRange: ValueRange? = nil,
        dangerRange: ValueRange? = nil,
        notes: String? = nil,
        kind: Kind = .gauge
    ) {
        self.id = id
        self.name = name
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

    // MARK: - Derived Behavior

    /// Returns a display string for UI, e.g. "600 – 7000 RPM"
    var displayRange: String {
        guard let range = typicalRange else { return "" }
        let unitLabel = units ?? "unknown"
        
        return String(format: "%.0f – %.0f %@", range.min, range.max, unitLabel)
    }

    /// Returns a color representing the current value’s state
    func color(for value: Double) -> Color {
        
        guard typicalRange != nil else { return .gray }
        if let danger = dangerRange, danger.contains(value) {
            return .red
        }
        if let warn = warningRange, warn.contains(value) {
            return .yellow
        }
        if typicalRange!.contains(value) {
            return .green
        }
        return .gray
    }
}

// MARK: - Library

/// Groups a set of standard OBD-II PIDs.
struct OBDPIDLibrary {
    static let standard: [OBDPID] = [
        
        OBDPID(
            enabled: true,
            name: "Fuel System Status",
            pid: OBDCommand.Mode1.fuelStatus,
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
            name: "MIL Status",
            pid: OBDCommand.Mode1.status,
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
            name: "Intake Air Temp (IAT)",
            pid: OBDCommand.Mode1.intakeTemp,
            formula: "A – 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 80),
            warningRange: .init(min: 80, max: 100),
            dangerRange: .init(min: 100, max: 150),
            notes: "Correlates with ambient and heat-soak."
        ),
        OBDPID(
            enabled: true,
            name: "OBD Module Voltage",
            pid: OBDCommand.Mode1.controlModuleVoltage,
            formula: "((A*256)+B)/1000",
            units: "V",
            typicalRange: .init(min: 8, max: 16),
            warningRange: .init(min: 0, max: 12),
            dangerRange: .init(min: 15, max: 18),
            notes: "Battery/alternator voltage"
        ),
        OBDPID(
            enabled: true,
            name: "Engine Coolant Temp",
            pid: OBDCommand.Mode1.coolantTemp,
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 98),
            warningRange: .init(min: 98, max: 108),
            dangerRange: .init(min: 108, max: 150),
            notes: "Subtract 40 offset"
        ),
        OBDPID(
            enabled: true,
            name: "Engine RPM",
            pid: OBDCommand.Mode1.rpm,
            formula: "((A*256)+B)/4",
            units: "RPM",
            typicalRange: .init(min: 0, max: 8000),
            warningRange: .init(min: 6000, max: 7500),
            dangerRange: .init(min: 7500, max: 8500),
            notes: "Main tachometer source"
        ),
        OBDPID(
            enabled: false,
            name: "Air-Fuel Ratio (λ)",
            pid: OBDCommand.Mode1.commandedEquivRatio,
            formula: "((A*256)+B)/32768",
            units: "λ",
            typicalRange: .init(min: 0.7, max: 1.3),
            warningRange: nil,
            dangerRange: nil,
            notes: "1.00 = stoich tick; AFR secondary scale handled elsewhere"
        ),
        OBDPID(
            enabled: false,
            name: "Vehicle Speed",
            pid: OBDCommand.Mode1.speed,
            formula: "A",
            units: "km/h",
            typicalRange: .init(min: 0, max: 240),
            warningRange: nil,
            dangerRange: nil,
            notes: "Conversion to mph handled elsewhere"
        ),
        OBDPID(
            enabled: false,
            name: "Engine Oil Temp",
            pid: OBDCommand.Mode1.engineOilTemp,
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 98),
            warningRange: .init(min: 98, max: 108),
            dangerRange: .init(min: 108, max: 150),
            notes: "Optional PID"
        ),
        OBDPID(
            enabled: false,
            name: "Fuel Pressure (Gauge)",
            pid: OBDCommand.Mode1.fuelPressure,
            formula: "A*3",
            units: "kPa",
            typicalRange: .init(min: 0, max: 765),
            warningRange: nil,
            dangerRange: nil,
            notes: "Legacy/gauge fuel pressure"
        ),
        OBDPID(
            enabled: false,
            name: "Catalyst Temp (Bank 1, Sensor 1)",
            pid: OBDCommand.Mode1.catalystTempB1S1,
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Pre-cat temp; linear thermometer"
        ),
        OBDPID(
            enabled: false,
            name: "Throttle Position",
            pid: OBDCommand.Mode1.throttlePos,
            formula: "((A*256)+B)/10",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Accelerator plate position"
        ),
        OBDPID(
            enabled: false,
            name: "Ignition Timing",
            pid: OBDCommand.Mode1.timingAdvance,
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
            name: "Ambient Air Temp",
            pid: OBDCommand.Mode1.ambientAirTemp,
            formula: "A – 40",
            units: "°C",
            typicalRange: .init(min: -40, max: 50),
            warningRange: nil,
            dangerRange: nil,
            notes: "Outside/ambient temperature"
        ),
        OBDPID(
            enabled: false,
            name: "Relative Throttle Position",
            pid: OBDCommand.Mode1.relativeThrottlePos,
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Relative to learned min/max"
        ),
        OBDPID(
            enabled: false,
            name: "Engine Load",
            pid: OBDCommand.Mode1.engineLoad,
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Calculated load"
        ),
        OBDPID(
            enabled: false,
            name: "Absolute Load",
            pid: OBDCommand.Mode1.absoluteLoad,
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Absolute load value"
        ),
        OBDPID(
            enabled: false,
            name: "Fuel Level",
            pid: OBDCommand.Mode1.fuelLevel,
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: .init(min: 0, max: 10),
            dangerRange: .init(min: 0, max: 5),
            notes: "Tank level"
        ),
        OBDPID(
            enabled: false,
            name: "Barometric Pressure",
            pid: OBDCommand.Mode1.barometricPressure,
            formula: "A",
            units: "kPa",
            typicalRange: .init(min: 80, max: 105),
            warningRange: nil,
            dangerRange: nil,
            notes: "Convert to inHg elsewhere if needed"
        ),
        OBDPID(
            enabled: false,
            name: "Intake Manifold Pressure (MAP)",
            pid: OBDCommand.Mode1.intakePressure,
            formula: "A",
            units: "kPa",
            typicalRange: .init(min: 20, max: 250),
            warningRange: nil,
            dangerRange: nil,
            notes: "Boost can be derived vs baro"
        ),
        OBDPID(
            enabled: false,
            name: "Fuel Rail Pressure (Absolute)",
            pid: OBDCommand.Mode1.fuelRailPressureAbs,
            formula: "((A*256)+B) * 10",
            units: "kPa",
            typicalRange: .init(min: 0, max: 20000), // 0–20 MPa
            warningRange: nil,
            dangerRange: nil,
            notes: "Display as MPa/PSI elsewhere if preferred"
        ),
        OBDPID(
            enabled: false,
            name: "Fuel Rail Pressure (Direct Injection)",
            pid: OBDCommand.Mode1.fuelRailPressureDirect,
            formula: "((A*256)+B) * 10",
            units: "kPa",
            typicalRange: .init(min: 0, max: 20000), // 0–20 MPa
            warningRange: nil,
            dangerRange: nil,
            notes: "DI rail; convert to MPa/PSI elsewhere"
        ),
        OBDPID(
            enabled: false,
            name: "Fuel Rail Pressure (Vacuum Referenced)",
            pid: OBDCommand.Mode1.fuelRailPressureVac,
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
            name: "Mass Air Flow (MAF)",
            pid: OBDCommand.Mode1.maf,
            formula: "((A*256)+B)/100",
            units: "g/s",
            typicalRange: .init(min: 0, max: 300),
            warningRange: nil,
            dangerRange: nil,
            notes: "Wide range; linear bar reads well; scale by engine size"
        ),
        OBDPID(
            enabled: false,
            name: "Fuel Rate",
            pid: OBDCommand.Mode1.fuelRate,
            formula: "((A*256)+B)/20",
            units: "L/h",
            typicalRange: .init(min: 0, max: 50),
            warningRange: nil,
            dangerRange: nil,
            notes: "Typical 0–50 L/h; tank/diesel may go higher"
        ),
        OBDPID(
            enabled: false,
            name: "Relative Accelerator Position",
            pid: OBDCommand.Mode1.relativeAccelPos,
            formula: "A * 100/255",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "Pedal position relative to calibrated range"
        ),
        OBDPID(
            enabled: false,
            name: "Catalyst Temp (Bank 2, Sensor 1)",
            pid: OBDCommand.Mode1.catalystTempB2S1,
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Pre-cat temp; linear thermometer"
        ),
        OBDPID(
            enabled: false,
            name: "Catalyst Temp (Bank 1, Sensor 2)",
            pid: OBDCommand.Mode1.catalystTempB1S2,
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Post-cat temp; linear thermometer"
        ),
        OBDPID(
            enabled: false,
            name: "Catalyst Temp (Bank 2, Sensor 2)",
            pid: OBDCommand.Mode1.catalystTempB2S2,
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Post-cat temp; linear thermometer"
        ),
    ]
}
