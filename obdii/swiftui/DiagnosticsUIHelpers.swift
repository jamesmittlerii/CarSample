import Foundation
import SwiftOBD2

// Shared, platform-agnostic helpers for diagnostics UI

func severitySymbolName(for severity: CodeSeverity) -> String {
    switch severity {
    case .low:       return "exclamationmark.circle"
    case .moderate:  return "exclamationmark.triangle"
    case .high:      return "bolt.trianglebadge.exclamationmark"
    case .critical:  return "xmark.octagon"
    }
}

func severitySectionTitle(_ severity: CodeSeverity) -> String {
    switch severity {
    case .critical: return "Critical"
    case .high:     return "High Severity"
    case .moderate: return "Moderate"
    case .low:      return "Low"
    }
}
