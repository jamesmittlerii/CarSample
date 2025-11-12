import SwiftUI
import SwiftOBD2

// SwiftUI-specific color mapping for CodeSeverity
func severityColor(_ severity: CodeSeverity) -> Color {
    switch severity {
    case .low:
        return .yellow
    case .moderate:
        return .orange
    case .high:
        return .red
    case .critical:
        return Color(red: 0.85, green: 0.0, blue: 0.0)
    }
}
