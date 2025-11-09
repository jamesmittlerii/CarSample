//
//  Helpers.swift
//  obdii
//
//  Created by cisstudent on 11/9/25.
//
import OSLog

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
    let oneMinAgo = logStore.position(date: Date().addingTimeInterval(since))

    // 3. Fetch all entries since that position
    let allEntries = try logStore.getEntries(at: oneMinAgo)

    // 4. Narrow to OSLogEntryLog first to ease type-checking
    let logEntries = allEntries.compactMap { $0 as? OSLogEntryLog }

    // 5. Filter by subsystem and category
    let filtered = logEntries.filter {
        $0.subsystem == subsystem && ($0.category == "Connection" || $0.category == "Communication")
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
