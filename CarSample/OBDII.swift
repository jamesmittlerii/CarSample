import CarPlay
import UIKit

// MARK: - Your OBDCode model (from before)
struct OBDCode: Identifiable, Codable {
    var id: String { code }
    let code: String
    let title: String
    let description: String
    let severity: Severity
    
    enum Severity: String, Codable {
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
        case critical = "Critical"
    }
}

// Example dataset
let exampleOBDCodes: [OBDCode] = [
    OBDCode(code: "P0300", title: "Random/Multiple Cylinder Misfire Detected",
            description: "Multiple cylinders are misfiring. Check spark plugs, coils, or injectors.",
            severity: .high),
    OBDCode(code: "P0171", title: "System Too Lean (Bank 1)",
            description: "The air-fuel mixture is too lean. Possible vacuum leak or bad MAF sensor.",
            severity: .moderate),
    OBDCode(code: "P0420", title: "Catalyst System Efficiency Below Threshold (Bank 1)",
            description: "Catalytic converter efficiency is below threshold. Check O₂ sensors or converter.",
            severity: .moderate),
    OBDCode(code: "P0442", title: "EVAP System Small Leak Detected",
            description: "Small vapor leak in the EVAP system, often caused by a loose gas cap.",
            severity: .low),
    OBDCode(code: "P0700", title: "Transmission Control System Malfunction",
            description: "Transmission control system fault. Check TCM for details.",
            severity: .high)
]

