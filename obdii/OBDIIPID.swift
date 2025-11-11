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
            label: "FuelStat",
            name: "Fuel System Status",
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
            label: "AFR Lam",
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
            formula: "((A*256)+B) - 32767",
            units: "Pa",
            typicalRange: .init(min: -2000, max: 2000),
            warningRange: nil,
            dangerRange: nil,
            notes: "Reported in Pa on some ECUs; verify units"
        )
        
        // GM extended commands
        ,

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
        )
        
    ]
}
