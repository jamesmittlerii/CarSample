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
    let enabled: Bool
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
        enabled: Bool = false,
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
        self.enabled = enabled
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
        if let danger = dangerRange, danger.contains(value) {
            return .red
        }
        if let warn = warningRange, warn.contains(value) {
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
            enabled: true,
            name: "Intake Air Temp (IAT)",
            pid: OBDCommand.Mode1.intakeTemp,
            formula: "A – 40",
            units: "°C",
            typicalRange: .init(min: -20, max: 100),
            warningRange: .init(min: 50, max: 60),
            dangerRange: .init(min: 60, max: 100),
            notes: "Correlates with ambient and heat-soak."
        ),
        OBDPID(
            enabled: true,
            name: "OBD Module Voltage",
            pid: OBDCommand.Mode1.controlModuleVoltage,
            formula: "((A*256)+B)/1000",
            units: "V",
            typicalRange: .init(min: 0, max: 18),
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
            typicalRange: .init(min: 0, max: 130),
            warningRange: .init(min: 105, max: 115),
            dangerRange: .init(min: 115, max: 130),
            notes: "Subtract 40 offset"
        ),
        OBDPID(
            enabled: true,
            name: "Engine RPM",
            pid: OBDCommand.Mode1.rpm,
            formula: "((A*256)+B)/4",
            units: "RPM",
            typicalRange: .init(min: 0, max: 8500),
            warningRange: .init(min: 6000, max: 7500),
            dangerRange: .init(min: 7500, max: 8500),
            notes: "Main tachometer source"
        ),
        OBDPID(
            enabled: true,
            name: "Air-Fuel Ratio (λ)",
            pid: OBDCommand.Mode1.commandedEquivRatio,
            formula: "((A*256)+B)/32768",
            units: "λ",
            typicalRange: .init(min: 0.5, max: 2.0),
            warningRange: nil,
            dangerRange: nil,
            notes: "1.00 = stoich"
        ),
        OBDPID(
            enabled: true,
            name: "Vehicle Speed",
            pid: OBDCommand.Mode1.speed,
            formula: "A",
            units: "km/h",
            typicalRange: .init(min: 0, max: 250),
            warningRange: nil,
            dangerRange: nil,
            notes: nil
        ),
        OBDPID(
            enabled: true,
            name: "Engine Oil Temp",
            pid: OBDCommand.Mode1.engineOilTemp,
            formula: "A - 40",
            units: "°C",
            typicalRange: .init(min: 0, max: 160),
            warningRange: .init(min: 130, max: 140),
            dangerRange: .init(min: 140, max: 160),
            notes: "Optional PID"
        ),
        OBDPID(
            enabled: true,
            name: "Fuel Pressure",
            pid: OBDCommand.Mode1.fuelPressure,
            formula: "A*3",
            units: "kPa",
            typicalRange: .init(min: 0, max: 765),
            warningRange: nil,
            dangerRange: nil,
            notes: "Gauge fuel pressure"
        ),

        OBDPID(
            enabled: true,
            name: "Catalyst Temp (Bank 1, Sensor 1)",
            pid: OBDCommand.Mode1.catalystTempB1S1,
            formula: "((A*256)+B)/10",
            units: "°C",
            typicalRange: .init(min: 0, max: 1000),
            warningRange: .init(min: 900, max: 950),
            dangerRange: .init(min: 950, max: 1000),
            notes: "Pre-cat temp"
        ),
        
        OBDPID(
            enabled: true,
            name: "Throttle Position",
            pid: OBDCommand.Mode1.throttlePos,
            formula: "((A*256)+B)/10",
            units: "%",
            typicalRange: .init(min: 0, max: 100),
            warningRange: nil,
            dangerRange: nil,
            notes: "accelerator"
        ),
        
        OBDPID(
            enabled: true,
            name: "Ignition Timing",
            pid: OBDCommand.Mode1.timingAdvance,
            formula: "(A/2) – 64",
            units: "° BTDC",
            typicalRange: .init(min: 0, max: 45),
            warningRange: nil,
            dangerRange: nil,
            notes: "timing"
        ),
    ]
}
