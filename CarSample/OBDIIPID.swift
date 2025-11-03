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
    let id: UUID
    let name: String
    let pid: OBDCommand.Mode1
    let formula: String
    let units: String
    let typicalRange: ValueRange
    let warningRange: ValueRange?
    let dangerRange: ValueRange?
    let notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        pid: OBDCommand.Mode1,
        formula: String,
        units: String,
        typicalRange: ValueRange,
        warningRange: ValueRange? = nil,
        dangerRange: ValueRange? = nil,
        notes: String? = nil
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
    }

    // MARK: - Derived Behavior

    /// Returns a display string for UI, e.g. "600 – 7000 RPM"
    var displayRange: String {
        String(
            format: "%.0f – %.0f %@",
            typicalRange.min,
            typicalRange.max,
            units
        )
    }

    /// Returns a color representing the current value’s state
    func color(for value: Double) -> Color {
        if let danger = dangerRange, !danger.contains(value) {
            return .red
        }
        if let warn = warningRange, !warn.contains(value) {
            return .yellow
        }
        if typicalRange.contains(value) {
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
            name: "OBD Module Voltage",
            pid: OBDCommand.Mode1.controlModuleVoltage,
            formula: "((A*256)+B)/1000",
            units: "V",
            typicalRange: .init(min: 11.5, max: 14.8),
            warningRange: .init(min: 11.0, max: 15.2),
            dangerRange: .init(min: 10.5, max: 15.5),
            notes: "Battery/alternator voltage"
        ),
        OBDPID(
            name: "Engine Coolant Temp",
            pid: OBDCommand.Mode1.coolantTemp,
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: 70, max: 105),
            warningRange: .init(min: 105, max: 115),
            dangerRange: .init(min: 115, max: 130),
            notes: "Subtract 40 offset"
        ),
        OBDPID(
            name: "Engine RPM",
            pid: OBDCommand.Mode1.rpm,
            formula: "((A*256)+B)/4",
            units: "RPM",
            typicalRange: .init(min: 600, max: 7000),
            warningRange: .init(min: 7000, max: 7500),
            dangerRange: .init(min: 7500, max: 8500),
            notes: "Main tachometer source"
        ),
        OBDPID(
            name: "Air-Fuel Ratio (λ)",
            pid: OBDCommand.Mode1.commandedEquivRatio,
            formula: "((A*256)+B)/32768",
            units: "λ",
            typicalRange: .init(min: 0.8, max: 1.2),
            warningRange: .init(min: 0.75, max: 1.25),
            dangerRange: .init(min: 0.7, max: 1.3),
            notes: "1.00 = stoich"
        ),
        OBDPID(
            name: "Vehicle Speed",
            pid: OBDCommand.Mode1.speed,
            formula: "A",
            units: "km/h / mph",
            typicalRange: .init(min: 0, max: 250),
            warningRange: nil,
            dangerRange: nil,
            notes: nil
        ),
        OBDPID(
            name: "Engine Oil Temp",
            pid: OBDCommand.Mode1.engineOilTemp,
            formula: "A - 40",
            units: "°C / °F",
            typicalRange: .init(min: 60, max: 130),
            warningRange: .init(min: 130, max: 140),
            dangerRange: .init(min: 140, max: 160),
            notes: "Optional PID"
        ),
        OBDPID(
            name: "Fuel Pressure",
            pid: OBDCommand.Mode1.fuelPressure,
            formula: "A*3",
            units: "kPa / psi",
            typicalRange: .init(min: 240, max: 450),
            warningRange: .init(min: 200, max: 500),
            dangerRange: nil,
            notes: "Gauge fuel pressure"
        ),

        OBDPID(
            name: "Catalyst Temp (Bank 1, Sensor 1)",
            pid: OBDCommand.Mode1.catalystTempB1S1,
            formula: "((A*256)+B)/10",
            units: "°C / °F",
            typicalRange: .init(min: 200, max: 900),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Pre-cat temp"
        ),
    ]
}
