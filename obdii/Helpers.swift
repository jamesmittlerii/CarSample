//
//  Helpers.swift
//  obdii
//
//  Created by cisstudent on 11/9/25.
//
import OSLog
import Foundation

struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let category: String
    let subsystem: String
    let message: String
}

func collectLogs(since: TimeInterval = -300) async throws -> Data {
    let subsystem = "com.rheosoft.obdii"
    // 1. Open the log store for the current process
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)

    // 2. Define a time range (e.g., last minute)
    let logStart = logStore.position(date: Date().addingTimeInterval(since))

    // 3. Fetch all entries since that position
    let allEntries = try logStore.getEntries(at: logStart)

    // 4. Narrow to OSLogEntryLog first to ease type-checking
    let logEntries = allEntries.compactMap { $0 as? OSLogEntryLog }

    // 5. Filter by subsystem and category
    let filtered = logEntries.filter {
        $0.subsystem == subsystem && ($0.category == "AppInit" || $0.category == "Connection" || $0.category == "Communication")
    }

    // 6. Map to your LogEntry structure
    let appLogs: [LogEntry] = filtered.map { entry in
        LogEntry(
            timestamp: entry.date,
            category: entry.category,
            subsystem: entry.subsystem,
            message: entry.composedMessage // Respects privacy masks
        )
    }

    let jsonData = try JSONEncoder().encode(appLogs)
    return jsonData
}

/// Builds a user-facing About detail string that matches CarPlay and Settings.
/// Example: "<DisplayName> v1.2.3 build:45"
func aboutDetailString(bundle: Bundle = .main) -> String {
    let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "App"
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    return "\(displayName) v\(version) build:\(build)"
}
